#!/usr/bin/env python3
"""Run the real booking model with a controlled HTTP boundary.

The model, pet/result DTOs and Korean schedule calculation are unchanged.
No real HTTP, account, database, Keychain or SwiftUI gesture is exercised.
This covers overlapping calls in one model, not server-side idempotency.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = root / 'Dog_kindergarden/Dog_kindergarden'


def declaration(source, marker):
    begin = source.index(marker)
    opening = source.index('{', begin)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin:end]


booking = (app / 'Views/Booking/BookingView.swift').read_text().split('\nstruct BookingView: View {', 1)[0]
booking = booking.replace('import SwiftUI', 'import Foundation', 1)
pet = declaration((app / 'Views/DogProfile/DogProfileView.swift').read_text(), 'struct Pet:')
result = declaration((app / 'Views/Navigation/AppRouter.swift').read_text(), 'struct BookingResult {')
schedule = (app / 'ReservationSchedule.swift').read_text()

boundaries = r'''
import Foundation
enum APIEnvironment {
    static let apiBaseURL = URL(string: "https://booking.invalid/api")!
}
enum APITransport {
    static var requests: [URLRequest] = []
    static var send: () async throws -> Data = { Data() }
    static func request(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = method; return request
    }
    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let data = try await send()
        return (data, HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
    }
}
// Only the unused store-price transport is stubbed; no price call is tested.
struct PriceResponse { let priceInfo: String? }
final class APIClient {
    static let shared = APIClient()
    func fetchStoreDetail(storeKey: String) async throws -> PriceResponse? { nil }
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
        fatalError("booking transport did not start")
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
    static let success = Data(#"{"reservation_id":101,"room_id":201,"status":"REQUEST"}"#.utf8)
    static func check(_ condition: Bool, _ message: String) {
        if !condition { failures += 1; print("FAIL: " + message) }
    }
    static func model() -> BookingViewModel {
        let vm = BookingViewModel()
        vm.pets = [Pet(pet_id: 77, name: "초코", breed: "푸들", age: 3, weight: 5,
                       gender: "여", note: "주의", image_url: "/api/pets/77/photo")]
        vm.selectedPetId = 77
        vm.selectedDate = ISO8601DateFormatter().date(from: "2026-11-19T05:00:00Z")!
        vm.startTime = vm.selectedDate; vm.hours = 2; vm.request = "원래 요청"
        return vm
    }
    static func submit(_ vm: BookingViewModel) async -> BookingResult? {
        await vm.submit(userId: 7, storeName: "예약 가게", storeKey: "store-A", storeAddress: "가게 주소",
                        storeType: "유치원", guardianPhone: "010-1234-5678", guardianAddress: "보호자 주소")
    }
    static func main() async throws {
        // Same-instance reentry must neither POST again nor finish the first call's loading phase.
        do {
            scenarios += 1
            let vm = model(), gate = Gate()
            APITransport.requests = []
            APITransport.send = {
                if APITransport.requests.count == 1 { return try await gate.wait() }
                return success
            }
            let first = Task { await submit(vm) }; await gate.started()
            vm.request = "나중에 입력한 요청"; vm.hours = 6
            var duplicateSuccesses = 0
            for _ in 0..<9 { if await submit(vm) != nil { duplicateSuccesses += 1 } }
            print("지연 중 10회 호출의 실제 전송 수: \(APITransport.requests.count)")
            check(APITransport.requests.count == 1, "overlapping booking calls must send one POST")
            check(duplicateSuccesses == 0, "rejected calls must not produce booking results")
            check(vm.isLoading, "duplicate calls must not clear the active request's loading phase")
            gate.finish(.success(success)); let booked = await first.value
            check(booked?.reservationId == 101 && booked?.roomId == 201, "first booking result must survive")
            check(booked?.dogName == "초코" && booked?.dogBreed == "푸들" && booked?.dogImageURL == "/api/pets/77/photo", "completion must use submitted pet")
            check(booked?.schedule == "2026-11-19 (목) 14:00" && booked?.durationHours == 2, "completion must use submitted schedule")
            check(!vm.isLoading && vm.errorMessage == nil, "successful booking must release loading cleanly")
            let request = APITransport.requests[0]
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            check(request.url?.path == "/api/reservations" && request.httpMethod == "POST", "wrong booking endpoint or method")
            check(body["user_id"] as? Int == 7 && body["pet_id"] as? Int == 77 && body["store_key"] as? String == "store-A", "booking recipient IDs must remain unchanged")
            check(body["request_message"] as? String == "원래 요청" && body["reservation_type"] as? String == "시간권 2시간", "posted form must be the submitted snapshot")
            check(body["start_date"] as? String == "2026-11-19 (목) 14:00" && body["end_date"] as? String == "2026-11-19 (목) 16:00", "posted Korean schedule must retain requested duration")
            check(body["guardian_phone"] as? String == "010-1234-5678" && body["guardian_address"] as? String == "보호자 주소", "guardian fields must be preserved")

            // Do not turn the guard into a permanent lock after a completed booking.
            scenarios += 1
            let previous = APITransport.requests.count
            APITransport.send = { success }
            let next = await submit(vm)
            check(next != nil && APITransport.requests.count == previous + 1 && !vm.isLoading, "a subsequent intentional booking must remain possible")
        }

        // Real parsing/failure paths must release the lock and allow a retry.
        for kind in ["network", "missing-room", "missing-reservation", "invalid-json", "canceled"] {
            scenarios += 1
            let vm = model()
            APITransport.requests = []
            APITransport.send = {
                switch kind {
                case "network": throw URLError(.notConnectedToInternet)
                case "canceled": throw URLError(.cancelled)
                case "missing-room": return Data(#"{"reservation_id":101}"#.utf8)
                case "missing-reservation": return Data(#"{"room_id":201}"#.utf8)
                default: return Data("not-json".utf8)
                }
            }
            let failed = await submit(vm)
            check(failed == nil && !vm.isLoading && vm.errorMessage != nil, "\(kind) must fail visibly and release loading")
            check(vm.request == "원래 요청", "\(kind) must preserve the form")
            APITransport.send = { success }
            let retried = await submit(vm)
            check(retried?.reservationId == 101 && APITransport.requests.count == 2, "\(kind) must allow retry")
            check(!vm.isLoading && vm.errorMessage == nil, "successful retry must clear the old error")
        }

        do {
            scenarios += 1
            let vm = model(); vm.selectedPetId = nil
            APITransport.requests = []; APITransport.send = { success }
            let invalid = await submit(vm)
            check(invalid == nil && APITransport.requests.isEmpty && !vm.isLoading, "missing pet must not send a request or lock submission")
            vm.selectedPetId = 77
            check(await submit(vm) != nil && APITransport.requests.count == 1, "selecting a valid pet must allow submission")
        }

        if failures > 0 { print("\(failures) booking assertions failed"); exit(1) }
        print("PASS: \(scenarios) real booking submission/retry/snapshot scenarios")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='booking-submission-') as tmp:
    work = Path(tmp)
    swift = work / 'Regression.swift'
    swift.write_text('\n'.join([boundaries, pet, result, schedule, booking, tests]))
    executable = work / 'regression'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-default-isolation', 'MainActor',
                    '-module-cache-path', str(work / 'module-cache'), str(swift),
                    '-o', str(executable)], check=True, timeout=120)
    subprocess.run([str(executable)], check=True, timeout=30)
