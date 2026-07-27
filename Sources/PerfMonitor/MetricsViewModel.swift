import Combine
import Foundation
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

struct MetricsSnapshot {
    let cpuUsagePercent: Double
    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    let uploadBytesPerSecond: Double
    let downloadBytesPerSecond: Double
    let diskReadBytesPerSecond: Double
    let diskWriteBytesPerSecond: Double
    let fps: Double
    let sampledAt: Date

    static let empty = MetricsSnapshot(
        cpuUsagePercent: 0,
        memoryUsedBytes: 0,
        memoryTotalBytes: ProcessInfo.processInfo.physicalMemory,
        uploadBytesPerSecond: 0,
        downloadBytesPerSecond: 0,
        diskReadBytesPerSecond: 0,
        diskWriteBytesPerSecond: 0,
        fps: 0,
        sampledAt: Date()
    )
}

@MainActor
final class MetricsViewModel: ObservableObject {
    @Published private(set) var snapshot: MetricsSnapshot = .empty
    @Published private(set) var history: [MetricsSnapshot] = []
    @Published private(set) var longHistory: [MetricsSnapshot] = []

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
            guard launchAtLoginEnabled != oldValue else { return }
            updateLaunchAtLogin()
        }
    }
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .unsupported
    @Published private(set) var launchAtLoginMessage: String?

    @Published var theme: AppTheme { didSet { persist(theme.rawValue, forKey: Keys.theme) } }

    @Published var overlayEnabled = false
    @Published var overlayOpacity: Double { didSet { persist(overlayOpacity, forKey: Keys.overlayOpacity) } }

    @Published var historyWindowVisible = false
    @Published var importError: String?

    private let provider: SystemMetricsProvider
    private var ticker: AnyCancellable?
    private let historyLimit: Int
    private let userDefaults: UserDefaults
    private var previousAlertState: [String: Bool] = [:]
    private var lastNotificationTime: [String: Date] = [:]
    private let notificationCooldown: TimeInterval = 60

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
        static let networkAlertThreshold = "networkAlertThresholdMBps"
        static let notificationsEnabled = "notificationsEnabled"
        static let theme = "theme"
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

        let stored = userDefaults.string(forKey: Keys.refreshInterval)
        refreshInterval = RefreshIntervalOption(rawValue: stored ?? "") ?? defaultRefreshInterval
        showCPU = userDefaults.object(forKey: Keys.showCPU) as? Bool ?? true
        showMemory = userDefaults.object(forKey: Keys.showMemory) as? Bool ?? true
        showNetwork = userDefaults.object(forKey: Keys.showNetwork) as? Bool ?? true
        showDisk = userDefaults.object(forKey: Keys.showDisk) as? Bool ?? true
        showFPS = userDefaults.object(forKey: Keys.showFPS) as? Bool ?? true
        showMenuBarCPU = userDefaults.object(forKey: Keys.showMenuBarCPU) as? Bool ?? true
        showMenuBarDownload = userDefaults.object(forKey: Keys.showMenuBarDownload) as? Bool ?? true
        showMenuBarUpload = userDefaults.object(forKey: Keys.showMenuBarUpload) as? Bool ?? false
        cpuAlertThresholdPercent = userDefaults.object(forKey: Keys.cpuAlertThreshold) as? Double ?? 85
        memoryAlertThresholdPercent = userDefaults.object(forKey: Keys.memoryAlertThreshold) as? Double ?? 85
        networkAlertThresholdMBps = userDefaults.object(forKey: Keys.networkAlertThreshold) as? Double ?? 20
        notificationsEnabled = userDefaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? false
        theme = AppTheme(rawValue: userDefaults.string(forKey: Keys.theme) ?? "") ?? .system
        overlayOpacity = userDefaults.object(forKey: Keys.overlayOpacity) as? Double ?? 0.85

        refreshLaunchAtLoginStatus()
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

    func exportSettings() throws -> Data {
        let settings = AppSettings(
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
            networkAlertThresholdMBps: networkAlertThresholdMBps,
            notificationsEnabled: notificationsEnabled,
            theme: theme.rawValue,
            overlayOpacity: overlayOpacity
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    func importSettings(from data: Data) {
        do {
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            applySettings(settings)
            importError = nil
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }
    }

    private func applySettings(_ s: AppSettings) {
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
        networkAlertThresholdMBps = s.networkAlertThresholdMBps
        notificationsEnabled = s.notificationsEnabled
        theme = AppTheme(rawValue: s.theme) ?? .system
        overlayOpacity = s.overlayOpacity
    }

    private var networkAlertThresholdBytesPerSecond: Double {
        networkAlertThresholdMBps * 1024 * 1024
    }

    private func persist(_ value: some Any, forKey key: String) {
        userDefaults.set(value, forKey: key)
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
    }

    private func pruneLongHistory(reference: Date) {
        let cutoff = reference.addingTimeInterval(-HistoryTimeRange.oneDay.seconds)
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

    private func refreshLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                launchAtLoginEnabled = true
                launchAtLoginStatus = .enabled
            case .requiresApproval:
                launchAtLoginEnabled = true
                launchAtLoginStatus = .requiresApproval
            default:
                launchAtLoginEnabled = false
                launchAtLoginStatus = .disabled
            }
        } else {
            launchAtLoginEnabled = false
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
