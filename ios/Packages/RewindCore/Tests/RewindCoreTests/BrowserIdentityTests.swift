import Testing
@testable import RewindCore

@Suite struct BrowserIdentityTests {
    @Test func matchesMobileSafarisSuffix() {
        #expect(BrowserIdentity.safariApplicationName(systemVersion: "18.1.1") == "Version/18.1 Mobile/15E148 Safari/604.1")
        #expect(BrowserIdentity.safariApplicationName(systemVersion: "26.0") == "Version/26.0 Mobile/15E148 Safari/604.1")
        #expect(BrowserIdentity.safariApplicationName(systemVersion: "17") == "Version/17.0 Mobile/15E148 Safari/604.1")
        #expect(BrowserIdentity.safariApplicationName(systemVersion: "") == "Version/17.0 Mobile/15E148 Safari/604.1")
    }
}
