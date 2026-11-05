import Testing
@testable import Dog_kindergarden

@Suite("리뷰 태그의 절반 이상 기준")
@MainActor
struct ReviewTagTests {
    private func tags(total: Int, votes: Int?) -> StoreTags {
        StoreTags(store_key: "test-store", count: total, cctv: votes,
                  pickup: votes, large_dog: votes, separation_care: votes)
    }

    @Test("홀수 리뷰 수는 실제 절반을 넘는 표가 필요하다")
    func oddTotals() {
        for (total, votes, expected) in [(3, 1, false), (3, 2, true),
                                         (5, 2, false), (5, 3, true),
                                         (7, 3, false), (7, 4, true)] {
            for tag in ReviewTag.allCases {
                #expect(tags(total: total, votes: votes).has(tag) == expected)
            }
        }
    }

    @Test("짝수 리뷰 수는 정확히 절반의 표도 포함한다")
    func evenTotals() {
        for (total, votes, expected) in [(2, 0, false), (2, 1, true),
                                         (4, 1, false), (4, 2, true),
                                         (6, 2, false), (6, 3, true)] {
            for tag in ReviewTag.allCases {
                #expect(tags(total: total, votes: votes).has(tag) == expected)
            }
        }
    }

    @Test("리뷰나 긍정 표가 없으면 태그를 부여하지 않는다")
    func absentVotes() {
        for (total, votes) in [(0, Int?.none), (0, 0), (1, 0), (3, nil)] {
            for tag in ReviewTag.allCases {
                #expect(!tags(total: total, votes: votes).has(tag))
            }
        }
        #expect(tags(total: 1, votes: 1).has(.cctv))
    }

    @Test("시설 태그는 각각의 표를 사용하며 다른 시설의 표를 재사용하지 않는다")
    func independentTags() {
        let store = StoreTags(store_key: "test-store", count: 5, cctv: 3,
                              pickup: 2, large_dog: 1, separation_care: 4)
        #expect(store.has(.cctv))
        #expect(!store.has(.pickup))
        #expect(!store.has(.largeDog))
        #expect(store.has(.separationCare))
    }
}
