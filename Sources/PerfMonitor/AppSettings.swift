import Foundation

struct AppSettings: Codable {
    var refreshInterval: String
    var showCPU: Bool
    var showMemory: Bool
    var showNetwork: Bool
    var showDisk: Bool
    var showFPS: Bool
    var showMenuBarCPU: Bool
    var showMenuBarDownload: Bool
    var showMenuBarUpload: Bool
    var cpuAlertThresholdPercent: Double
    var memoryAlertThresholdPercent: Double
    var diskAlertThresholdPercent: Double
    var networkAlertThresholdMBps: Double
    var notificationsEnabled: Bool
    var theme: String
    var overlayEnabled: Bool
    var launchAtLoginEnabled: Bool
    var overlayOpacity: Double

    enum CodingKeys: String, CodingKey {
        case refreshInterval
        case showCPU
        case showMemory
        case showNetwork
        case showDisk
        case showFPS
        case showMenuBarCPU
        case showMenuBarDownload
        case showMenuBarUpload
        case cpuAlertThresholdPercent
        case memoryAlertThresholdPercent
        case diskAlertThresholdPercent
        case networkAlertThresholdMBps
        case notificationsEnabled
        case theme
        case overlayEnabled
        case launchAtLoginEnabled
        case overlayOpacity
    }

    init(
        refreshInterval: String,
        showCPU: Bool,
        showMemory: Bool,
        showNetwork: Bool,
        showDisk: Bool,
        showFPS: Bool,
        showMenuBarCPU: Bool,
        showMenuBarDownload: Bool,
        showMenuBarUpload: Bool,
        cpuAlertThresholdPercent: Double,
        memoryAlertThresholdPercent: Double,
        diskAlertThresholdPercent: Double,
        networkAlertThresholdMBps: Double,
        notificationsEnabled: Bool,
        theme: String,
        overlayEnabled: Bool,
        launchAtLoginEnabled: Bool,
        overlayOpacity: Double
    ) {
        self.refreshInterval = refreshInterval
        self.showCPU = showCPU
        self.showMemory = showMemory
        self.showNetwork = showNetwork
        self.showDisk = showDisk
        self.showFPS = showFPS
        self.showMenuBarCPU = showMenuBarCPU
        self.showMenuBarDownload = showMenuBarDownload
        self.showMenuBarUpload = showMenuBarUpload
        self.cpuAlertThresholdPercent = cpuAlertThresholdPercent
        self.memoryAlertThresholdPercent = memoryAlertThresholdPercent
        self.diskAlertThresholdPercent = diskAlertThresholdPercent
        self.networkAlertThresholdMBps = networkAlertThresholdMBps
        self.notificationsEnabled = notificationsEnabled
        self.theme = theme
        self.overlayEnabled = overlayEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.overlayOpacity = overlayOpacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refreshInterval = try c.decodeIfPresent(String.self, forKey: .refreshInterval) ?? RefreshIntervalOption.oneSecond.rawValue
        showCPU = try c.decodeIfPresent(Bool.self, forKey: .showCPU) ?? true
        showMemory = try c.decodeIfPresent(Bool.self, forKey: .showMemory) ?? true
        showNetwork = try c.decodeIfPresent(Bool.self, forKey: .showNetwork) ?? true
        showDisk = try c.decodeIfPresent(Bool.self, forKey: .showDisk) ?? true
        showFPS = try c.decodeIfPresent(Bool.self, forKey: .showFPS) ?? true
        showMenuBarCPU = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarCPU) ?? true
        showMenuBarDownload = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarDownload) ?? true
        showMenuBarUpload = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarUpload) ?? false
        cpuAlertThresholdPercent = try c.decodeIfPresent(Double.self, forKey: .cpuAlertThresholdPercent) ?? 85
        memoryAlertThresholdPercent = try c.decodeIfPresent(Double.self, forKey: .memoryAlertThresholdPercent) ?? 85
        diskAlertThresholdPercent = try c.decodeIfPresent(Double.self, forKey: .diskAlertThresholdPercent) ?? 85
        networkAlertThresholdMBps = try c.decodeIfPresent(Double.self, forKey: .networkAlertThresholdMBps) ?? 20
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? AppTheme.system.rawValue
        overlayEnabled = try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? false
        launchAtLoginEnabled = try c.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? false
        overlayOpacity = try c.decodeIfPresent(Double.self, forKey: .overlayOpacity) ?? 0.85
    }

    static var `default`: AppSettings {
        AppSettings(
            refreshInterval: RefreshIntervalOption.oneSecond.rawValue,
            showCPU: true,
            showMemory: true,
            showNetwork: true,
            showDisk: true,
            showFPS: true,
            showMenuBarCPU: true,
            showMenuBarDownload: true,
            showMenuBarUpload: false,
            cpuAlertThresholdPercent: 85,
            memoryAlertThresholdPercent: 85,
            diskAlertThresholdPercent: 85,
            networkAlertThresholdMBps: 20,
            notificationsEnabled: false,
            theme: AppTheme.system.rawValue,
            overlayEnabled: false,
            launchAtLoginEnabled: false,
            overlayOpacity: 0.85
        )
    }
}
