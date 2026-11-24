import WebKit
import RewindCore

/// The two document-start scripts for one platform, config already wrapped in.
struct InjectedScripts: Equatable {
    /// Page world: history + fetch/XHR patches. No bridge, no globals.
    let page: String
    /// Isolated "SocialRewind" world: CSS/DOM filter, counter, identity, bridge.
    let isolated: String

    @MainActor static let isolatedWorld = WKContentWorld.world(name: EngineConfigBuilder.isolatedWorldName)

    @MainActor
    func install(in controller: WKUserContentController) {
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: page, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: .page))
        controller.addUserScript(WKUserScript(source: isolated, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: Self.isolatedWorld))
    }
}
