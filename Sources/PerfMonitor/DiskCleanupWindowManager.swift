import AppKit
import Combine
import SwiftUI

@MainActor
final class DiskCleanupWindowManager {
    var onClose: (() -> Void)?

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?

    func show(viewModel: MetricsViewModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(
            rootView: rootView(viewModel: viewModel, theme: viewModel.theme)
        )
        let window = NSWindow(contentViewController: controller)
        window.title = "Disk Cleanup"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.window = nil
                self?.hostingController = nil
                self?.onClose?()
            }
        }

        self.window = window
        self.hostingController = controller
    }

    func hide() {
        window?.close()
        window = nil
        hostingController = nil
    }

    func updateTheme(_ theme: AppTheme, viewModel: MetricsViewModel) {
        hostingController?.rootView = rootView(viewModel: viewModel, theme: theme)
    }

    private func rootView(viewModel: MetricsViewModel, theme: AppTheme) -> AnyView {
        AnyView(
            DiskCleanupDetailView(viewModel: viewModel) {
                viewModel.diskCleanupWindowVisible = false
            }
            .preferredColorScheme(theme.colorScheme)
        )
    }
}

@MainActor
final class DiskCleanupCoordinator: ObservableObject {
    private let windowManager = DiskCleanupWindowManager()
    private var cancellables = Set<AnyCancellable>()
    private var isBound = false

    func bind(viewModel: MetricsViewModel) {
        guard !isBound else { return }
        isBound = true

        windowManager.onClose = { [weak viewModel] in
            viewModel?.diskCleanupWindowVisible = false
        }

        viewModel.$diskCleanupWindowVisible
            .receive(on: RunLoop.main)
            .sink { [weak self, weak viewModel] visible in
                guard let self, let viewModel else { return }
                if visible {
                    self.windowManager.show(viewModel: viewModel)
                } else {
                    self.windowManager.hide()
                }
            }
            .store(in: &cancellables)

        viewModel.$theme
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self, weak viewModel] theme in
                guard let self, let viewModel else { return }
                self.windowManager.updateTheme(theme, viewModel: viewModel)
            }
            .store(in: &cancellables)
    }
}
