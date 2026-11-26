import DeviceActivity
import ManagedSettings

/// - Sign-in unlocks: when the window for approving a login in the real app ends, lock it again
///   (the app also re-locks as soon as the user comes back to it).
/// Reserved for scheduled features (roadmap "Later features"):
/// - Sleep mode: shield everything, Social Rewind included, during a nightly window.
/// - Time limits: shield a platform's filtered browser after N minutes a day.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // TODO: sleep mode start
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity.rawValue.hasPrefix(ShieldState.signInActivityPrefix) {
            ShieldState.reapplyAll()
        }
        // TODO: sleep mode end
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        // TODO: time limit reached
    }
}
