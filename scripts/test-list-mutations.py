#!/usr/bin/env python3
"""Run the actual list action bodies with isolated async API/EventKit boundaries.

This tests state mutations, not rendered SwiftUI. No live service, Keychain,
calendar, production data, or application method rewritten for the test is used.
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


api = (app / 'APIClient.swift').read_text()
reservation = (app / 'Views/MyPage/ReservationListView.swift').read_text()
favorite = (app / 'Views/MyPage/FavoritesView.swift').read_text()
phase = (app / 'Views/AsyncLoadState.swift').read_text()

boundaries = '''
import Foundation

@MainActor final class AuthSession { var userId: Int? = 1 }
@MainActor final class APIClient {
    static let shared = APIClient()
    var getReservations: (Int) async throws -> [ReservationSummary] = { _ in [] }
    var cancel: (Int) async throws -> Void = { _ in }
    var getFavorites: (Int) async throws -> [FavoriteStoreResponse] = { _ in [] }
    var remove: (Int, Int) async throws -> Void = { _, _ in }
    func fetchReservations(userId: Int) async throws -> [ReservationSummary] { try await getReservations(userId) }
    func cancelReservation(reservationId: Int) async throws { try await cancel(reservationId) }
    func fetchFavorites(userId: Int) async throws -> [FavoriteStoreResponse] { try await getFavorites(userId) }
    func removeFavorite(userId: Int, storeId: Int) async throws { try await remove(userId, storeId) }
}
@MainActor enum CalendarService {
    static var removed: [Int] = []
    static func syncReservationEvents(_ items: [ReservationSummary]) async {}
    static func removeReservationEvent(reservationId: Int) async { removed.append(reservationId) }
}
@MainActor final class Gate<T> {
    private var continuation: CheckedContinuation<T, Error>?
    var waiting: Bool { continuation != nil }
    func wait() async throws -> T { try await withCheckedThrowingContinuation { continuation = $0 } }
    func finish(_ result: Result<T, Error>) { continuation!.resume(with: result); continuation = nil }
}
'''

# Only SwiftUI storage/environment wrappers are replaced. The action bodies
# below are taken verbatim from production, including their Task boundaries.
models = '''
@MainActor final class ReservationHarness {
    let authSession = AuthSession()
    var reservations: [ReservationSummary] = []
    var loadPhase: AsyncLoadPhase = .idle
    var cancelingReservationId: Int?
    var reloadRequested = false
'''
models += declaration(reservation, '    private func load()').replace('private func', 'func', 1) + '\n'
models += declaration(reservation, '    private func cancel(').replace('private func', 'func', 1) + '\n}\n'
models += '''
@MainActor final class FavoriteHarness {
    let authSession = AuthSession()
    var favorites: [FavoriteStoreResponse] = []
    var loadPhase: AsyncLoadPhase = .idle
    var removingStoreId: Int?
'''
models += declaration(favorite, '    private func load()').replace('private func', 'func', 1) + '\n'
models += declaration(favorite, '    private func remove(').replace('private func', 'func', 1) + '\n}\n'

tests = r'''
@main struct Regression {
    @MainActor static var failures = 0
    @MainActor static func check(_ condition: Bool, _ message: String) {
        if !condition { failures += 1; print("FAIL: " + message) }
    }
    @MainActor static func settle() async { for _ in 0..<100 { await Task.yield() } }
    @MainActor static func until(_ condition: () -> Bool) async {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }
        check(false, "asynchronous action did not complete")
    }
    static func failed(_ phase: AsyncLoadPhase) -> Bool {
        if case .failed = phase { return true }; return false
    }
    static func booking(_ id: Int) -> ReservationSummary {
        ReservationSummary(reservationId: id, storeId: 9, storeName: "가게", storeType: "호텔",
            petName: "초코", petImageUrl: nil, startDate: "2026-11-04", endDate: "2026-11-05",
            reservationType: "숙박권", status: "REQUEST")
    }
    static func store(_ id: Int) -> FavoriteStoreResponse {
        FavoriteStoreResponse(storeId: id, storeKey: "store-\(id)", name: "가게\(id)",
            address: nil, phone: nil, storeType: "호텔", latitude: nil, longitude: nil)
    }
    @MainActor static func main() async {
        let api = APIClient.shared

        // Failure used to remove the row first and restore it at an obsolete index.
        do {
            let view = ReservationHarness(), gate = Gate<Void>()
            view.reservations = [booking(1), booking(2)]
            api.cancel = { id in check(id == 2, "wrong reservation canceled"); try await gate.wait() }
            view.cancel(view.reservations[1]); await until { gate.waiting }
            check(view.reservations.map(\.reservationId) == [1, 2], "pending cancellation must not remove its row")
            gate.finish(.failure(URLError(.notConnectedToInternet)))
            await until { failed(view.loadPhase) }
            check(view.reservations.map(\.reservationId) == [1, 2], "failed cancellation must keep both original rows")
            check(CalendarService.removed.isEmpty, "failed server cancellation must not delete calendar event")
        }

        // Canceled rows must remain accessible until server retention removes them.
        do {
            let view = ReservationHarness()
            view.reservations = [booking(1), booking(2)]
            api.cancel = { _ in }
            view.cancel(view.reservations[0])
            await until { view.loadPhase == .loaded }
            check(view.reservations.map(\.reservationId) == [1, 2], "successful cancellation must retain history row")
            check(view.reservations.first?.status == "CANCELED", "successful cancellation must update only target status")
            check(view.reservations.last?.status == "REQUEST", "cancellation must not change another reservation")
            check(CalendarService.removed == [1], "successful cancellation must remove target calendar event once")
        }

        // While a mutation is pending, another cancel/refresh cannot shrink its list.
        do {
            let view = ReservationHarness(), gate = Gate<Void>()
            view.reservations = [booking(1), booking(2)]
            let first = booking(1), second = booking(2)
            var posts: [Int] = [], gets = 0
            api.cancel = { id in posts.append(id); if id == 1 { try await gate.wait() } }
            api.getReservations = { _ in gets += 1; return [booking(3)] }
            view.cancel(first); await until { gate.waiting }
            view.cancel(second); await view.load(); await settle()
            check(posts == [1] && gets == 0, "cancel and refresh must not overlap a pending cancellation")
            gate.finish(.failure(URLError(.timedOut)))
            await until { failed(view.loadPhase) }
            await until { gets == 1 && view.cancelingReservationId == nil }
            check(view.reservations.map(\.reservationId) == [3], "deferred refresh must apply the latest server list after cancellation")
        }

        // An already-running GET must finish before destructive actions can begin.
        do {
            let view = ReservationHarness(), gate = Gate<[ReservationSummary]>()
            let item = booking(1)
            view.reservations = [item]
            var posts = 0
            api.cancel = { _ in posts += 1 }
            api.getReservations = { _ in try await gate.wait() }
            let load = Task { await view.load() }; await until { gate.waiting }
            view.cancel(item); await settle()
            check(posts == 0, "cancellation must wait for an in-flight list refresh")
            gate.finish(.success([item])); await load.value
        }

        // A failed favorite removal must not restore another successful removal.
        do {
            let view = FavoriteHarness(), gate = Gate<Void>()
            view.favorites = [store(1), store(2)]
            var posts: [Int] = []
            api.remove = { uid, id in
                check(uid == 1, "wrong favorites account")
                posts.append(id); if id == 1 { try await gate.wait() }
            }
            view.remove(store(1)); await until { gate.waiting }
            check(view.favorites.map(\.storeId) == [1, 2], "pending favorite removal must retain both rows")
            view.remove(store(2)); await settle()
            check(posts == [1], "favorite removals must serialize instead of restoring whole-list backups")
            gate.finish(.failure(URLError(.timedOut)))
            await until { failed(view.loadPhase) }
            view.remove(store(2)); await until { view.loadPhase == .loaded }
            check(view.favorites.map(\.storeId) == [1], "retry must remove only the successful favorite")
        }

        do {
            let view = FavoriteHarness(), gate = Gate<[FavoriteStoreResponse]>()
            view.favorites = [store(1)]
            var posts = 0
            api.remove = { _, _ in posts += 1 }
            api.getFavorites = { _ in try await gate.wait() }
            let load = Task { await view.load() }; await until { gate.waiting }
            view.remove(store(1)); await settle()
            check(posts == 0, "favorite removal must wait for an in-flight refresh")
            gate.finish(.success([store(1)])); await load.value
        }

        do {
            let view = FavoriteHarness(), gate = Gate<Void>()
            view.favorites = [store(1)]
            var gets = 0
            api.remove = { _, _ in try await gate.wait() }
            api.getFavorites = { _ in gets += 1; return [] }
            view.remove(store(1)); await until { gate.waiting }
            await view.load()
            check(gets == 0, "favorite refresh must not overlap removal")
            gate.finish(.success(())); await until { view.loadPhase == .loaded }
            await settle()
            check(view.favorites.isEmpty, "successful removal must produce the empty state")
            await view.load()
            check(gets == 1, "completed removal must release refresh guard")
        }

        // This exact order crashed the old index-based rollback: cancel index 2,
        // refresh to an empty list, then receive the cancellation's network error.
        do {
            let view = ReservationHarness(), gate = Gate<Void>()
            view.reservations = [booking(1), booking(2), booking(3)]
            api.cancel = { _ in try await gate.wait() }
            api.getReservations = { _ in [] }
            view.cancel(view.reservations[2]); await until { gate.waiting }
            await view.load()
            gate.finish(.failure(URLError(.timedOut)))
            await until { failed(view.loadPhase) }
            await until { view.cancelingReservationId == nil }
            check(view.reservations.isEmpty, "failed index-2 cancellation must safely apply the deferred empty server list")
        }

        // A live update received during cancellation is deferred, not lost until
        // the next 60-second safety poll. Failed actions still display their error.
        for succeeds in [true, false] {
            let view = ReservationHarness(), gate = Gate<Void>()
            view.reservations = [booking(1), booking(2)]
            var gets = 0
            api.cancel = { _ in try await gate.wait() }
            api.getReservations = { _ in
                gets += 1
                var first = booking(1), second = booking(2)
                if succeeds { first.status = "CANCELED" }
                second.status = "CONFIRMED"
                return [first, second]
            }
            view.cancel(booking(1)); await until { gate.waiting }
            await view.load(); await view.load()
            check(gets == 0, "live updates must not start GET during mutation")
            gate.finish(succeeds ? .success(()) : .failure(URLError(.timedOut)))
            await until { gets == 1 && view.cancelingReservationId == nil && !view.loadPhase.isLoading }
            check(view.reservations.last?.status == "CONFIRMED", "queued live update must refresh other reservation immediately")
            check(gets == 1, "multiple queued updates must coalesce into one refresh")
            if !succeeds { check(failed(view.loadPhase), "successful queued GET must not hide cancellation failure") }
        }

        do {
            let view = ReservationHarness(), post = Gate<Void>(), get = Gate<[ReservationSummary]>()
            view.reservations = [booking(1), booking(2)]
            var gets = 0
            var canceled = booking(1), confirmed = booking(2)
            canceled.status = "CANCELED"; confirmed.status = "CONFIRMED"
            api.cancel = { _ in try await post.wait() }
            api.getReservations = { _ in
                gets += 1
                if gets == 1 { return try await get.wait() }
                return [canceled, confirmed]
            }
            view.cancel(booking(1)); await until { post.waiting }
            await view.load()
            post.finish(.success(())); await until { get.waiting }
            // A second server change occurs after the first GET took its snapshot.
            await view.load(); await view.load()
            get.finish(.success([canceled, booking(2)]))
            await until { gets == 2 && !view.loadPhase.isLoading }
            check(view.reservations.last?.status == "CONFIRMED", "change received during deferred GET must not be lost")
            check(gets == 2, "signals during a GET must coalesce into exactly one additional GET")
        }

        if failures > 0 { print("\(failures) list mutation assertions failed"); exit(1) }
        print("PASS: 11 production list-action scenarios (pending/failure/success/history/calendar/cancel-refresh/favorite-refresh/index-2 crash/queued live updates/in-flight GET updates)")
    }
}
'''

source = boundaries + '\n'.join([
    declaration(api, 'struct ReservationSummary:'),
    declaration(api, 'struct FavoriteStoreResponse:'),
    declaration(phase, 'enum AsyncLoadPhase:'),
]) + models + tests

with tempfile.TemporaryDirectory(prefix='list-mutations-') as tmp:
    path = Path(tmp)
    swift = path / 'Regression.swift'
    swift.write_text(source)
    executable = path / 'regression'
    subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', str(path / 'module-cache'),
                    str(swift), '-o', str(executable)], check=True, timeout=120)
    subprocess.run([str(executable)], check=True, timeout=30)
