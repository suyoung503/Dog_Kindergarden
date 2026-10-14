//
//  Dog_kindergardenTests.swift
//  Dog_kindergardenTests
//
//  Created by su young on 5/13/26.
//

import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("Core application regression tests")
struct DogKindergardenTests {

    @Test("Async load state distinguishes loading and failure")
    func asyncLoadPhaseState() {
        #expect(AsyncLoadPhase.idle.isLoading == false)
        #expect(AsyncLoadPhase.loading.isLoading == true)
        #expect(AsyncLoadPhase.loaded.isLoading == false)
        #expect(AsyncLoadPhase.failed("network").isLoading == false)
    }

    @Test("Missing pet fields use safe display defaults")
    func petResponseDefaults() {
        let response = PetResponse(
            petId: 7,
            name: "몽이",
            breed: nil,
            age: nil,
            weight: nil,
            gender: nil,
            note: nil,
            imageUrl: nil
        )

        let profile = response.toDomain()

        #expect(profile.name == "몽이")
        #expect(profile.breed == "정보 없음")
        #expect(profile.age == 0)
        #expect(profile.weight == 0)
        #expect(profile.gender == "정보 없음")
        #expect(profile.note == "특이사항 없음")
    }

    @Test("Store capabilities decode from snake case")
    func storeCapabilityDecoding() throws {
        let payload = """
        {
          "store_id": 42,
          "store_key": "store-42",
          "name": "테스트 유치원",
          "partner_status": "ACTIVE",
          "is_partner": true,
          "can_book": true,
          "can_chat": true,
          "can_diary": true,
          "can_review": true,
          "images": [
            { "image_id": 1, "image_url": "https://example.com/1.jpg", "sort_order": 0 }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let detail = try decoder.decode(StoreDetailResponse.self, from: Data(payload.utf8))

        #expect(detail.storeId == 42)
        #expect(detail.partnerStatus == "ACTIVE")
        #expect(detail.isPartner == true)
        #expect(detail.canBook == true)
        #expect(detail.canChat == true)
        #expect(detail.canDiary == true)
        #expect(detail.canReview == true)
        #expect(detail.images?.first?.sortOrder == 0)
    }

    @Test("Notification items only create valid deep links")
    func notificationDeepLinks() {
        let chat = inboxItem(type: "chat", roomId: 12, asOwner: true)
        let malformedChat = inboxItem(type: "chat")
        let support = inboxItem(type: "support", conversationId: 8)
        let ownerApplication = inboxItem(type: "owner_application")

        #expect(chat.deepLink == .chat(roomId: 12, title: "알림", asOwner: true, storeType: nil))
        #expect(malformedChat.deepLink == nil)
        #expect(support.deepLink == .support(conversationId: 8, title: "알림"))
        #expect(ownerApplication.deepLink == .ownerApplications)
    }

    @Test("Booking price text is normalized and matched without invented prices")
    @MainActor
    func bookingPriceMatching() {
        let viewModel = BookingViewModel()
        viewModel.storePriceInfo = "시간권 1시간 8,000원 / 종일 유치원 35,000원\\n호텔 1박 50,000원"

        #expect(viewModel.formattedStorePriceInfo == "시간권 1시간 8,000원\n종일 유치원 35,000원\n호텔 1박 50,000원")
        #expect(viewModel.services[0].price == "시간권 1시간 8,000원")
        #expect(viewModel.services[1].price == "종일 유치원 35,000원")
        #expect(viewModel.services[2].price == "호텔 1박 50,000원")

        viewModel.storePriceInfo = nil
        #expect(viewModel.services.allSatisfy { $0.price == "가격 업체 확인" })
    }

    private func inboxItem(
        type: String,
        roomId: Int? = nil,
        conversationId: Int? = nil,
        asOwner: Bool = false
    ) -> AppInboxItem {
        AppInboxItem(
            id: UUID().uuidString,
            type: type,
            title: "알림",
            body: "내용",
            roomId: roomId,
            reservationId: nil,
            conversationId: conversationId,
            applicationId: nil,
            asOwner: asOwner,
            storeType: nil,
            receivedAt: Date(timeIntervalSince1970: 0),
            isRead: false
        )
    }
}
