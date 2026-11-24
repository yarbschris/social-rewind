import Foundation

/// Messages from the engine. Mirror of `BridgeEvent` in `engine/src/core/types.ts`.
public enum BridgeEvent: Decodable, Equatable, Sendable {
    case ready(engineVersion: Int, rulesRevision: Int)
    case postViewed(key: String, sessionCount: Int)
    case routeBlocked(path: String, reason: String, redirectedTo: String?)
    case ruleHit(ruleId: String)
    case identity(username: String)
    case error(message: String)
    /// A newer engine sent something this build doesn't know. Ignore it.
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, engineVersion, rulesRevision, key, sessionCount, path, reason, redirectedTo, ruleId, username, message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "ready":
            self = .ready(engineVersion: try c.decode(Int.self, forKey: .engineVersion),
                          rulesRevision: try c.decode(Int.self, forKey: .rulesRevision))
        case "postViewed":
            self = .postViewed(key: try c.decode(String.self, forKey: .key),
                               sessionCount: try c.decode(Int.self, forKey: .sessionCount))
        case "routeBlocked":
            self = .routeBlocked(path: try c.decode(String.self, forKey: .path),
                                 reason: try c.decode(String.self, forKey: .reason),
                                 redirectedTo: try c.decodeIfPresent(String.self, forKey: .redirectedTo))
        case "ruleHit":
            self = .ruleHit(ruleId: try c.decode(String.self, forKey: .ruleId))
        case "identity":
            self = .identity(username: try c.decode(String.self, forKey: .username))
        case "error":
            self = .error(message: try c.decode(String.self, forKey: .message))
        default:
            self = .unknown(type: type)
        }
    }

    /// Decodes a `WKScriptMessage.body` (a Foundation object graph) or an Android JSON string.
    public init(messageBody: Any) throws {
        let data: Data
        if let string = messageBody as? String {
            data = Data(string.utf8)
        } else if JSONSerialization.isValidJSONObject(messageBody) {
            data = try JSONSerialization.data(withJSONObject: messageBody)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported message body"))
        }
        self = try JSONDecoder().decode(BridgeEvent.self, from: data)
    }
}

extension BridgeEvent {
    public static let maxKeyLength = 128
    public static let maxMessageLength = 500

    /// The page's own scripts can post to the handler too (it lives in the page world),
    /// so treat every event as untrusted. Returns nil if the event should be dropped.
    public func validated() -> BridgeEvent? {
        switch self {
        case .postViewed(let key, let count):
            guard !key.isEmpty, key.count <= Self.maxKeyLength, count >= 0 else { return nil }
            return self
        case .identity(let username):
            guard Username.isValid(username) else { return nil }
            return self
        case .error(let message):
            return .error(message: String(message.prefix(Self.maxMessageLength)))
        case .routeBlocked(let path, let reason, let to):
            return .routeBlocked(path: String(path.prefix(Self.maxMessageLength)),
                                 reason: String(reason.prefix(Self.maxMessageLength)),
                                 redirectedTo: to.map { String($0.prefix(Self.maxMessageLength)) })
        case .ready, .ruleHit, .unknown:
            return self
        }
    }
}
