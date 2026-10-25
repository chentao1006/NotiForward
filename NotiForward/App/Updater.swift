#if !APP_STORE
import AppKit
import Observation
import Sparkle

/// Sparkle updates for the direct download. The App Store build is updated by the App Store,
/// so this file isn't compiled into it.
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let reminders = UpdateReminders()
    @ObservationIgnored private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: reminders
    )

    /// Mirrors Sparkle's setting so SwiftUI can observe it.
    var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    init() {
        automaticallyChecks = false
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        // A menu bar app isn't frontmost, so Sparkle's window would open behind other apps.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}
/// A menu bar app isn't frontmost, so an update found by a scheduled check would open behind
/// other windows. Bring the app forward whenever Sparkle shows an update.
private final class UpdateReminders: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate()
    }
}
#endif
