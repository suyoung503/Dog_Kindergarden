import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("Diary notification routing")
@MainActor
struct DiaryNotificationTests {
    @Test("Diary inbox and system notifications open the same reservation read-only")
    func diaryRoute() throws {
        let json = #"{"id":"chat:32","type":"diary","title":"맡겨멍","body":"초코의 새 알림장","roomId":7,"reservationId":19,"diaryId":23,"petName":"초코","storeName":"초코 유치원","canWrite":false,"asOwner":false,"receivedAt":0,"isRead":false}"#
        let item = try JSONDecoder().decode(AppInboxItem.self, from: Data(json.utf8))
        let expected = NotificationDeepLink.diary(reservationId: 19, diaryId: 23, petName: "초코", storeName: "초코 유치원", canWrite: false)
        #expect(item.deepLink == expected)
        #expect(NotificationDeepLink.resolve(type: "diary", roomId: 7, conversationId: nil, title: "맡겨멍", asOwner: false, storeType: nil,
                                             reservationId: 19, diaryId: 23, petName: "초코", storeName: "초코 유치원", canWrite: false) == expected)
        #expect(try JSONDecoder().decode(AppInboxItem.self, from: JSONEncoder().encode(item)) == item)
    }

    @Test("A missing reservation never opens an unrelated chat", arguments: [nil, 0, -1] as [Int?])
    func missingReservation(reservationId: Int?) {
        #expect(NotificationDeepLink.resolve(type: "diary", roomId: 7, conversationId: nil, title: "알림장", asOwner: false, storeType: nil,
                                             reservationId: reservationId) == .reservationList)
    }

    @Test("Legacy inbox decoding and memberwise call sites remain compatible")
    func legacy() throws {
        let json = #"{"id":"chat:1","type":"chat","title":"맡겨멍","body":"내용","roomId":7,"asOwner":false,"receivedAt":0,"isRead":false}"#
        let item = try JSONDecoder().decode(AppInboxItem.self, from: Data(json.utf8))
        #expect(item.diaryId == nil)
        #expect(item.petName == nil)
        #expect(item.storeName == nil)
        #expect(item.canWrite == nil)
        let legacy = AppInboxItem(id: "chat:1", type: "chat", title: "맡겨멍", body: "내용", roomId: 7, reservationId: nil,
                                  conversationId: nil, applicationId: nil, asOwner: false, storeType: nil, receivedAt: Date(timeIntervalSinceReferenceDate: 0), isRead: false)
        #expect(legacy == item)
    }

    @Test("A diary without optional metadata is safe and read-only")
    func defaultMetadata() {
        #expect(NotificationDeepLink.resolve(type: "diary", roomId: nil, conversationId: nil, title: "맡겨멍", asOwner: true, storeType: nil,
                                             reservationId: 19) == .diary(reservationId: 19, diaryId: nil, petName: "우리 아이", storeName: "알림장", canWrite: false))
    }

    @Test("Optional feed metadata decodes without breaking old responses")
    func feedMetadata() throws {
        let json = #"{"event_id":"chat:32","type":"diary","title":"맡겨멍","body":"내용","reservation_id":19,"diary_id":23,"pet_name":"초코","store_name":"유치원","can_write":false}"#
        let dto = try JSONDecoder().decode(NotificationItemDTO.self, from: Data(json.utf8))
        #expect(dto.diary_id == 23)
        #expect(dto.pet_name == "초코")
        #expect(dto.store_name == "유치원")
        #expect(dto.can_write == false)
    }
}
