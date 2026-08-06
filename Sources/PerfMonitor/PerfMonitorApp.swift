import AppKit
import SwiftUI

@main
struct PerfMonitorApp: App {
    @StateObject private var viewModel = MetricsViewModel(provider: SystemMetricsProvider())
    @StateObject private var overlayCoordinator = OverlayCoordinator()
    @StateObject private var historyCoordinator = HistoryCoordinator()
    @StateObject private var diskCleanupCoordinator = DiskCleanupCoordinator()
    @StateObject private var updaterViewModel = UpdaterViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel, updaterViewModel: updaterViewModel)
                .preferredColorScheme(viewModel.theme.colorScheme)
                .onAppear {
                    overlayCoordinator.bind(viewModel: viewModel)
                    historyCoordinator.bind(viewModel: viewModel)
                    diskCleanupCoordinator.bind(viewModel: viewModel)
                }
        } label: {
            HStack(spacing: 4) {
                MenuBarCPUIcon(cpuPercent: viewModel.snapshot.cpuUsagePercent)
                Text(viewModel.menuBarTitle)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
