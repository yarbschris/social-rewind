import Foundation

public enum EngineInfo {
    /// Mirror of `ENGINE_VERSION` in `engine/src/core/types.ts`. Keep in sync.
    public static let version = 1
}

/// Mirror of `RulePack` in `engine/src/core/types.ts`.
/// Native code types only what the settings UI and pack selection need; rule
/// bodies are forwarded to the engine as the original JSON bytes.
public struct RulePack: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var platform: String
    public var revision: Int
    public var minEngineVersion: Int
    public var startPath: String
    public var alwaysAllowRoutes: [String]?
    public var features: [String: FeatureDef]
    public var modes: [String: ModeDef]?
    public var counter: JSONValue?
    public var identity: JSONValue?

    public enum FeatureGroup: String, Codable, Sendable, CaseIterable {
        case content
        case ads
    }

    public struct FeatureDef: Codable, Sendable, Equatable {
        public var title: String
        public var description: String?
        public var group: FeatureGroup
        public var `default`: Bool
        /// `false` → "Coming soon", never applied. Missing → available.
        public var available: Bool?
        public var rules: RuleSet

        public var isAvailable: Bool { available ?? true }
    }

    public struct ModeDef: Codable, Sendable, Equatable {
        public var title: String
        public var description: String?
        public var home: String
        public var allowRoutes: [String]
        public var rules: RuleSet?
    }

    public struct RuleSet: Codable, Sendable, Equatable {
        public var css: [String]?
        public var dom: [JSONValue]?
        public var routes: [RouteRule]?
        public var network: [JSONValue]?
    }

    public struct RouteRule: Codable, Sendable, Equatable {
        public enum Action: String, Codable, Sendable { case block, redirect }
        public var pattern: String
        public var action: Action
        public var to: String?
    }
}

/// A rule pack together with the exact bytes it was decoded from (forwarded to
/// the engine) and the declaration order of features and modes.
public struct LoadedRulePack: Sendable, Equatable {
    public let pack: RulePack
    public let data: Data
    public let featureOrder: [String]
    public let modeOrder: [String]

    public init(data: Data) throws {
        let pack = try JSONDecoder().decode(RulePack.self, from: data)
        self.pack = pack
        self.data = data
        let declared = JSONKeyOrder.keys(atPath: ["features"], in: data) ?? []
        self.featureOrder = Self.ordered(declared, keys: Array(pack.features.keys))
        let declaredModes = JSONKeyOrder.keys(atPath: ["modes"], in: data) ?? []
        self.modeOrder = Self.ordered(declaredModes, keys: Array((pack.modes ?? [:]).keys))
    }

    /// Features in declaration order for one group.
    public func features(in group: RulePack.FeatureGroup) -> [(id: String, def: RulePack.FeatureDef)] {
        featureOrder.compactMap { id in
            guard let def = pack.features[id], def.group == group else { return nil }
            return (id, def)
        }
    }

    private static func ordered(_ declared: [String], keys: [String]) -> [String] {
        let known = Set(keys)
        var result = declared.filter { known.contains($0) }
        // Fallback for anything the order scan missed.
        result += keys.filter { !result.contains($0) }.sorted()
        return result
    }
}
