import Foundation
import RewindCore

/// Loads rule packs and the engine bundle copied into the app by scripts/build-engine-for-ios.sh.
enum RulePackLoader {
    static let resourceSubdirectory = "Generated"

    /// Looks in `Generated/` (where the build script copies files), then the bundle root.
    private static func resource(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: resourceSubdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    static func bundled(_ platform: Platform) -> LoadedRulePack? {
        guard let url = resource(platform.rulePackResourceName, "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? LoadedRulePack(data: data)
    }

    /// Where an opt-in refreshed pack is cached (App Group container).
    static func refreshedURL(_ platform: Platform) -> URL? {
        AppGroup.containerURL?
            .appendingPathComponent("RulePacks", isDirectory: true)
            .appendingPathComponent("\(platform.rulePackResourceName).json")
    }

    /// The bundled pack, or the cached refreshed one if it's valid and newer.
    static func load(_ platform: Platform) -> LoadedRulePack? {
        guard let bundled = bundled(platform) else { return nil }
        let cached = refreshedURL(platform).flatMap { try? Data(contentsOf: $0) }
        return RulePackSelector.select(bundled: bundled, refreshed: cached, platform: platform)
    }

    struct EngineSources {
        /// History + fetch/XHR patches, for the page world.
        let page: String
        /// CSS/DOM filter, counter and bridge, for the isolated "SocialRewind" world.
        let isolated: String
    }

    /// Both engine bundles, or nil if either is missing (callers must then fail closed).
    static func engineSources() -> EngineSources? {
        func load(_ name: String) -> String? {
            resource(name, "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        guard let page = load(EngineConfigBuilder.pageBundleName),
              let isolated = load(EngineConfigBuilder.isolatedBundleName),
              !page.isEmpty, !isolated.isEmpty else { return nil }
        return EngineSources(page: page, isolated: isolated)
    }
}
