import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("Chat notification routing")
@MainActor
struct ChatNotificationTests {
    @Test("Chat display text does not contaminate the counterpart title or room routing", arguments: [false, true])
    func counterpartRoute(asOwner: Bool) throws {
        let title = asOwner ? "초코 보호자" : "초코 유치원"
        let item = AppInboxItem(id: "chat:24", type: "chat", title: title,
                                body: "새 채팅이 도착했어요. 내일 뵐게요", roomId: 12,
                                reservationId: nil, conversationId: nil, applicationId: nil,
                                asOwner: asOwner, storeType: asOwner ? nil : "KINDERGARTEN",
                                receivedAt: Date(), isRead: false)
        let expected = NotificationDeepLink.chat(roomId: 12, title: title, asOwner: asOwner,
                                                storeType: asOwner ? nil : "KINDERGARTEN")
        #expect(item.deepLink == expected)
        #expect(NotificationDeepLink.resolve(type: "chat", roomId: 12, conversationId: nil,
                                             title: title, asOwner: asOwner,
                                             storeType: asOwner ? nil : "KINDERGARTEN") == expected)
        #expect(try JSONDecoder().decode(AppInboxItem.self, from: JSONEncoder().encode(item)).deepLink == expected)
    }

    @Test("Invalid chat IDs never navigate to a fallback room", arguments: [nil, 0, -1] as [Int?])
    func invalidRoom(roomId: Int?) {
        #expect(NotificationDeepLink.resolve(type: "chat", roomId: roomId, conversationId: nil,
                                             title: "초코 유치원", asOwner: false, storeType: nil) == nil)
    }
}
