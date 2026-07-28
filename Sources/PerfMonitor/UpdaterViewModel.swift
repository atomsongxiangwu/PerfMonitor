@preconcurrency import Sparkle
import Combine
import Foundation

// Wraps SPUStandardUpdaterController so it can be used as a SwiftUI @StateObject.
// @preconcurrency suppresses Sendable warnings from the ObjC Sparkle framework.
@MainActor
final class UpdaterViewModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    /// False for `swift run` / bare binaries that lack a packaged .app Info.plist.
    @Published private(set) var isUpdaterAvailable = false

    private let controller: SPUStandardUpdaterController?
    private var cancellable: AnyCancellable?

    init() {
        guard Self.shouldEnableUpdater else {
            controller = nil
            isUpdaterAvailable = false
            return
        }

        let ctrl = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller = ctrl
        isUpdaterAvailable = true
        // KVO publisher may deliver on any thread; hop to main before mutating @Published.
        cancellable = ctrl.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    /// Sparkle needs a real .app bundle with feed URL / public key in Info.plist.
    /// `swift run` launches a bare executable under Products/Debug — starting the
    /// updater there only produces the "Unable to Check For Updates" alert.
    private static var shouldEnableUpdater: Bool {
        let bundle = Bundle.main
        guard bundle.bundleURL.pathExtension == "app" else { return false }
        guard let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURL.isEmpty else {
            return false
        }
        guard let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicKey.isEmpty else {
            return false
        }
        return true
    }
}
