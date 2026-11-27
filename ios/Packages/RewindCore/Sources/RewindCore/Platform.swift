import Foundation

public enum Platform: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case instagram
    case tiktok
    case snapchat
    case x
    case linkedin
    case youtube
    case facebook
    case reddit

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .snapchat: "Snapchat"
        case .x: "X"
        case .linkedin: "LinkedIn"
        case .youtube: "YouTube"
        case .facebook: "Facebook"
        case .reddit: "Reddit"
        }
    }

    /// Only platforms with a rule pack and host policy can be opened.
    public var isAvailable: Bool { self == .instagram }

    public var origin: URL {
        switch self {
        case .instagram: URL(string: "https://www.instagram.com")!
        case .tiktok: URL(string: "https://www.tiktok.com")!
        case .snapchat: URL(string: "https://web.snapchat.com")!
        case .x: URL(string: "https://x.com")!
        case .linkedin: URL(string: "https://www.linkedin.com")!
        case .youtube: URL(string: "https://m.youtube.com")!
        case .facebook: URL(string: "https://m.facebook.com")!
        case .reddit: URL(string: "https://www.reddit.com")!
        }
    }

    /// `origin` + the rule pack's `startPath` (or the mode's home, resolved by the engine).
    public func startURL(startPath: String = "/") -> URL {
        URL(string: startPath, relativeTo: origin)?.absoluteURL ?? origin
    }

    /// Opens the platform's own app, e.g. to approve a login there. nil if it has no known scheme.
    public var nativeAppURL: URL? {
        switch self {
        case .instagram: URL(string: "instagram://app")
        default: nil
        }
    }

    /// Paths of the platform's sign-in and verification pages (two-factor, "confirm it's you"),
    /// where Social Rewind offers help approving the login in the locked native app.
    public func isSignInPath(_ path: String) -> Bool {
        switch self {
        case .instagram:
            let prefixes = ["/accounts/login", "/accounts/onetap", "/challenge", "/two_factor", "/auth_platform"]
            return prefixes.contains { path == $0 || path.hasPrefix($0 + "/") || path.hasPrefix($0 + "?") }
        default:
            return false
        }
    }

    /// Bundled resource name (without extension) of the rule pack.
    public var rulePackResourceName: String { rawValue }

    /// Opt-in refresh source (docs/decisions/0002).
    public var rulePackRefreshURL: URL {
        URL(string: "https://raw.githubusercontent.com/yarbschris/social-rewind/main/rules/\(rawValue).json")!
    }

    /// Stable identifier for this platform's isolated WebKit data store
    /// (`WKWebsiteDataStore(forIdentifier:)`). Never change these: doing so logs users out.
    public var websiteDataStoreID: UUID {
        switch self {
        case .instagram: UUID(uuidString: "0198EAC3-D294-4578-8B70-39E16F60B8B8")!
        case .tiktok: UUID(uuidString: "DAE44091-2ABB-4ED7-A099-0E116B136F77")!
        case .snapchat: UUID(uuidString: "ECED505E-4891-4DCD-B54A-A46FAEDD057D")!
        case .x: UUID(uuidString: "D4B0EE49-F832-45C4-9B6A-B1FBF9872C99")!
        case .linkedin: UUID(uuidString: "D45291F7-05E9-4A6B-AF22-4349D7462372")!
        case .youtube: UUID(uuidString: "7860CD0F-C566-445D-A22D-96F107D15EAC")!
        case .facebook: UUID(uuidString: "019DCC96-86D9-49BA-B517-B82A6CFF81F8")!
        case .reddit: UUID(uuidString: "528F47A3-76C2-4A2B-A188-9DB4F69FB1E4")!
        }
    }
}

/// `socialrewind://open/<platform>`
public enum DeepLink: Equatable, Sendable {
    public static let scheme = "socialrewind"

    case open(Platform)

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        // socialrewind://open/instagram → host "open", path "/instagram"
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).filter { !$0.isEmpty }
        guard parts.count == 2, parts[0] == "open", let platform = Platform(rawValue: parts[1].lowercased()) else {
            return nil
        }
        self = .open(platform)
    }

    public var url: URL {
        switch self {
        case .open(let platform): URL(string: "\(Self.scheme)://open/\(platform.rawValue)")!
        }
    }
}
