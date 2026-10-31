import CryptoKit
import Foundation
import Testing
import UIKit
@testable import Dog_kindergarden

@Suite("Icon attribution and offline licenses")
@MainActor
struct AttributionTests {
    @Test("Both Noto icons retain exact versioned sources and Google credit")
    func notoSources() throws {
        let expected = [
            "emoji_hotel": "9481ce20ef21f0c658344417901228e73aaf3480/png/512/emoji_u1f3e8.png",
            "emoji_bone": "f3ae03f5e9b3b8516fa151f7168159ca1a3e7515/png/32/emoji_u1f9b4.png",
        ]
        #expect(AttributionView.credits.count == 9)
        #expect(Set(AttributionView.credits.map(\.id)).count == 9)
        for (asset, path) in expected {
            let credit = try #require(AttributionView.credits.first { $0.assetName == asset })
            #expect(credit.creator == "Google LLC")
            #expect(credit.provider == "Noto Emoji")
            #expect(credit.sourceURL == "https://github.com/googlefonts/noto-emoji/blob/\(path)")
            #expect(UIImage(named: asset) != nil)
        }
    }

    @Test("The existing seven Flaticon credits remain available")
    func existingCredits() {
        let existing = AttributionView.credits.filter { $0.url.host == "www.flaticon.com" }
        #expect(Set(existing.map(\.assetName)) == ["icon_paw", "dog_c", "dog_b", "kindergarden", "emoji_chat", "emoji_calendar", "emoji_note"])
        #expect(existing.count == 7)
        #expect(existing.allSatisfy { $0.provider == "Flaticon" })
    }

    @Test("Complete versioned notices ship inside the app for offline reading")
    func bundledNotices() throws {
        let url = try #require(Bundle.main.url(forResource: "NotoEmojiNotices", withExtension: "txt"))
        let data = try Data(contentsOf: url)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(AttributionView.notoNotices == text)
        #expect(text.contains("Copyright 2013 Google LLC"))
        #expect(text.contains("Apache License"))
        #expect(text.contains("SIL OPEN FONT LICENSE Version 1.1"))
        #expect(text.contains("this notice does not assert that upstream offers a choice of licenses"))
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == "b3d9d2ec566cda28de3aed4bd54bda6bea1d0dff49281c1a85df35fb35dbb7f8")
    }
}
