#!/usr/bin/env python3
"""Run the real Swift review service with controlled response ordering.

Only HTTP transport and the API base URL are isolated. The service, JSON
decoder, models and loading phases come from production. No live API,
account, Keychain, defaults or rendered SwiftUI is exercised.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = root / 'Dog_kindergarden/Dog_kindergarden'
service = (app / 'Views/Review/ReviewService.swift').read_text()
phase = (app / 'Views/AsyncLoadState.swift').read_text()
phase = phase[phase.index('enum AsyncLoadPhase:'):phase.index('/// 최초 조회')]

boundaries = r'''
import Foundation
import Observation

enum APIEnvironment {
    static let apiBaseURL = URL(string: "https://review.invalid/api")!
}
enum APITransport {
    static var send: (URLRequest) async throws -> Data = { _ in throw URLError(.badURL) }
    static func request(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = method; return request
    }
    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data = try await send(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
final class Gate {
    private var continuation: CheckedContinuation<Data, Error>?
    func wait() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func started() async {
        for _ in 0..<10_000 {
            if continuation != nil { return }; await Task.yield()
        }
        fatalError("transport did not start")
    }
    func finish(_ result: Result<Data, Error>) {
        continuation!.resume(with: result); continuation = nil
    }
}
'''

tests = r'''
@main struct Regression {
    static var failures = 0
    static var scenarios = 0
    static let old = Data(#"{"summary":{"count":1,"avg_rating":3,"cctv":0,"pickup":0,"large_dog":0,"separation_care":0},"reviews":[{"id":1,"verified":1,"user_name":"이전","rating":3,"revisit":0,"cctv":0,"pickup":0,"large_dog":0,"separation_care":0,"content":"이전 리뷰","created_at":"2026-11-18 00:00:00"}]}"#.utf8)
    static let fresh = Data(#"{"summary":{"count":2,"avg_rating":4,"cctv":1,"pickup":1,"large_dog":1,"separation_care":1},"reviews":[{"id":2,"verified":1,"user_name":"최신","rating":5,"revisit":1,"cctv":1,"pickup":1,"large_dog":1,"separation_care":1,"content":"방금 등록한 리뷰","created_at":"2026-11-18 00:01:00"}]}"#.utf8)
    static let eligible = Data(#"{"eligible":true,"reason":"eligible"}"#.utf8)
    static let reviewed = Data(#"{"eligible":false,"reason":"already_reviewed"}"#.utf8)
    static func check(_ value: Bool, _ message: String) {
        if !value { failures += 1; print("FAIL: " + message) }
    }
    static func main() async {
        // The same-key comparison alone accepts older successes and failures.
        for eligibility in [false, true] {
            for failOld in [false, true] {
                scenarios += 1
                let service = ReviewService(), gate = Gate()
                var calls = 0
                APITransport.send = { _ in
                    calls += 1
                    return calls == 1 ? try await gate.wait() : eligibility ? reviewed : fresh
                }
                let oldRequest = Task {
                    if eligibility { await service.loadEligibility(storeKey: "A", userId: 7) }
                    else { await service.load(storeKey: "A") }
                }
                await gate.started()
                if eligibility { await service.loadEligibility(storeKey: "A", userId: 7) }
                else { await service.load(storeKey: "A") }
                gate.finish(failOld ? .failure(URLError(.timedOut)) : .success(eligibility ? eligible : old))
                await oldRequest.value
                if eligibility {
                    check(service.eligibility?.eligible == false, "old eligibility must not re-enable reviewed booking")
                    check(service.eligibilityLoadPhase == .loaded, "old eligibility failure must not replace fresh success")
                } else {
                    check(service.reviews.map(\.id) == [2] && service.summary?.count == 2, "old list must not replace fresh reviews or summary")
                    check(service.loadPhase == .loaded, "old list failure must not replace fresh success")
                }
            }
        }

        // Clear/reopen can return to the same key (A -> clear -> A).
        for eligibility in [false, true] {
            scenarios += 1
            let service = ReviewService(), gate = Gate()
            var calls = 0
            APITransport.send = { _ in
                calls += 1
                return calls == 1 ? try await gate.wait() : eligibility ? reviewed : fresh
            }
            let oldRequest = Task {
                if eligibility { await service.loadEligibility(storeKey: "A", userId: 7) }
                else { await service.load(storeKey: "A") }
            }
            await gate.started(); service.clear()
            if eligibility { await service.loadEligibility(storeKey: "A", userId: 7) }
            else { await service.load(storeKey: "A") }
            gate.finish(.success(eligibility ? eligible : old)); await oldRequest.value
            check(eligibility ? service.eligibility?.eligible == false : service.reviews.map(\.id) == [2], "clear/reopen must reject old same-key response")
        }

        // Exercise the real POST -> load -> eligibility flow, not a copied mutation.
        do {
            scenarios += 1
            let service = ReviewService(), gate = Gate()
            var gets = 0
            APITransport.send = { request in
                if request.httpMethod == "POST" { return Data("{}".utf8) }
                if request.url!.lastPathComponent == "eligibility" { return reviewed }
                gets += 1
                return gets == 1 ? try await gate.wait() : fresh
            }
            let oldRequest = Task { await service.load(storeKey: "A") }
            await gate.started()
            let submitted = await service.submit(storeKey: "A", storeName: "가게", userId: 7, draft: ReviewDraft())
            check(submitted, "successful review submit must remain successful")
            gate.finish(.success(old)); await oldRequest.value
            check(service.reviews.map(\.id) == [2] && service.summary?.count == 2, "pre-submit GET must not hide newly submitted review")
            check(service.eligibility?.eligible == false, "successful submit must update eligibility")
        }

        // A current failure must still be visible without discarding cached data.
        for eligibility in [false, true] {
            scenarios += 1
            let service = ReviewService()
            APITransport.send = { _ in eligibility ? reviewed : fresh }
            if eligibility { await service.loadEligibility(storeKey: "A", userId: 7) }
            else { await service.load(storeKey: "A") }
            APITransport.send = { _ in throw URLError(.notConnectedToInternet) }
            if eligibility { await service.loadEligibility(storeKey: "A", userId: 7) }
            else { await service.load(storeKey: "A") }
            let phase = eligibility ? service.eligibilityLoadPhase : service.loadPhase
            if case .failed = phase {} else { check(false, "current failure must be reported") }
            check(eligibility ? service.eligibility?.eligible == false : service.reviews.map(\.id) == [2], "current failure must preserve cached data")
        }

        if failures > 0 { print("\(failures) review assertions failed"); exit(1) }
        print("PASS: \(scenarios) real review-service ordering/submit/failure scenarios")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='review-state-') as tmp:
    work = Path(tmp)
    swift = work / 'Regression.swift'
    swift.write_text(boundaries + phase + service + tests)
    executable = work / 'regression'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-default-isolation', 'MainActor',
                    '-module-cache-path', str(work / 'module-cache'), str(swift),
                    '-o', str(executable)], check=True, timeout=120)
    subprocess.run([str(executable)], check=True, timeout=30)
