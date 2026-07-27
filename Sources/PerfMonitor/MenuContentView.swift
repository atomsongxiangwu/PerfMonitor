import AppKit
import SwiftUI

private let panelWidth: CGFloat = 360
private let panelHeight: CGFloat = 540

struct MenuContentView: View {
    @ObservedObject var viewModel: MetricsViewModel
    @State private var selectedTab: Tab = .monitor

    enum Tab: String, CaseIterable {
        case monitor = "Monitor"
        case settings = "Settings"
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
        .frame(width: panelWidth, height: panelHeight)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.bar)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .monitor:
            monitorTab
        case .settings:
            settingsTab
        }
    }

    private var monitorTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.showCPU {
                    metricRow(
                        "CPU",
                        value: String(format: "%.1f%%", viewModel.snapshot.cpuUsagePercent),
                        isAlerting: viewModel.isCPUAlerting(for: viewModel.snapshot)
                    )
                    trendRow("CPU Trend", values: viewModel.history.map(\.cpuUsagePercent), color: .orange, maxY: 100)
                }

                if viewModel.showMemory {
                    metricRow(
                        "Memory",
                        value: "\(MetricFormatting.bytes(viewModel.snapshot.memoryUsedBytes)) / \(MetricFormatting.bytes(viewModel.snapshot.memoryTotalBytes))",
                        isAlerting: viewModel.isMemoryAlerting(for: viewModel.snapshot)
                    )
                    trendRow("Memory Trend", values: memoryPctTrend, color: .purple, maxY: 100)
                }

                if viewModel.showNetwork {
                    metricRow(
                        "Upload",
                        value: "\(MetricFormatting.speed(viewModel.snapshot.uploadBytesPerSecond))/s",
                        isAlerting: viewModel.isUploadAlerting(for: viewModel.snapshot)
                    )
                    metricRow(
                        "Download",
                        value: "\(MetricFormatting.speed(viewModel.snapshot.downloadBytesPerSecond))/s",
                        isAlerting: viewModel.isDownloadAlerting(for: viewModel.snapshot)
                    )
                    networkTrendRow
                }

                if viewModel.showDisk {
                    metricRow(
                        "Disk Read",
                        value: "\(MetricFormatting.speed(viewModel.snapshot.diskReadBytesPerSecond))/s",
                        isAlerting: false
                    )
                    metricRow(
                        "Disk Write",
                        value: "\(MetricFormatting.speed(viewModel.snapshot.diskWriteBytesPerSecond))/s",
                        isAlerting: false
                    )
                    diskTrendRow
                }

                if viewModel.showFPS {
                    metricRow("FPS", value: MetricFormatting.fps(viewModel.snapshot.fps), isAlerting: false)
                }
            }
            .padding(14)
            .frame(width: panelWidth, alignment: .leading)
        }
        .frame(width: panelWidth, height: panelHeight - 37)
        .overlay(alignment: .bottomLeading) {
            Text("Updated: \(viewModel.snapshot.sampledAt.formatted(date: .omitted, time: .standard))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
    }

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                refreshSection
                themeSection
                displaySection
                menuBarSection
                overlaySection
                thresholdSection
                launchAtLoginSection
                historySection
                configSection
            }
            .padding(14)
            .frame(width: panelWidth, alignment: .leading)
        }
        .frame(width: panelWidth, height: panelHeight - 37)
    }

    private var refreshSection: some View {
        section("Refresh") {
            Picker("", selection: $viewModel.refreshInterval) {
                ForEach(RefreshIntervalOption.allCases) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var themeSection: some View {
        section("Theme") {
            Picker("", selection: $viewModel.theme) {
                ForEach(AppTheme.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var displaySection: some View {
        section("Display in Panel") {
            HStack(spacing: 10) {
                Toggle("CPU", isOn: $viewModel.showCPU)
                Toggle("Memory", isOn: $viewModel.showMemory)
                Toggle("Network", isOn: $viewModel.showNetwork)
                Toggle("Disk", isOn: $viewModel.showDisk)
                Toggle("FPS", isOn: $viewModel.showFPS)
            }
        }
    }

    private var menuBarSection: some View {
        section("Menu Bar Content") {
            HStack(spacing: 16) {
                Toggle("CPU", isOn: $viewModel.showMenuBarCPU)
                Toggle("Download ↓", isOn: $viewModel.showMenuBarDownload)
                Toggle("Upload ↑", isOn: $viewModel.showMenuBarUpload)
            }
        }
    }

    private var overlaySection: some View {
        section("Floating Overlay") {
            Toggle("Show HUD", isOn: $viewModel.overlayEnabled)
            HStack {
                Text("Opacity")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", viewModel.overlayOpacity * 100))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $viewModel.overlayOpacity, in: 0.2...1.0)
        }
    }

    private var thresholdSection: some View {
        section("Alert Thresholds") {
            thresholdRow("CPU", value: $viewModel.cpuAlertThresholdPercent, range: 50...100, format: "%.0f%%")
            thresholdRow("Memory", value: $viewModel.memoryAlertThresholdPercent, range: 50...100, format: "%.0f%%")
            thresholdRow("Network", value: $viewModel.networkAlertThresholdMBps, range: 1...500, format: "%.0f MB/s")
            Toggle("Desktop Notifications", isOn: $viewModel.notificationsEnabled)
        }
    }

    private var launchAtLoginSection: some View {
        section("Startup") {
            Toggle("Launch at Login", isOn: $viewModel.launchAtLoginEnabled)
            HStack {
                Text("Status").foregroundStyle(.secondary).font(.caption)
                Spacer()
                Text(viewModel.launchAtLoginStatus.rawValue)
                    .font(.system(.caption, design: .monospaced))
            }
            if let message = viewModel.launchAtLoginMessage {
                Text(message).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var historySection: some View {
        section("History") {
            HStack {
                Text("Open 1h / 24h trend window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open") {
                    viewModel.historyWindowVisible = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var configSection: some View {
        section("Configuration") {
            HStack(spacing: 10) {
                Button("Export Config") { exportConfig() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Import Config") { importConfig() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if let err = viewModel.importError {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    @ViewBuilder
    private func metricRow(_ title: String, value: String, isAlerting: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(isAlerting ? Color.red : Color.primary)
        }
    }

    private func thresholdRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    @ViewBuilder
    private func trendRow(_ title: String, values: [Double], color: Color, maxY: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            MiniTrendChart(values: values, strokeColor: color, maxY: maxY)
                .frame(height: 28)
                .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var memoryPctTrend: [Double] {
        viewModel.history.map { s in
            guard s.memoryTotalBytes > 0 else { return 0 }
            return Double(s.memoryUsedBytes) / Double(s.memoryTotalBytes) * 100
        }
    }

    private var downloadTrend: [Double] { viewModel.history.map(\.downloadBytesPerSecond) }
    private var uploadTrend: [Double] { viewModel.history.map(\.uploadBytesPerSecond) }
    private var netMax: Double { max(downloadTrend.max() ?? 1, uploadTrend.max() ?? 1) }

    private var networkTrendRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Network Trend").font(.caption).foregroundStyle(.secondary)
                Text("↓").font(.caption2).foregroundStyle(.blue)
                Text("↑").font(.caption2).foregroundStyle(.green)
            }
            ZStack {
                MiniTrendChart(values: downloadTrend, strokeColor: .blue, maxY: netMax)
                MiniTrendChart(values: uploadTrend, strokeColor: .green, maxY: netMax)
            }
            .frame(height: 28)
            .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var diskReadTrend: [Double] { viewModel.history.map(\.diskReadBytesPerSecond) }
    private var diskWriteTrend: [Double] { viewModel.history.map(\.diskWriteBytesPerSecond) }
    private var diskMax: Double { max(diskReadTrend.max() ?? 1, diskWriteTrend.max() ?? 1) }

    private var diskTrendRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Disk Trend").font(.caption).foregroundStyle(.secondary)
                Text("R").font(.caption2).foregroundStyle(.purple)
                Text("W").font(.caption2).foregroundStyle(.teal)
            }
            ZStack {
                MiniTrendChart(values: diskReadTrend, strokeColor: .purple, maxY: diskMax)
                MiniTrendChart(values: diskWriteTrend, strokeColor: .teal, maxY: diskMax)
            }
            .frame(height: 28)
            .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func exportConfig() {
        guard let data = try? viewModel.exportSettings() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PerfMonitor-config.json"
        panel.allowedContentTypes = [.json]
        panel.message = "Save PerfMonitor configuration"
        activateApp()
        panel.begin { response in
            restoreApp()
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a PerfMonitor configuration file"
        activateApp()
        panel.begin { response in
            restoreApp()
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }
            viewModel.importSettings(from: data)
        }
    }

    private func activateApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreApp() {
        NSApp.setActivationPolicy(.accessory)
    }
}
