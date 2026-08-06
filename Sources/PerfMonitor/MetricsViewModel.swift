import Combine
import Foundation
import AppKit
import ServiceManagement
import UserNotifications

enum RefreshIntervalOption: String, CaseIterable, Identifiable {
    case halfSecond = "0.5s"
    case oneSecond = "1s"
    case twoSeconds = "2s"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .halfSecond: return 0.5
        case .oneSecond: return 1.0
        case .twoSeconds: return 2.0
        }
    }
}

enum LaunchAtLoginStatus: String {
    case enabled = "Enabled"
    case disabled = "Disabled"
    case requiresApproval = "Requires Approval"
    case unsupported = "Unsupported"
    case error = "Error"
}

enum HistoryTimeRange: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case oneDay = "24h"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .oneDay: return 24 * 3600
        }
    }
}

enum HistoryMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case download = "Download"
    case upload = "Upload"
    case diskRead = "Disk Read"
    case diskWrite = "Disk Write"

    var id: String { rawValue }
}

struct MetricsSnapshot: Codable {
    let cpuUsagePercent: Double
    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    let uploadBytesPerSecond: Double
    let downloadBytesPerSecond: Double
    let diskReadBytesPerSecond: Double
    let diskWriteBytesPerSecond: Double
    let diskUsedBytes: UInt64
    let diskTotalBytes: UInt64
    let fps: Double
    let sampledAt: Date

    enum CodingKeys: String, CodingKey {
        case cpuUsagePercent
        case memoryUsedBytes
        case memoryTotalBytes
        case uploadBytesPerSecond
        case downloadBytesPerSecond
        case diskReadBytesPerSecond
        case diskWriteBytesPerSecond
        case diskUsedBytes
        case diskTotalBytes
        case fps
        case sampledAt
    }

    init(
        cpuUsagePercent: Double,
        memoryUsedBytes: UInt64,
        memoryTotalBytes: UInt64,
        uploadBytesPerSecond: Double,
        downloadBytesPerSecond: Double,
        diskReadBytesPerSecond: Double,
        diskWriteBytesPerSecond: Double,
        diskUsedBytes: UInt64,
        diskTotalBytes: UInt64,
        fps: Double,
        sampledAt: Date
    ) {
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.fps = fps
        self.sampledAt = sampledAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cpuUsagePercent = try c.decodeIfPresent(Double.self, forKey: .cpuUsagePercent) ?? 0
        memoryUsedBytes = try c.decodeIfPresent(UInt64.self, forKey: .memoryUsedBytes) ?? 0
        memoryTotalBytes = try c.decodeIfPresent(UInt64.self, forKey: .memoryTotalBytes) ?? ProcessInfo.processInfo.physicalMemory
        uploadBytesPerSecond = try c.decodeIfPresent(Double.self, forKey: .uploadBytesPerSecond) ?? 0
        downloadBytesPerSecond = try c.decodeIfPresent(Double.self, forKey: .downloadBytesPerSecond) ?? 0
        diskReadBytesPerSecond = try c.decodeIfPresent(Double.self, forKey: .diskReadBytesPerSecond) ?? 0
        diskWriteBytesPerSecond = try c.decodeIfPresent(Double.self, forKey: .diskWriteBytesPerSecond) ?? 0
        diskUsedBytes = try c.decodeIfPresent(UInt64.self, forKey: .diskUsedBytes) ?? 0
        diskTotalBytes = try c.decodeIfPresent(UInt64.self, forKey: .diskTotalBytes) ?? 0
        fps = try c.decodeIfPresent(Double.self, forKey: .fps) ?? 0
        sampledAt = try c.decodeIfPresent(Date.self, forKey: .sampledAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cpuUsagePercent, forKey: .cpuUsagePercent)
        try c.encode(memoryUsedBytes, forKey: .memoryUsedBytes)
        try c.encode(memoryTotalBytes, forKey: .memoryTotalBytes)
        try c.encode(uploadBytesPerSecond, forKey: .uploadBytesPerSecond)
        try c.encode(downloadBytesPerSecond, forKey: .downloadBytesPerSecond)
        try c.encode(diskReadBytesPerSecond, forKey: .diskReadBytesPerSecond)
        try c.encode(diskWriteBytesPerSecond, forKey: .diskWriteBytesPerSecond)
        try c.encode(diskUsedBytes, forKey: .diskUsedBytes)
        try c.encode(diskTotalBytes, forKey: .diskTotalBytes)
        try c.encode(fps, forKey: .fps)
        try c.encode(sampledAt, forKey: .sampledAt)
    }

    static let empty = MetricsSnapshot(
        cpuUsagePercent: 0,
        memoryUsedBytes: 0,
        memoryTotalBytes: ProcessInfo.processInfo.physicalMemory,
        uploadBytesPerSecond: 0,
        downloadBytesPerSecond: 0,
        diskReadBytesPerSecond: 0,
        diskWriteBytesPerSecond: 0,
        diskUsedBytes: 0,
        diskTotalBytes: 0,
        fps: 0,
        sampledAt: Date()
    )
}

@MainActor
final class MetricsViewModel: ObservableObject {
    @Published private(set) var snapshot: MetricsSnapshot = .empty
    @Published private(set) var history: [MetricsSnapshot] = []
    @Published private(set) var longHistory: [MetricsSnapshot] = []
    @Published private(set) var topProcesses: [ProcessMetricEntry] = []

    @Published var refreshInterval: RefreshIntervalOption {
        didSet {
            guard oldValue != refreshInterval else { return }
            persist(refreshInterval.rawValue, forKey: Keys.refreshInterval)
            start()
        }
    }

    @Published var showCPU = true { didSet { persist(showCPU, forKey: Keys.showCPU) } }
    @Published var showMemory = true { didSet { persist(showMemory, forKey: Keys.showMemory) } }
    @Published var showNetwork = true { didSet { persist(showNetwork, forKey: Keys.showNetwork) } }
    @Published var showDisk = true { didSet { persist(showDisk, forKey: Keys.showDisk) } }
    @Published var showFPS = true { didSet { persist(showFPS, forKey: Keys.showFPS) } }

    @Published var showMenuBarCPU = true { didSet { persist(showMenuBarCPU, forKey: Keys.showMenuBarCPU) } }
    @Published var showMenuBarDownload = true { didSet { persist(showMenuBarDownload, forKey: Keys.showMenuBarDownload) } }
    @Published var showMenuBarUpload = false { didSet { persist(showMenuBarUpload, forKey: Keys.showMenuBarUpload) } }

    @Published var cpuAlertThresholdPercent = 85.0 {
        didSet { persist(cpuAlertThresholdPercent, forKey: Keys.cpuAlertThreshold) }
    }
    @Published var memoryAlertThresholdPercent = 85.0 {
        didSet { persist(memoryAlertThresholdPercent, forKey: Keys.memoryAlertThreshold) }
    }
    @Published var diskAlertThresholdPercent = 85.0 {
        didSet { persist(diskAlertThresholdPercent, forKey: Keys.diskAlertThreshold) }
    }
    @Published var networkAlertThresholdMBps = 20.0 {
        didSet { persist(networkAlertThresholdMBps, forKey: Keys.networkAlertThreshold) }
    }
    @Published var notificationsEnabled = false {
        didSet {
            persist(notificationsEnabled, forKey: Keys.notificationsEnabled)
            if notificationsEnabled { requestNotificationPermission() }
        }
    }

    @Published var launchAtLoginEnabled = false {
        didSet {
            persist(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled)
            guard launchAtLoginEnabled != oldValue else { return }
            updateLaunchAtLogin()
        }
    }
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .unsupported
    @Published private(set) var launchAtLoginMessage: String?

    @Published var theme: AppTheme { didSet { persist(theme.rawValue, forKey: Keys.theme) } }

    @Published var overlayEnabled = false { didSet { persist(overlayEnabled, forKey: Keys.overlayEnabled) } }
    @Published var overlayOpacity: Double { didSet { persist(overlayOpacity, forKey: Keys.overlayOpacity) } }

    @Published var historyWindowVisible = false
    @Published var diskCleanupWindowVisible = false
    @Published var importError: String?
    @Published var historyExportError: String?
    @Published private(set) var diskCleanupItems: [DiskCleanupItem] = []
    @Published private(set) var diskCleanupIsScanning = false
    @Published private(set) var diskCleanupCleaningCategories: Set<DiskCleanupCategory> = []
    @Published private(set) var diskCleanupLastScannedAt: Date?
    @Published var diskCleanupMessage: String?
    @Published var diskCleanupError: String?
    @Published private(set) var diskCleanupSelectedCandidateIDs: Set<String> = []

    @Published var topProcessSortKey: ProcessSortKey = .cpu {
        didSet { topProcesses = processSampler.sample(topN: 5, sortBy: topProcessSortKey) }
    }

    private let provider: SystemMetricsProvider
    private let diskCleanupService = DiskCleanupService()
    private let processSampler = ProcessSampler()
    private let preferencesStore = PreferencesStore()
    private let historyStore = HistoryStore(retentionDays: 7)
    private var ticker: AnyCancellable?
    private let historyLimit: Int
    private let historyRetentionDays: Int = 7
    private let userDefaults: UserDefaults
    private var previousAlertState: [String: Bool] = [:]
    private var lastNotificationTime: [String: Date] = [:]
    private let notificationCooldown: TimeInterval = 60
    private var lastPersistedAt: Date = .distantPast
    private var terminationObserver: NSObjectProtocol?

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let showCPU = "showCPU"
        static let showMemory = "showMemory"
        static let showNetwork = "showNetwork"
        static let showDisk = "showDisk"
        static let showFPS = "showFPS"
        static let showMenuBarCPU = "showMenuBarCPU"
        static let showMenuBarDownload = "showMenuBarDownload"
        static let showMenuBarUpload = "showMenuBarUpload"
        static let cpuAlertThreshold = "cpuAlertThresholdPercent"
        static let memoryAlertThreshold = "memoryAlertThresholdPercent"
        static let diskAlertThreshold = "diskAlertThresholdPercent"
        static let networkAlertThreshold = "networkAlertThresholdMBps"
        static let notificationsEnabled = "notificationsEnabled"
        static let theme = "theme"
        static let overlayEnabled = "overlayEnabled"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let overlayOpacity = "overlayOpacity"
    }

    init(
        provider: SystemMetricsProvider,
        defaultRefreshInterval: RefreshIntervalOption = .oneSecond,
        historyLimit: Int = 60,
        userDefaults: UserDefaults = .standard
    ) {
        self.provider = provider
        self.historyLimit = historyLimit
        self.userDefaults = userDefaults

        let persistedSettings = preferencesStore.load()
        let legacySettings: AppSettings? = {
            guard userDefaults.object(forKey: Keys.showCPU) != nil ||
                  userDefaults.object(forKey: Keys.refreshInterval) != nil else {
                return nil
            }

            return AppSettings(
                refreshInterval: userDefaults.string(forKey: Keys.refreshInterval) ?? RefreshIntervalOption.oneSecond.rawValue,
                showCPU: userDefaults.object(forKey: Keys.showCPU) as? Bool ?? true,
                showMemory: userDefaults.object(forKey: Keys.showMemory) as? Bool ?? true,
                showNetwork: userDefaults.object(forKey: Keys.showNetwork) as? Bool ?? true,
                showDisk: userDefaults.object(forKey: Keys.showDisk) as? Bool ?? true,
                showFPS: userDefaults.object(forKey: Keys.showFPS) as? Bool ?? true,
                showMenuBarCPU: userDefaults.object(forKey: Keys.showMenuBarCPU) as? Bool ?? true,
                showMenuBarDownload: userDefaults.object(forKey: Keys.showMenuBarDownload) as? Bool ?? true,
                showMenuBarUpload: userDefaults.object(forKey: Keys.showMenuBarUpload) as? Bool ?? false,
                cpuAlertThresholdPercent: userDefaults.object(forKey: Keys.cpuAlertThreshold) as? Double ?? 85,
                memoryAlertThresholdPercent: userDefaults.object(forKey: Keys.memoryAlertThreshold) as? Double ?? 85,
                diskAlertThresholdPercent: userDefaults.object(forKey: Keys.diskAlertThreshold) as? Double ?? 85,
                networkAlertThresholdMBps: userDefaults.object(forKey: Keys.networkAlertThreshold) as? Double ?? 20,
                notificationsEnabled: userDefaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? false,
                theme: userDefaults.string(forKey: Keys.theme) ?? AppTheme.system.rawValue,
                overlayEnabled: userDefaults.object(forKey: Keys.overlayEnabled) as? Bool ?? false,
                launchAtLoginEnabled: userDefaults.object(forKey: Keys.launchAtLoginEnabled) as? Bool ?? false,
                overlayOpacity: userDefaults.object(forKey: Keys.overlayOpacity) as? Double ?? 0.85
            )
        }()
        var settings = persistedSettings ?? legacySettings ?? .default
        if persistedSettings == nil && legacySettings == nil {
            settings.refreshInterval = defaultRefreshInterval.rawValue
        }

        refreshInterval = RefreshIntervalOption(rawValue: settings.refreshInterval) ?? defaultRefreshInterval
        showCPU = settings.showCPU
        showMemory = settings.showMemory
        showNetwork = settings.showNetwork
        showDisk = settings.showDisk
        showFPS = settings.showFPS
        showMenuBarCPU = settings.showMenuBarCPU
        showMenuBarDownload = settings.showMenuBarDownload
        showMenuBarUpload = settings.showMenuBarUpload
        cpuAlertThresholdPercent = settings.cpuAlertThresholdPercent
        memoryAlertThresholdPercent = settings.memoryAlertThresholdPercent
        diskAlertThresholdPercent = settings.diskAlertThresholdPercent
        networkAlertThresholdMBps = settings.networkAlertThresholdMBps
        notificationsEnabled = settings.notificationsEnabled
        theme = AppTheme(rawValue: settings.theme) ?? .system
        overlayEnabled = settings.overlayEnabled
        launchAtLoginEnabled = settings.launchAtLoginEnabled
        overlayOpacity = settings.overlayOpacity

        if persistedSettings == nil {
            preferencesStore.save(settings)
        }

        longHistory = historyStore.load()
        pruneLongHistory(reference: Date())
        history = Array(longHistory.suffix(historyLimit))

        reconcileLaunchAtLoginPreference()
        observeTermination()
        refresh()
        start()
    }

    func isCPUAlerting(for snapshot: MetricsSnapshot) -> Bool {
        snapshot.cpuUsagePercent >= cpuAlertThresholdPercent
    }

    func isMemoryAlerting(for snapshot: MetricsSnapshot) -> Bool {
        guard snapshot.memoryTotalBytes > 0 else { return false }
        let percent = Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes) * 100
        return percent >= memoryAlertThresholdPercent
    }

    func isDiskSpaceAlerting(for snapshot: MetricsSnapshot) -> Bool {
        let percent = MetricFormatting.diskUsagePercent(used: snapshot.diskUsedBytes, total: snapshot.diskTotalBytes)
        return percent >= diskAlertThresholdPercent
    }

    func isUploadAlerting(for snapshot: MetricsSnapshot) -> Bool {
        snapshot.uploadBytesPerSecond >= networkAlertThresholdBytesPerSecond
    }

    func isDownloadAlerting(for snapshot: MetricsSnapshot) -> Bool {
        snapshot.downloadBytesPerSecond >= networkAlertThresholdBytesPerSecond
    }

    var menuBarTitle: String {
        var parts: [String] = []
        if showMenuBarCPU {
            parts.append("CPU \(String(format: "%.0f%%", snapshot.cpuUsagePercent))")
        }
        if showMenuBarDownload {
            parts.append("\(MetricFormatting.speed(snapshot.downloadBytesPerSecond))/s↓")
        }
        if showMenuBarUpload {
            parts.append("\(MetricFormatting.speed(snapshot.uploadBytesPerSecond))/s↑")
        }
        return parts.isEmpty ? "PerfMonitor" : parts.joined(separator: " | ")
    }

    func historyData(for range: HistoryTimeRange, maxPoints: Int = 720) -> [MetricsSnapshot] {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        let filtered = longHistory.filter { $0.sampledAt >= cutoff }
        return downsample(filtered, to: maxPoints)
    }

    func historyValue(for metric: HistoryMetric, snapshot: MetricsSnapshot) -> Double {
        switch metric {
        case .cpu:
            return snapshot.cpuUsagePercent
        case .memory:
            guard snapshot.memoryTotalBytes > 0 else { return 0 }
            return Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes) * 100
        case .download:
            return snapshot.downloadBytesPerSecond
        case .upload:
            return snapshot.uploadBytesPerSecond
        case .diskRead:
            return snapshot.diskReadBytesPerSecond
        case .diskWrite:
            return snapshot.diskWriteBytesPerSecond
        }
    }

    func historyValueText(for metric: HistoryMetric, snapshot: MetricsSnapshot) -> String {
        switch metric {
        case .cpu, .memory:
            return String(format: "%.1f%%", historyValue(for: metric, snapshot: snapshot))
        case .download, .upload, .diskRead, .diskWrite:
            return "\(MetricFormatting.speed(historyValue(for: metric, snapshot: snapshot)))/s"
        }
    }

    func historyChartMaxY(for metric: HistoryMetric, data: [MetricsSnapshot]) -> Double {
        switch metric {
        case .cpu, .memory:
            return 100
        case .download, .upload, .diskRead, .diskWrite:
            let maxValue = data.map { historyValue(for: metric, snapshot: $0) }.max() ?? 1
            return max(maxValue * 1.1, 1)
        }
    }

    func exportHistoryData(as format: HistoryExportFormat) throws -> Data {
        try historyStore.export(longHistory, as: format)
    }

    func exportSettings() throws -> Data {
        try preferencesStore.exportData(currentPreferences)
    }

    func refreshDiskCleanupItems() {
        guard !diskCleanupIsScanning else { return }
        diskCleanupIsScanning = true
        diskCleanupError = nil

        Task {
            let items = await diskCleanupService.scanItems()
            diskCleanupItems = items
            pruneDiskCleanupSelection(using: items)
            diskCleanupLastScannedAt = Date()
            diskCleanupIsScanning = false
        }
    }

    func cleanDiskCleanupCategory(_ category: DiskCleanupCategory) {
        guard !diskCleanupCleaningCategories.contains(category) else { return }
        diskCleanupError = nil
        diskCleanupMessage = nil
        diskCleanupCleaningCategories.insert(category)

        Task {
            do {
                let result = try await diskCleanupService.clean(category: category)
                let items = await diskCleanupService.scanItems()
                diskCleanupItems = items
                pruneDiskCleanupSelection(using: items)
                diskCleanupLastScannedAt = Date()
                diskCleanupMessage = result.freedBytes > 0
                    ? "Freed \(MetricFormatting.bytes(result.freedBytes)) from \(category.title)"
                    : "No removable files found in \(category.title)"
                if !result.failedPaths.isEmpty {
                    diskCleanupError = "Failed to remove \(result.failedPaths.count) item(s) from \(category.title)"
                }
            } catch {
                diskCleanupError = "Cleanup failed for \(category.title): \(error.localizedDescription)"
            }

            diskCleanupCleaningCategories.remove(category)
        }
    }

    func toggleDiskCleanupCandidate(_ candidate: DiskCleanupCandidate) {
        if diskCleanupSelectedCandidateIDs.contains(candidate.id) {
            diskCleanupSelectedCandidateIDs.remove(candidate.id)
        } else {
            diskCleanupSelectedCandidateIDs.insert(candidate.id)
        }
    }

    func setDiskCleanupSelection(_ isSelected: Bool, candidates: [DiskCleanupCandidate]) {
        let ids = candidates.map(\.id)
        if isSelected {
            diskCleanupSelectedCandidateIDs.formUnion(ids)
        } else {
            diskCleanupSelectedCandidateIDs.subtract(ids)
        }
    }

    func isDiskCleanupCandidateSelected(_ candidate: DiskCleanupCandidate) -> Bool {
        diskCleanupSelectedCandidateIDs.contains(candidate.id)
    }

    func selectedDiskCleanupCandidates(for item: DiskCleanupItem) -> [DiskCleanupCandidate] {
        item.topCandidates.filter { diskCleanupSelectedCandidateIDs.contains($0.id) }
    }

    func cleanSelectedDiskCleanupCandidates(in item: DiskCleanupItem) {
        let candidates = selectedDiskCleanupCandidates(for: item)
        guard !candidates.isEmpty else { return }

        let category = item.category
        diskCleanupError = nil
        diskCleanupMessage = nil
        diskCleanupCleaningCategories.insert(category)

        Task {
            do {
                let result = try await diskCleanupService.clean(
                    category: category,
                    candidatePaths: candidates.map(\.path)
                )
                let items = await diskCleanupService.scanItems()
                diskCleanupItems = items
                pruneDiskCleanupSelection(using: items)
                diskCleanupLastScannedAt = Date()
                diskCleanupMessage = result.freedBytes > 0
                    ? "Freed \(MetricFormatting.bytes(result.freedBytes)) from \(result.cleanedPaths.count) selected item(s)"
                    : "No selected items were removed"
                if !result.failedPaths.isEmpty {
                    diskCleanupError = "Failed to remove \(result.failedPaths.count) selected item(s)"
                }
            } catch {
                diskCleanupError = "Cleanup failed for selected items: \(error.localizedDescription)"
            }

            diskCleanupCleaningCategories.remove(category)
        }
    }

    func isCleaningDiskCategory(_ category: DiskCleanupCategory) -> Bool {
        diskCleanupCleaningCategories.contains(category)
    }

    private func pruneDiskCleanupSelection(using items: [DiskCleanupItem]) {
        let validIDs = Set(items.flatMap { $0.topCandidates.map(\.id) })
        diskCleanupSelectedCandidateIDs = diskCleanupSelectedCandidateIDs.intersection(validIDs)
    }

    func importSettings(from data: Data) {
        do {
            let settings = try preferencesStore.decode(data)
            applySettings(settings)
            importError = nil
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }
    }

    private func applySettings(_ s: AppSettings) {
        applyPreferences(s)
        preferencesStore.save(s)
    }

    private var networkAlertThresholdBytesPerSecond: Double {
        networkAlertThresholdMBps * 1024 * 1024
    }

    private var currentPreferences: AppSettings {
        AppSettings(
            refreshInterval: refreshInterval.rawValue,
            showCPU: showCPU,
            showMemory: showMemory,
            showNetwork: showNetwork,
            showDisk: showDisk,
            showFPS: showFPS,
            showMenuBarCPU: showMenuBarCPU,
            showMenuBarDownload: showMenuBarDownload,
            showMenuBarUpload: showMenuBarUpload,
            cpuAlertThresholdPercent: cpuAlertThresholdPercent,
            memoryAlertThresholdPercent: memoryAlertThresholdPercent,
            diskAlertThresholdPercent: diskAlertThresholdPercent,
            networkAlertThresholdMBps: networkAlertThresholdMBps,
            notificationsEnabled: notificationsEnabled,
            theme: theme.rawValue,
            overlayEnabled: overlayEnabled,
            launchAtLoginEnabled: launchAtLoginEnabled,
            overlayOpacity: overlayOpacity
        )
    }

    private func applyPreferences(_ s: AppSettings) {
        refreshInterval = RefreshIntervalOption(rawValue: s.refreshInterval) ?? .oneSecond
        showCPU = s.showCPU
        showMemory = s.showMemory
        showNetwork = s.showNetwork
        showDisk = s.showDisk
        showFPS = s.showFPS
        showMenuBarCPU = s.showMenuBarCPU
        showMenuBarDownload = s.showMenuBarDownload
        showMenuBarUpload = s.showMenuBarUpload
        cpuAlertThresholdPercent = s.cpuAlertThresholdPercent
        memoryAlertThresholdPercent = s.memoryAlertThresholdPercent
        diskAlertThresholdPercent = s.diskAlertThresholdPercent
        networkAlertThresholdMBps = s.networkAlertThresholdMBps
        notificationsEnabled = s.notificationsEnabled
        theme = AppTheme(rawValue: s.theme) ?? .system
        overlayEnabled = s.overlayEnabled
        launchAtLoginEnabled = s.launchAtLoginEnabled
        overlayOpacity = s.overlayOpacity
    }

    private func persist(_ value: some Any, forKey key: String) {
        preferencesStore.save(currentPreferences)
    }

    private func start() {
        ticker?.cancel()
        ticker = Timer.publish(every: refreshInterval.seconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        snapshot = provider.readSnapshot()
        history.append(snapshot)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
        longHistory.append(snapshot)
        pruneLongHistory(reference: snapshot.sampledAt)
        evaluateAlerts(snapshot: snapshot)
        persistHistory(force: false)
        topProcesses = processSampler.sample(topN: 5, sortBy: topProcessSortKey)
    }

    private func observeTermination() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.persistHistory(force: true)
            }
        }
    }

    private func persistHistory(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPersistedAt) >= 10 else { return }
        lastPersistedAt = now
        historyStore.save(longHistory)
    }

    private func pruneLongHistory(reference: Date) {
        let cutoff = reference.addingTimeInterval(-TimeInterval(historyRetentionDays * 24 * 3600))
        longHistory.removeAll { $0.sampledAt < cutoff }
    }

    private func downsample(_ data: [MetricsSnapshot], to maxPoints: Int) -> [MetricsSnapshot] {
        guard data.count > maxPoints, maxPoints > 1 else { return data }
        let step = Int(ceil(Double(data.count) / Double(maxPoints)))
        return stride(from: 0, to: data.count, by: step).map { data[$0] }
    }

    private func evaluateAlerts(snapshot: MetricsSnapshot) {
        processAlert(
            key: "cpu",
            isTriggered: isCPUAlerting(for: snapshot),
            title: "CPU usage alert",
            body: String(format: "CPU reached %.1f%%", snapshot.cpuUsagePercent)
        )
        let memPct = snapshot.memoryTotalBytes > 0
            ? Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes) * 100 : 0
        processAlert(
            key: "memory",
            isTriggered: isMemoryAlerting(for: snapshot),
            title: "Memory usage alert",
            body: String(format: "Memory reached %.1f%%", memPct)
        )
        processAlert(
            key: "disk",
            isTriggered: isDiskSpaceAlerting(for: snapshot),
            title: "Disk space alert",
            body: String(format: "Disk usage reached %.1f%%", MetricFormatting.diskUsagePercent(used: snapshot.diskUsedBytes, total: snapshot.diskTotalBytes))
        )
        processAlert(
            key: "download",
            isTriggered: isDownloadAlerting(for: snapshot),
            title: "Download traffic alert",
            body: "Download reached \(MetricFormatting.speed(snapshot.downloadBytesPerSecond))/s"
        )
        processAlert(
            key: "upload",
            isTriggered: isUploadAlerting(for: snapshot),
            title: "Upload traffic alert",
            body: "Upload reached \(MetricFormatting.speed(snapshot.uploadBytesPerSecond))/s"
        )
    }

    private func processAlert(key: String, isTriggered: Bool, title: String, body: String) {
        let wasTriggered = previousAlertState[key] ?? false
        previousAlertState[key] = isTriggered
        guard notificationsEnabled, isTriggered, !wasTriggered else { return }
        let now = Date()
        guard now.timeIntervalSince(lastNotificationTime[key] ?? .distantPast) >= notificationCooldown else { return }
        lastNotificationTime[key] = now
        sendNotification(title: title, body: body)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "perfmonitor.\(title).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func reconcileLaunchAtLoginPreference() {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                launchAtLoginStatus = .enabled
            case .requiresApproval:
                launchAtLoginStatus = .requiresApproval
            default:
                launchAtLoginStatus = .disabled
            }

            if launchAtLoginEnabled {
                if launchAtLoginStatus == .disabled {
                    updateLaunchAtLogin()
                }
            } else if launchAtLoginStatus != .disabled {
                updateLaunchAtLogin()
            }
        } else {
            launchAtLoginStatus = .unsupported
        }
    }

    private func updateLaunchAtLogin() {
        guard #available(macOS 13.0, *) else {
            launchAtLoginStatus = .unsupported
            launchAtLoginMessage = "Current macOS version does not support this API."
            return
        }
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.register()
                launchAtLoginStatus = .enabled
            } else {
                try SMAppService.mainApp.unregister()
                launchAtLoginStatus = .disabled
            }
            launchAtLoginMessage = nil
        } catch {
            launchAtLoginEnabled.toggle()
            launchAtLoginStatus = .error
            launchAtLoginMessage = error.localizedDescription
        }
    }
}
