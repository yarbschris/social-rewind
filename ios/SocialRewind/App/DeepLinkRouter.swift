import Foundation

/// The one way into `AppModel.handle(url:)` for links that come from outside SwiftUI: taps on the
/// shield's notification and App Intents (Home Screen shortcuts, Siri, Spotlight, the Action
/// button). Either can arrive on a cold launch before SwiftUI has created the model, so the link
/// waits here until `attach` is called.
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    private weak var model: AppModel?
    private var pendingURL: URL?

    func attach(_ model: AppModel) {
        self.model = model
        if let url = pendingURL {
            pendingURL = nil
            model.handle(url: url)
        }
    }

    func open(_ url: URL) {
        if let model { model.handle(url: url) } else { pendingURL = url }
    }
}
