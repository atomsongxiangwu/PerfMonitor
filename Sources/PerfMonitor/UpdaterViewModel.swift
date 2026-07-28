@preconcurrency import Sparkle
import Combine
import Foundation

// Wraps SPUStandardUpdaterController so it can be used as a SwiftUI @StateObject.
// @preconcurrency suppresses Sendable warnings from the ObjC Sparkle framework.
@MainActor
final class UpdaterViewModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController
    private var cancellable: AnyCancellable?

    init() {
        let ctrl = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller = ctrl
        // KVO publisher may deliver on any thread; hop to main before mutating @Published.
        cancellable = ctrl.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
