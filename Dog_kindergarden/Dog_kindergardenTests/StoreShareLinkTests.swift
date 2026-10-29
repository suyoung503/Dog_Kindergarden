import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("Public store share links")
struct StoreShareLinkTests {
    @Test("Share URL contains only the percent-encoded stable public key")
    func publicURL() throws {
        let key = "서울|멍 & 쉼/#?+%"
        let url = try #require(StoreShareLink.publicURL(storeKey: key))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "https")
        #expect(parts.host == "matgyeomung-api.dog-kindergarden.workers.dev")
        #expect(parts.path == "/store")
        #expect(parts.queryItems == [URLQueryItem(name: "key", value: key)])
        #expect(StoreShareLink.storeKey(from: StoreShareLink.appURL(storeKey: key)!) == key)
    }

    @Test("Reject malformed or unrelated links instead of navigating")
    func strictParsing() {
        for raw in [
            "https://evil.example/store?key=a", "kakao123://store?key=a",
            "matgyeomung://other?key=a", "matgyeomung://store/path?key=a",
            "matgyeomung://store/?key=a", "matgyeomung://user@store?key=a",
            "matgyeomung://store:123?key=a", "matgyeomung://store?key=a#fragment",
            "matgyeomung://store?key=", "matgyeomung://store?key=%20",
            "matgyeomung://store?key=a&key=b", "matgyeomung://store?key=a&token=secret",
            "matgyeomung://store?key=%00", "matgyeomung://store?key=%0A",
            "matgyeomung://store?key=" + String(repeating: "a", count: 513)
        ] {
            #expect(StoreShareLink.storeKey(from: URL(string: raw)!) == nil, "Accepted \(raw)")
        }
        #expect(StoreShareLink.publicURL(storeKey: "") == nil)
        #expect(StoreShareLink.publicURL(storeKey: " padded ") == nil)
    }

    @Test("Cold and warm links wait until consumed and a newer request is not discarded")
    @MainActor
    func pendingDelivery() throws {
        let inbox = StoreShareInbox()
        #expect(inbox.receive(URL(string: "matgyeomung://store?key=first")!))
        let first = try #require(inbox.pending)
        #expect(inbox.pending?.storeKey == "first")
        #expect(!inbox.receive(URL(string: "kakao123://oauth?code=secret")!))
        #expect(inbox.pending == first)
        #expect(inbox.receive(URL(string: "matgyeomung://store?key=second")!))
        inbox.consume(first)
        #expect(inbox.pending?.storeKey == "second")
        inbox.consume(try #require(inbox.pending))
        #expect(inbox.pending == nil)
    }
}
