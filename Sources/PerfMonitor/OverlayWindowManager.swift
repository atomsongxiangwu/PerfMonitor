import AppKit
import Combine
import SwiftUI

// MARK: - OverlayWindowManager

/// Manages the lifecycle of the floating always-on-top NSPanel.
@MainActor
final class OverlayWindowManager {
    /// Called when the user closes the panel via the HUD close button.
    var onClose: (() -> Void)?

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?

    func show(viewModel: MetricsViewModel) {
        if let existing = panel {
            existing.orderFront(nil)
            setOpacity(viewModel.overlayOpacity)
            return
        }

        let rootView = makeRootView(viewModel: viewModel, theme: viewModel.theme)
        let controller = NSHostingController(rootView: rootView)
        controller.view.setFrameSize(controller.view.fittingSize)

        let contentSize = controller.view.frame.size
        let origin = defaultOrigin(for: contentSize)

        let newPanel = NSPanel(
            contentRect: NSRect(origin: origin, size: contentSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .floating
        newPanel.isMovableByWindowBackground = true
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.alphaValue = CGFloat(viewModel.overlayOpacity)
        newPanel.contentViewController = controller

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newPanel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.panel = nil
                self?.hostingController = nil
                self?.onClose?()
            }
        }

        newPanel.orderFront(nil)
        panel = newPanel
        hostingController = controller
    }

    func hide() {
        panel?.close()
        panel = nil
        hostingController = nil
    }

    func setOpacity(_ opacity: Double) {
        panel?.alphaValue = CGFloat(max(0.1, min(1.0, opacity)))
    }

    func updateTheme(_ theme: AppTheme, viewModel: MetricsViewModel) {
        guard let controller = hostingController else { return }
        controller.rootView = makeRootView(viewModel: viewModel, theme: theme)
    }

    private func makeRootView(viewModel: MetricsViewModel, theme: AppTheme) -> AnyView {
        AnyView(
            OverlayView(viewModel: viewModel)
                .preferredColorScheme(theme.colorScheme)
        )
    }

    private func defaultOrigin(for size: CGSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        return NSPoint(
            x: screen.visibleFrame.maxX - size.width - 16,
            y: screen.visibleFrame.maxY - size.height - 16
        )
    }
}

// MARK: - OverlayCoordinator

/// Lives as @StateObject in PerfMonitorApp; observes MetricsViewModel via Combine
/// and drives OverlayWindowManager show/hide without requiring MenuContentView to be visible.
@MainActor
final class OverlayCoordinator: ObservableObject {
    private let windowManager = OverlayWindowManager()
    private var cancellables = Set<AnyCancellable>()
    private var isBound = false

    func bind(viewModel: MetricsViewModel) {
        guard !isBound else { return }
        isBound = true

        windowManager.onClose = { [weak viewModel] in
            viewModel?.overlayEnabled = false
        }

        viewModel.$overlayEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self, weak viewModel] enabled in
                guard let self, let viewModel else { return }
                if enabled {
                    self.windowManager.show(viewModel: viewModel)
                } else {
                    self.windowManager.hide()
                }
            }
            .store(in: &cancellables)

        viewModel.$overlayOpacity
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] opacity in
                self?.windowManager.setOpacity(opacity)
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
