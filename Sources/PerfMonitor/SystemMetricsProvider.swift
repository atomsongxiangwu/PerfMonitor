import AppKit
import CoreVideo
import Darwin
import Foundation
import IOKit
import IOKit.storage

final class SystemMetricsProvider {
    private let pageSize: vm_size_t
    private let refreshRateFPS: Double

    private var previousCPUTicks: CPUTicks?
    private var previousNetworkSample: NetworkSample?
    private var previousDiskSample: DiskSample?
    private var lastCPUUsagePercent: Double = 0

    init() {
        var hostPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &hostPageSize)
        pageSize = hostPageSize
        refreshRateFPS = Self.currentDisplayRefreshRate() ?? 0
    }

    func readSnapshot() -> MetricsSnapshot {
        let cpuUsage = sampleCPUUsage() ?? lastCPUUsagePercent
        lastCPUUsagePercent = cpuUsage

        let memory = sampleMemoryUsage()
        let network = sampleNetworkRate()
        let disk = sampleDiskRate()
        let diskSpace = sampleDiskSpace()

        return MetricsSnapshot(
            cpuUsagePercent: cpuUsage,
            memoryUsedBytes: memory.used,
            memoryTotalBytes: memory.total,
            uploadBytesPerSecond: network.upload,
            downloadBytesPerSecond: network.download,
            diskReadBytesPerSecond: disk.read,
            diskWriteBytesPerSecond: disk.write,
            diskUsedBytes: diskSpace.used,
            diskTotalBytes: diskSpace.total,
            fps: refreshRateFPS,
            sampledAt: Date()
        )
    }
}

private extension SystemMetricsProvider {
    struct CPUTicks {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    struct NetworkCounters {
        let inBytes: UInt64
        let outBytes: UInt64
    }

    struct NetworkSample {
        let counters: NetworkCounters
        let timestamp: Date
    }

    struct DiskCounters {
        let readBytes: UInt64
        let writeBytes: UInt64
    }

    struct DiskSample {
        let counters: DiskCounters
        let timestamp: Date
    }

    func sampleCPUUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let current = CPUTicks(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )

        defer { previousCPUTicks = current }
        guard let previousCPUTicks else { return nil }

        let user = Double(current.user &- previousCPUTicks.user)
        let system = Double(current.system &- previousCPUTicks.system)
        let idle = Double(current.idle &- previousCPUTicks.idle)
        let nice = Double(current.nice &- previousCPUTicks.nice)

        let inUse = user + system + nice
        let total = inUse + idle

        guard total > 0 else { return nil }
        return inUse / total * 100
    }

    func sampleMemoryUsage() -> (used: UInt64, total: UInt64) {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, total) }

        let usedPages = UInt64(info.active_count)
            + UInt64(info.inactive_count)
            + UInt64(info.wire_count)
            + UInt64(info.compressor_page_count)
        let used = usedPages * UInt64(pageSize)
        return (used, total)
    }

    func sampleNetworkRate() -> (upload: Double, download: Double) {
        guard let currentCounters = readNetworkCounters() else { return (0, 0) }

        let currentSample = NetworkSample(counters: currentCounters, timestamp: Date())
        defer { previousNetworkSample = currentSample }

        guard let previousNetworkSample else { return (0, 0) }

        let duration = currentSample.timestamp.timeIntervalSince(previousNetworkSample.timestamp)
        guard duration > 0 else { return (0, 0) }

        let uploadDelta = currentSample.counters.outBytes >= previousNetworkSample.counters.outBytes
            ? currentSample.counters.outBytes - previousNetworkSample.counters.outBytes
            : 0
        let downloadDelta = currentSample.counters.inBytes >= previousNetworkSample.counters.inBytes
            ? currentSample.counters.inBytes - previousNetworkSample.counters.inBytes
            : 0

        return (
            upload: Double(uploadDelta) / duration,
            download: Double(downloadDelta) / duration
        )
    }

    func sampleDiskRate() -> (read: Double, write: Double) {
        guard let currentCounters = readDiskCounters() else { return (0, 0) }

        let currentSample = DiskSample(counters: currentCounters, timestamp: Date())
        defer { previousDiskSample = currentSample }

        guard let previousDiskSample else { return (0, 0) }

        let duration = currentSample.timestamp.timeIntervalSince(previousDiskSample.timestamp)
        guard duration > 0 else { return (0, 0) }

        let readDelta = currentSample.counters.readBytes >= previousDiskSample.counters.readBytes
            ? currentSample.counters.readBytes - previousDiskSample.counters.readBytes
            : 0
        let writeDelta = currentSample.counters.writeBytes >= previousDiskSample.counters.writeBytes
            ? currentSample.counters.writeBytes - previousDiskSample.counters.writeBytes
            : 0

        return (
            read: Double(readDelta) / duration,
            write: Double(writeDelta) / duration
        )
    }

    func sampleDiskSpace() -> (used: UInt64, total: UInt64) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = attrs[.systemSize] as? NSNumber,
              let free = attrs[.systemFreeSize] as? NSNumber else {
            return (0, 0)
        }

        let totalBytes = total.uint64Value
        let freeBytes = free.uint64Value
        let usedBytes = totalBytes > freeBytes ? totalBytes - freeBytes : 0
        return (usedBytes, totalBytes)
    }

    func readNetworkCounters() -> NetworkCounters? {
        var interfaceAddressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddressPointer) == 0 else {
            return nil
        }
        guard let firstAddress = interfaceAddressPointer else {
            return nil
        }
        defer { freeifaddrs(firstAddress) }

        var inBytes: UInt64 = 0
        var outBytes: UInt64 = 0

        for interface in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard isUp, isRunning, !isLoopback else { continue }

            guard interface.pointee.ifa_data != nil else { continue }
            let data = interface.pointee.ifa_data.assumingMemoryBound(to: if_data.self).pointee
            inBytes += UInt64(data.ifi_ibytes)
            outBytes += UInt64(data.ifi_obytes)
        }

        return NetworkCounters(inBytes: inBytes, outBytes: outBytes)
    }

    func readDiskCounters() -> DiskCounters? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else {
            return nil
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var readBytes: UInt64 = 0
        var writeBytes: UInt64 = 0

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            guard let cf = IORegistryEntryCreateCFProperty(
                service,
                kIOBlockStorageDriverStatisticsKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue(),
                  let stats = cf as? [String: Any] else {
                continue
            }

            if let val = stats[kIOBlockStorageDriverStatisticsBytesReadKey as String] as? NSNumber {
                readBytes += val.uint64Value
            }
            if let val = stats[kIOBlockStorageDriverStatisticsBytesWrittenKey as String] as? NSNumber {
                writeBytes += val.uint64Value
            }
        }

        return DiskCounters(readBytes: readBytes, writeBytes: writeBytes)
    }

    static func currentDisplayRefreshRate() -> Double? {
        if let screen = NSScreen.main, screen.maximumFramesPerSecond > 0 {
            return Double(screen.maximumFramesPerSecond)
        }

        var displayLink: CVDisplayLink?
        let result = CVDisplayLinkCreateWithCGDisplay(CGMainDisplayID(), &displayLink)
        guard result == kCVReturnSuccess, let displayLink else { return nil }

        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink)
        guard period.timeValue > 0, period.timeScale > 0 else { return nil }

        return Double(period.timeScale) / Double(period.timeValue)
    }
}
