import Foundation

/// How Social Rewind's web view identifies itself to the platform.
///
/// WKWebView's default user agent ends in "Mobile/15E148", without Safari's "Version/x Safari/y".
/// Platforms treat that as an unknown embedded browser. Meta, for one, then applies extra login
/// checks and offers fewer two-factor options. WebKit builds the rest of the string (OS version,
/// AppleWebKit), so only this application suffix is set, to what Mobile Safari sends.
public enum BrowserIdentity {
    /// e.g. "Version/18.1 Mobile/15E148 Safari/604.1" for systemVersion "18.1.1".
    public static func safariApplicationName(systemVersion: String) -> String {
        let parts = systemVersion.split(separator: ".").map(String.init)
        let major = parts.first.flatMap(Int.init) ?? 17
        let minor = parts.dropFirst().first.flatMap(Int.init) ?? 0
        return "Version/\(major).\(minor) Mobile/15E148 Safari/604.1"
    }
}
