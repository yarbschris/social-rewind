import Foundation

/// Mirror of `EngineConfig` in `engine/src/core/types.ts`.
public struct EngineConfig: Sendable {
    public var platform: Platform
    /// Raw user settings; resolved against the pack when encoded.
    public var settings: PlatformSettings
    public var rules: LoadedRulePack
    public var username: String?
    public var debug: Bool
    public var experimental: Bool

    public init(platform: Platform, settings: PlatformSettings, rules: LoadedRulePack,
                username: String?, debug: Bool, experimental: Bool) {
        self.platform = platform
        self.settings = settings
        self.rules = rules
        self.username = username
        self.debug = debug
        self.experimental = experimental
    }
}

/// Builds the injected scripts. Config is passed **by closure**, never through a global,
/// so the page's own scripts can't read or change it (see the two-world split in
/// docs/architecture.md):
///
///     (function(){"use strict";const __SR_CONFIG__ = {...};
///     <bundle source>
///     })();
public enum EngineConfigBuilder {
    public enum BuildError: Error, Equatable {
        case invalidRulePackJSON
    }

    /// The named content world for the isolated bundle and the message handler.
    public static let isolatedWorldName = "SocialRewind"
    public static let pageBundleName = "social-rewind-page"
    public static let isolatedBundleName = "social-rewind-isolated"

    /// Wraps one engine bundle so that it sees `__SR_CONFIG__` as a closure constant.
    public static func wrap(bundleSource: String, config: EngineConfig) throws -> String {
        let json = try configJSON(config)
        return "(function(){\"use strict\";const __SR_CONFIG__ = \(json);\n\(bundleSource)\n})();"
    }

    /// The config object as JSON text, escaped for embedding in script source.
    public static func configJSON(_ config: EngineConfig) throws -> String {
        // The rule pack is forwarded as-is (minus whitespace) so that fields native
        // doesn't model (dom rules, predicates, counter…) reach the engine intact.
        guard let rulesObject = try? JSONSerialization.jsonObject(with: config.rules.data),
              rulesObject is [String: Any] else {
            throw BuildError.invalidRulePackJSON
        }
        let rulesJSON = try JSONSerialization.data(withJSONObject: rulesObject, options: [.sortedKeys, .withoutEscapingSlashes])

        let resolved = config.settings.resolved(for: config.rules.pack)
        var parts: [String] = []
        parts.append("\"platform\":\(try encode(config.platform.rawValue))")
        // Hosts the engine may act on. From the hardcoded HostPolicy, never from the pack:
        // user scripts run on every main-frame origin (e.g. Facebook login), and the engine
        // must stay inert there.
        parts.append("\"hosts\":\(try encode(HostPolicy.for(config.platform).exactHosts.sorted()))")
        parts.append("\"settings\":\(try encode(resolved))")
        parts.append("\"rules\":\(String(decoding: rulesJSON, as: UTF8.self))")
        if let username = config.username, Username.isValid(username) {
            parts.append("\"username\":\(try encode(username))")
        }
        parts.append("\"debug\":\(config.debug)")
        parts.append("\"experimental\":\(config.experimental)")
        return escapeForScript("{" + parts.joined(separator: ",") + "}")
    }

    /// Live CSS/DOM-only settings change. Evaluate in the isolated world; it has no effect on
    /// the page-world bundle, which only picks up changes on reload.
    public static func updateScript(settings: PlatformSettings, rules: RulePack) throws -> String {
        let json = escapeForScript(try encode(settings.resolved(for: rules)))
        return "window.SocialRewind?.update(\(json));"
    }

    /// Makes JSON text safe to embed in JS source and HTML: `<` can't close a script tag,
    /// and U+2028/U+2029 can't terminate a line (they're legal in JSON strings but historically not in JS).
    /// Outside strings, JSON never contains these characters, so replacing them everywhere is safe.
    public static func escapeForScript(_ json: String) -> String {
        json
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

public enum Username {
    /// Instagram-style handles: letters, digits, '.', '_', at most 30 characters.
    public static func isValid(_ username: String) -> Bool {
        username.range(of: "^[A-Za-z0-9._]{1,30}$", options: .regularExpression) != nil
    }
}
