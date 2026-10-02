import Foundation
import Observation

// ⚠️ 배포된 Cloudflare Worker 주소. wrangler deploy 후 실제 URL로 맞추세요.
let apiBaseURL = "https://matgyeomung-api.dog-kindergarden.workers.dev"

// MARK: - 모델

struct PetReview: Identifiable, Decodable {
    let id: Int
    let verified: Int?
    let user_name: String?
    let rating: Double
    let revisit: Int
    let cctv: Int
    let pickup: Int
    let large_dog: Int
    let separation_care: Int
    let content: String?
    let created_at: String?
}

struct ReviewEligibility: Decodable {
    let eligible: Bool
    let reason: String

    var guidanceMessage: String {
        switch reason {
        case "already_reviewed":
            return "이용 완료 건의 리뷰를 이미 작성했어요"
        case "no_completed_reservation":
            return "확정된 이용 완료 내역이 있어야 리뷰를 작성할 수 있어요"
        default:
            return eligible ? "이용 내역이 확인된 보호자예요" : "리뷰 작성 조건을 확인하지 못했어요"
        }
    }
}

struct ReviewSummary: Decodable {
    let count: Int
    let avg_rating: Double?
    let cctv: Int?
    let pickup: Int?
    let large_dog: Int?
    let separation_care: Int?
}

private struct ReviewListResponse: Decodable {
    let summary: ReviewSummary
    let reviews: [PetReview]
}

// 가게별 태그 집계 (필터용)
struct StoreTags: Decodable {
    let store_key: String
    let count: Int
    let cctv: Int?
    let pickup: Int?
    let large_dog: Int?
    let separation_care: Int?

    // 보호자 절반 이상이 인증한 태그만 true
    func has(_ tag: ReviewTag) -> Bool {
        let half = max(1, count / 2)
        switch tag {
        case .cctv:           return (cctv ?? 0) >= half
        case .pickup:         return (pickup ?? 0) >= half
        case .largeDog:       return (large_dog ?? 0) >= half
        case .separationCare: return (separation_care ?? 0) >= half
        }
    }
}

enum ReviewTag: String, CaseIterable, Identifiable {
    case cctv, pickup, largeDog, separationCare
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cctv: return "CCTV"
        case .pickup: return "픽업"
        case .largeDog: return "대형견"
        case .separationCare: return "분리불안 케어"
        }
    }
}

// 작성 폼 입력값
struct ReviewDraft {
    var rating: Int = 5
    var revisit = false
    var cctv = false
    var pickup = false
    var largeDog = false
    var separationCare = false
    var content = ""
}

// MARK: - 서비스

// 앱 전역에서 공유하는 가게별 태그 (필터용)
@Observable
final class TagStore {
    var tagsByKey: [String: StoreTags] = [:]

    func load() async {
        guard let url = URL(string: "\(apiBaseURL)/api/pet-reviews/tags") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let list = try JSONDecoder().decode([StoreTags].self, from: data)
            await MainActor.run {
                self.tagsByKey = Dictionary(uniqueKeysWithValues: list.map { ($0.store_key, $0) })
            }
        } catch {
            #if DEBUG
            print("⚠️ 태그 집계 로드 실패: \(error)")
            #endif
        }
    }
}

@Observable
final class ReviewService {
    var summary: ReviewSummary?
    var reviews: [PetReview] = []
    var isLoading = false
    var eligibility: ReviewEligibility?
    var isCheckingEligibility = false

    func storeKey(name: String, address: String = "") -> String {
        address.isEmpty ? name : "\(name)|\(address)"
    }

    func load(storeKey: String) async {
        isLoading = true
        defer { isLoading = false }
        guard var comps = URLComponents(string: "\(apiBaseURL)/api/pet-reviews") else { return }
        comps.queryItems = [URLQueryItem(name: "storeKey", value: storeKey)]
        guard let url = comps.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(ReviewListResponse.self, from: data)
            await MainActor.run {
                self.summary = decoded.summary
                self.reviews = decoded.reviews
            }
        } catch {
            #if DEBUG
            print("⚠️ 리뷰 로드 실패: \(error)")
            #endif
        }
    }

    func clearEligibility() {
        eligibility = nil
        isCheckingEligibility = false
    }

    func loadEligibility(storeKey: String, userId: Int) async {
        isCheckingEligibility = true
        defer { isCheckingEligibility = false }

        guard var comps = URLComponents(string: "\(apiBaseURL)/api/pet-reviews/eligibility") else { return }
        comps.queryItems = [
            URLQueryItem(name: "storeKey", value: storeKey),
            URLQueryItem(name: "userId", value: String(userId)),
        ]
        guard let url = comps.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                eligibility = nil
                return
            }
            eligibility = try JSONDecoder().decode(ReviewEligibility.self, from: data)
        } catch {
            eligibility = nil
            #if DEBUG
            print("⚠️ 리뷰 작성 자격 확인 실패: \(error)")
            #endif
        }
    }

    func submit(storeKey: String, storeName: String, userId: Int, draft: ReviewDraft) async -> Bool {
        guard let url = URL(string: "\(apiBaseURL)/api/pet-reviews") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "user_id": userId,
            "store_key": storeKey,
            "store_name": storeName,
            "rating": draft.rating,
            "revisit": draft.revisit,
            "cctv": draft.cctv,
            "pickup": draft.pickup,
            "large_dog": draft.largeDog,
            "separation_care": draft.separationCare,
            "content": draft.content,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let ok = (resp as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            if ok {
                await load(storeKey: storeKey)
                await loadEligibility(storeKey: storeKey, userId: userId)
            } else if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      body["reason"] as? String != nil {
                await loadEligibility(storeKey: storeKey, userId: userId)
            }
            return ok
        } catch {
            #if DEBUG
            print("⚠️ 리뷰 작성 실패: \(error)")
            #endif
            return false
        }
    }
}
