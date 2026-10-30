import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("Reservation notification routing")
@MainActor
struct ReservationNotificationTests {
    @Test("Reservation cancellation routes according to recipient context", arguments: [false, true])
    func canceled(asOwner: Bool) throws {
        let item = try decode(type: "reservation_canceled", asOwner: asOwner)
        #expect(item.deepLink == (asOwner ? .ownerMode : .reservationList))
    }

    @Test("Confirmed and submitted reservations open the customer's reservation list", arguments: ["reservation_confirmed", "reservation_submitted"])
    func customerReservation(type: String) throws {
        #expect(try decode(type: type, asOwner: false).deepLink == .reservationList)
    }

    @Test("System notification taps share reservation routing with the inbox", arguments: [false, true])
    func systemTap(asOwner: Bool) throws {
        let expected: NotificationDeepLink = asOwner ? .ownerMode : .reservationList
        let link = NotificationDeepLink.resolve(type: "reservation_canceled", roomId: 7,
                                                conversationId: nil, title: "맡겨멍",
                                                asOwner: asOwner, storeType: nil)
        #expect(link == expected)
        #expect(link == (try decode(type: "reservation_canceled", asOwner: asOwner)).deepLink)
    }

    @Test("Pre-context persisted chat inbox items still decode and route")
    func legacyInbox() throws {
        let item = try decode(type: "chat", asOwner: false)
        #expect(item.deepLink == .chat(roomId: 7, title: "맡겨멍", asOwner: false, storeType: nil))
        let roundTrip = try JSONDecoder().decode(AppInboxItem.self, from: JSONEncoder().encode(item))
        #expect(roundTrip == item)
    }

    private func decode(type: String, asOwner: Bool) throws -> AppInboxItem {
        let json = """
        {"id":"chat:19","type":"\(type)","title":"맡겨멍","body":"예약 안내","roomId":7,"reservationId":5,"asOwner":\(asOwner),"receivedAt":0,"isRead":false}
        """
        return try JSONDecoder().decode(AppInboxItem.self, from: Data(json.utf8))
    }
}
