/// Features that depend on how the app was built.
enum BuildFeatures {
    /// False in the TestFlight preview (`ios/project-preview.yml`). That build has no Family Controls
    /// entitlement, since Apple hasn't approved it for distribution yet, and no Screen Time extensions,
    /// so it never asks for Screen Time access or applies shields. The filtered browser works as usual.
    static let screenTime: Bool = {
        #if SR_NO_SCREEN_TIME
        false
        #else
        true
        #endif
    }()
}
