import Aptabase
import Foundation

/// Sends anonymous product-usage events only. Never attach notification content,
/// Bark credentials, rule values, bundle identifiers, or other user data.
@MainActor
final class AnalyticsManager {
    static let shared = AnalyticsManager()

    private static let appKey = "A-US-7913644270"
    private var isInitialized = false
    private var dailyCheckInTimer: Timer?

    private init() {}

    func start() {
        guard !isInitialized else { return }
        isInitialized = true

        Aptabase.shared.initialize(appKey: Self.appKey)
        track("app_started")
        scheduleNextDailyCheckIn()
    }

    func track(_ eventName: String) {
        guard isInitialized else { return }
        Aptabase.shared.trackEvent(eventName)
        // Menu-bar apps may start after the SDK's active-state flush trigger.
        Aptabase.shared.flush()
    }

    private func scheduleNextDailyCheckIn() {
        dailyCheckInTimer?.invalidate()

        guard let nextMidnight = Calendar.autoupdatingCurrent.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }

        dailyCheckInTimer = Timer(fire: nextMidnight, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.track("daily_check_in")
                self?.scheduleNextDailyCheckIn()
            }
        }
        if let dailyCheckInTimer {
            RunLoop.main.add(dailyCheckInTimer, forMode: .common)
        }
    }
}
