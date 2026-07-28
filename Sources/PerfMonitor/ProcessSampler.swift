import Darwin
import Foundation

// MARK: - Model

struct ProcessMetricEntry: Identifiable {
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let memoryBytes: UInt64
}

// MARK: - Sampler

/// Samples per-process CPU and memory via libproc (proc_listpids / proc_pidinfo).
/// CPU% is computed as a delta between two calls, so the first call always returns 0% CPU.
final class ProcessSampler {

    private struct PreviousCPU {
        let totalNanos: UInt64
        let timestamp: Date
    }

    private var previousCPU: [Int32: PreviousCPU] = [:]

    /// Returns up to `topN` processes sorted by `sortKey`.
    func sample(topN: Int = 5, sortBy: ProcessSortKey = .cpu) -> [ProcessMetricEntry] {
        let pids = listAllPIDs()
        let now = Date()
        var entries: [ProcessMetricEntry] = []
        entries.reserveCapacity(pids.count)

        for pid in pids {
            var info = proc_taskinfo()
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info,
                                   Int32(MemoryLayout<proc_taskinfo>.size))
            guard ret > 0 else { continue }

            let totalNanos = info.pti_total_user + info.pti_total_system
            let memBytes = info.pti_resident_size

            var cpuPercent: Double = 0
            if let prev = previousCPU[pid], prev.timestamp < now {
                let elapsed = now.timeIntervalSince(prev.timestamp)
                if elapsed > 0 {
                    let delta = totalNanos >= prev.totalNanos ? totalNanos - prev.totalNanos : 0
                    cpuPercent = (Double(delta) / 1e9) / elapsed * 100
                }
            }
            previousCPU[pid] = PreviousCPU(totalNanos: totalNanos, timestamp: now)

            entries.append(ProcessMetricEntry(
                pid: pid,
                name: processName(pid: pid),
                cpuPercent: cpuPercent,
                memoryBytes: memBytes
            ))
        }

        // Remove stale entries
        let currentSet = Set(pids)
        previousCPU = previousCPU.filter { currentSet.contains($0.key) }

        switch sortBy {
        case .cpu:
            entries.sort { $0.cpuPercent > $1.cpuPercent }
        case .memory:
            entries.sort { $0.memoryBytes > $1.memoryBytes }
        }
        return Array(entries.prefix(topN))
    }

    // MARK: - Private helpers

    private func listAllPIDs() -> [Int32] {
        // First call with nil buffer returns the required byte count
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }
        let capacity = Int(byteCount) / MemoryLayout<Int32>.size
        var pids = [Int32](repeating: 0, count: capacity)
        let actual = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids,
                                   Int32(capacity * MemoryLayout<Int32>.size))
        guard actual > 0 else { return [] }
        let count = Int(actual) / MemoryLayout<Int32>.size
        return Array(pids.prefix(count)).filter { $0 > 0 }
    }

    private func processName(pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: Int(PROC_PIDPATHINFO_MAXSIZE))
        let ret = proc_name(pid, &buf, UInt32(PROC_PIDPATHINFO_MAXSIZE))
        if ret > 0, let s = String(cString: buf, encoding: .utf8), !s.isEmpty {
            return s
        }
        return "[\(pid)]"
    }
}

// MARK: - Sort key

enum ProcessSortKey: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "MEM"
    var id: String { rawValue }
}
