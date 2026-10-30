#!/usr/bin/env python3
"""Run the real booking submission against a local Swift transport, without Xcode or networking."""
from pathlib import Path
import subprocess
import tempfile
import os

root = Path(__file__).resolve().parents[1]
app = root / 'Dog_kindergarden/Dog_kindergarden'

def declaration(path, start):
    source = (app / path).read_text()
    begin = source.index(start)
    opening = source.index('{', begin)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin:end]

model = declaration('Views/Booking/BookingView.swift', 'final class BookingViewModel')
assert '"guardian_phone"' in model and '"guardian_address"' in model, 'Actual booking contact inputs must be sent with the reservation'
result = declaration('Views/Navigation/AppRouter.swift', 'struct BookingResult')
pet = declaration('Views/DogProfile/DogProfileView.swift', 'struct Pet:')
source = '''import Foundation
struct StoreDetail { let priceInfo: String? }
@MainActor enum APIEnvironment { static let apiBaseURL = URL(string: "https://example.invalid/api")! }
@MainActor enum APIClient {
    static let shared = Client()
    struct Client { func fetchStoreDetail(storeKey: String) async throws -> StoreDetail? { nil } }
}
@MainActor enum APITransport {
    static var respond: ((URLRequest) -> Data)?
    static func request(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = method; return request
    }
    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let bytes = respond!(request)
        await Task.yield()
        return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
''' + (app / 'ReservationSchedule.swift').read_text() + '\n' + pet + '\n' + result + '\n@MainActor\n' + model + '''
@main struct Regression {
    @MainActor static func main() async throws {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        let legacy = BookingResult(reservationId: 1, roomId: 2, storeName: "가게", dogName: "강아지",
                                   dogBreed: "", schedule: "", price: "", isAllDay: false, durationHours: 1)
        let legacyPhoto = Mirror(reflecting: legacy).children.first { $0.label == "dogImageURL" }?.value as? String
        check(legacyPhoto == nil, "Existing BookingResult calls must default to no photo")
        let photos: [String?] = ["/api/pets/11/photo", "data:image/jpeg;base64,YWJj", nil]
        for selectedIndex in [0, 1] {
            for changeDuringResponse in [false, true] {
                for photo in photos {
                    let vm = BookingViewModel()
                    vm.pets = [
                        Pet(pet_id: 11, name: "코코", breed: "푸들", age: nil, weight: nil, gender: nil, note: nil, image_url: photo),
                        Pet(pet_id: 22, name: "보리", breed: "시바", age: nil, weight: nil, gender: nil, note: nil, image_url: photo)
                    ]
                    let selected = vm.pets[selectedIndex]
                    vm.selectedPetId = selected.pet_id
                    vm.selectedDate = ISO8601DateFormatter().date(from: "2026-12-31T09:00:00+09:00")!
                    vm.startTime = ISO8601DateFormatter().date(from: "2001-01-01T23:30:00+09:00")!
                    check(vm.dateLabel == "2026-12-31 (목)", "Selected date display must use KST")
                    check(vm.timeLabel == "23:30", "Selected clock display must use KST")
                    vm.hours = 3
                    vm.storePriceInfo = "시간권 10,000원"
                    let expectedPrice = vm.selectedPriceText
                    APITransport.respond = { request in
                        let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                        check(body["pet_id"] as? Int == selected.pet_id, "POST must use selected pet")
                        check(body["image_url"] == nil, "Photo must not change reservation API payload")
                        check(body["start_date"] as? String == "2026-12-31 (목) 23:30", "POST start must combine selected KST day and time")
                        check(body["end_date"] as? String == "2027-01-01 (금) 02:30", "POST end must add the requested 3 hours across year boundary")
                        check(body["reservation_type"] as? String == "시간권 3시간", "POST must preserve requested duration")
                        if changeDuringResponse {
                            vm.selectedPetId = vm.pets[1 - selectedIndex].pet_id
                            vm.pets = []
                            vm.selectedService = "종일권"
                            vm.hours = 6
                            vm.selectedDate = Date.distantFuture
                            vm.startTime = Date.distantFuture
                            vm.storePriceInfo = nil
                        }
                        return Data(#"{"reservation_id":31,"room_id":41}"#.utf8)
                    }
                    let result = await vm.submit(userId: 1, storeName: "유치원", storeKey: "store", storeAddress: "서울", storeType: "유치원")
                    check(result?.dogName == selected.name, "Name must match submitted pet, not changed selection")
                    check(result?.dogBreed == selected.breed, "Breed must match submitted pet")
                    let reflectedPhoto = result.flatMap { result in Mirror(reflecting: result).children.first { $0.label == "dogImageURL" }?.value as? String }
                    check(reflectedPhoto == photo, "Photo must match submitted pet (including nil)")
                    check(result?.schedule == "2026-12-31 (목) 23:30", "Schedule must use submitted date/time snapshot")
                    check(result?.price == expectedPrice, "Price must use submission snapshot")
                    check(result?.isAllDay == false && result?.durationHours == 3, "Duration must use submission snapshot")
                }
            }
        }
        for contact in [nil, "", "예약별 입력"] as [String?] {
            let vm = BookingViewModel()
            vm.pets = [Pet(pet_id: 11, name: "코코", breed: nil, age: nil, weight: nil, gender: nil, note: nil, image_url: nil)]
            vm.selectedPetId = 11
            APITransport.respond = { request in
                let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                check(body["guardian_phone"] as? String == contact, "Phone input must preserve missing/empty/specific value")
                check(body["guardian_address"] as? String == contact, "Address input must preserve missing/empty/specific value")
                return Data(#"{"reservation_id":31,"room_id":41}"#.utf8)
            }
            _ = await vm.submit(userId: 1, storeName: "유치원", storeKey: "store", storeAddress: "서울", storeType: "유치원", guardianPhone: contact, guardianAddress: contact)
        }
        for service in ["종일권", "하루 숙박권"] {
            let vm = BookingViewModel()
            vm.pets = [Pet(pet_id: 11, name: "코코", breed: nil, age: nil, weight: nil, gender: nil, note: nil, image_url: nil)]
            vm.selectedPetId = 11
            vm.selectedService = service
            vm.selectedDate = ISO8601DateFormatter().date(from: "2026-10-28T23:30:00+09:00")!
            vm.startTime = ISO8601DateFormatter().date(from: "2001-01-01T14:30:00+09:00")!
            vm.hours = 6
            APITransport.respond = { request in
                let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                check(body["start_date"] as? String == "2026-10-28 (수)", "Non-hourly POST must remain date-only")
                check(body["end_date"] as? String == "2026-10-28 (수)", "Non-hourly POST must not add hourly duration")
                check(body["reservation_type"] as? String == service, "Non-hourly service must remain unchanged")
                vm.selectedService = "시간권"
                vm.hours = 1
                return Data(#"{"reservation_id":31,"room_id":41}"#.utf8)
            }
            let result = await vm.submit(userId: 1, storeName: "유치원", storeKey: "store", storeAddress: "서울", storeType: "유치원")
            check(result?.schedule == "2026-10-28 (수)", "Non-hourly completion must remain date-only")
            check(result?.isAllDay == true && result?.durationHours == 1, "Non-hourly completion must keep submitted service snapshot")
        }
        if !failures.isEmpty {
            for failure in Set(failures).sorted() { print("FAIL: " + failure) }
            exit(1)
        }
        print("PASS: 12 booking selection/photo/suspended-response cases plus 3 guardian contact cases and 2 date-only service cases")
    }
}
'''
view = (app / 'Views/Booking/BookingDoneView.swift').read_text()
with tempfile.TemporaryDirectory(prefix='booking-photo-') as tmp:
    swift = Path(tmp) / 'BookingPhotoRegression.swift'
    binary = Path(tmp) / 'BookingPhotoRegression'
    swift.write_text(source)
    subprocess.run(['swiftc', '-module-cache-path', str(Path(tmp) / 'module-cache'), '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
assert 'AuthenticatedPetImage(value: booking?.dogImageURL)' in view, 'Completion must reuse private pet photo renderer'
assert '.frame(width: 128, height: 128)' in view and '.clipShape(Circle())' in view
print('PASS: completion photo renderer and circular frame wiring')

# Swift Testing exercises the same Foundation helper used by submission and owner detail.
with tempfile.TemporaryDirectory(prefix='reservation-schedule-') as tmp:
    package = Path(tmp)
    (package / 'Sources/Dog_kindergarden').mkdir(parents=True)
    (package / 'Tests/ScheduleTests').mkdir(parents=True)
    (package / 'Package.swift').write_text("""// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ReservationScheduleRegression", platforms: [.macOS(.v14)], targets: [.target(name: "Dog_kindergarden"), .testTarget(name: "ScheduleTests", dependencies: ["Dog_kindergarden"])])
""")
    (package / 'Sources/Dog_kindergarden/ReservationSchedule.swift').write_text((app / 'ReservationSchedule.swift').read_text())
    (package / 'Tests/ScheduleTests/ReservationScheduleTests.swift').write_text((root / 'Dog_kindergarden/Dog_kindergardenTests/ReservationScheduleTests.swift').read_text())
    subprocess.run(['swift', 'test', '--disable-sandbox', '--package-path', tmp, '--scratch-path', str(package / '.build')], check=True, env={**os.environ, 'CLANG_MODULE_CACHE_PATH': str(package / 'module-cache'), 'SWIFTPM_MODULECACHE_OVERRIDE': str(package / 'module-cache')})
