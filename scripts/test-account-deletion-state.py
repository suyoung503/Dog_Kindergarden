#!/usr/bin/env python3
"""실제 탈퇴 함수의 await 경계를 검사한다. SwiftUI 저장소·API·SDK·기기 상태만 격리한다.

운영 탈퇴, 네트워크, Keychain, UserDefaults, 캘린더, 카카오 SDK는 실행하지 않는다.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
view = (root / 'Dog_kindergarden/Dog_kindergarden/Views/MyPage/MyPageView.swift').read_text()
begin = view.index('    private func deleteAccount()')
opening = view.index('{', begin)
depth, end = 1, opening + 1
while depth:
    depth += (view[end] == '{') - (view[end] == '}')
    end += 1
action = view[begin:end].replace('private func', 'func', 1)

boundaries = r'''
import Foundation

@MainActor enum AuthTokenStore {
    static var token: String? = "session-A"
    static func load() -> String? { token }
}
@MainActor enum APIEnvironment {
    static var apiBaseURL = URL(string: "https://api-a.example/api")!
}
enum AccountDeletionError: Error { case activeReservations(customer: Int, owner: Int) }
enum FixtureError: Error { case unavailable, unauthorized }
@MainActor final class AuthSession {
    var userId: Int? = 1
    var deletions = 0
    func completeAccountDeletion() { deletions += 1; userId = nil; AuthTokenStore.token = nil }
}
@MainActor final class UserProfile {
    var name = "계정 A 프로필"
    var deletions = 0
    func clearAfterAccountDeletion() { deletions += 1; name = "보호자" }
}
@MainActor final class AppRouter {
    var screen = "계정 A 화면"
    var deletions: [Int] = []
    func clearAccountData(userId: Int) { deletions.append(userId); screen = "start" }
}
@MainActor final class AppNotificationService {
    static let shared = AppNotificationService()
    var inbox = "계정 A 알림"
    var deletions: [Int] = []
    func clearAfterAccountDeletion(userId: Int) { deletions.append(userId); inbox = "" }
}
@MainActor enum CalendarService {
    static var mappings = "계정 A 캘린더 연결"
    static var deletions = 0
    static func clearLocalMappings() { deletions += 1; mappings = "" }
}
@MainActor final class Gate {
    private var continuation: CheckedContinuation<Void, Error>?
    var waiting: Bool { continuation != nil }
    func wait() async throws { try await withCheckedThrowingContinuation { continuation = $0 } }
    func finish(_ result: Result<Void, Error>) { continuation!.resume(with: result); continuation = nil }
}
@MainActor final class APIClient {
    static let shared = APIClient()
    var requests: [Int] = []
    var send: () async throws -> Void = {}
    func deleteAccount(userId: Int) async throws { requests.append(userId); try await send() }
}
@MainActor final class Harness {
    let authSession = AuthSession()
    let userProfile = UserProfile()
    let router = AppRouter()
    var isDeletingAccount = false
    var accountDeletionError: String?
    var showAccountDeletionSheet = true
'''

tests = r'''
}
@main struct Regression {
    @MainActor static var failures = 0
    @MainActor static var scenarios = 0
    @MainActor static func check(_ condition: Bool, _ message: String) {
        if !condition { failures += 1; print("FAIL: \(message)") }
    }
    @MainActor static func fixture() -> Harness {
        AuthTokenStore.token = "session-A"
        APIEnvironment.apiBaseURL = URL(string: "https://api-a.example/api")!
        APIClient.shared.requests = []
        APIClient.shared.send = {}
        AppNotificationService.shared.inbox = "계정 A 알림"
        AppNotificationService.shared.deletions = []
        CalendarService.mappings = "계정 A 캘린더 연결"
        CalendarService.deletions = 0
        return Harness()
    }
    @MainActor static func until(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline { fatalError("fixture gate timeout") }
            await Task.yield()
        }
    }
    @MainActor static func checkNoCleanup(_ v: Harness, _ label: String) {
        check(v.authSession.deletions == 0 && v.userProfile.deletions == 0, "\(label): 인증/프로필 초기화 금지")
        check(v.router.deletions.isEmpty && AppNotificationService.shared.deletions.isEmpty, "\(label): 화면/알림 초기화 금지")
        check(CalendarService.deletions == 0, "\(label): 캘린더 연결 초기화 금지")
        check(!v.isDeletingAccount, "\(label): 완료 후 진행 중 표시 해제")
    }
    @MainActor static func checkDeleted(_ v: Harness, _ label: String) {
        check(v.authSession.userId == nil && AuthTokenStore.load() == nil, "\(label): 현재 계정 로그아웃")
        check(v.authSession.deletions == 1 && v.userProfile.deletions == 1, "\(label): 정리 한 번")
        check(v.router.deletions == [1] && AppNotificationService.shared.deletions == [1], "\(label): 해당 계정 화면/알림 정리")
        check(CalendarService.deletions == 1 && !v.showAccountDeletionSheet, "\(label): 연결/시트 정리")
        check(!v.isDeletingAccount && v.accountDeletionError == nil, "\(label): 정상 완료 상태")
    }
    @MainActor static func main() async {
        do {
            scenarios += 1
            let v = fixture(); await v.deleteAccount()
            checkDeleted(v, "정상 성공")
            check(APIClient.shared.requests == [1], "현재 사용자 ID로 한 번 요청")
        }
        for blocked in [false, true] {
            scenarios += 1
            let v = fixture()
            APIClient.shared.send = {
                if blocked { throw AccountDeletionError.activeReservations(customer: 2, owner: 3) }
                throw FixtureError.unavailable
            }
            await v.deleteAccount(); checkNoCleanup(v, "현재 요청 실패")
            check(v.showAccountDeletionSheet && v.accountDeletionError != nil, "실패 안내와 시트 유지")
            if blocked { check(v.accountDeletionError!.contains("2건") && v.accountDeletionError!.contains("3건"), "보호자/가게 진행 예약 안내 유지") }
        }
        do {
            scenarios += 1
            let v = fixture(), gate = Gate(); APIClient.shared.send = { try await gate.wait() }
            let first = Task { await v.deleteAccount() }; await until { gate.waiting }
            await v.deleteAccount(); check(APIClient.shared.requests == [1], "중복 클릭 단일 전송")
            gate.finish(.success(())); await first.value; checkDeleted(v, "단일 전송 성공")
        }
        for change in ["user", "token", "server", "expired"] {
            for outcome in ["success", "failure", "blocked"] {
                scenarios += 1
                let v = fixture(), gate = Gate(); APIClient.shared.send = { try await gate.wait() }
                let task = Task { await v.deleteAccount() }; await until { gate.waiting }
                // RootView의 세션 만료→시작 화면·재로그인 또는 API 변경 뒤 결과를 전달한다.
                if change == "user" { v.authSession.userId = 2; AuthTokenStore.token = "session-B" }
                if change == "token" { AuthTokenStore.token = "replacement-A" }
                if change == "server" { APIEnvironment.apiBaseURL = URL(string: "https://api-b.example/api")! }
                if change == "expired" { v.authSession.userId = nil; AuthTokenStore.token = nil }
                v.userProfile.name = "현재 프로필"
                v.router.screen = "현재 화면"
                v.accountDeletionError = "현재 화면 안내"
                AppNotificationService.shared.inbox = "현재 알림"
                CalendarService.mappings = "현재 연결"
                let expectedUser = v.authSession.userId, expectedToken = AuthTokenStore.load()
                if outcome == "success" { gate.finish(.success(())) }
                else if outcome == "blocked" { gate.finish(.failure(AccountDeletionError.activeReservations(customer: 9, owner: 8))) }
                else { gate.finish(.failure(FixtureError.unavailable)) }
                await task.value
                let label = "\(change)/\(outcome)"
                checkNoCleanup(v, label)
                check(v.authSession.userId == expectedUser && AuthTokenStore.load() == expectedToken, "\(label): 현재 인증 보존")
                check(v.userProfile.name == "현재 프로필" && v.router.screen == "현재 화면", "\(label): 현재 프로필/화면 보존")
                check(AppNotificationService.shared.inbox == "현재 알림" && CalendarService.mappings == "현재 연결", "\(label): 알림/일정 연결 보존")
                check(v.accountDeletionError == "현재 화면 안내" && v.showAccountDeletionSheet, "\(label): 오래된 응답 안내 차단")
            }
        }
        for token in [nil, ""] as [String?] {
            scenarios += 1
            let v = fixture(); AuthTokenStore.token = token
            // 실제 서버처럼 인증 없는 요청은 성공 응답이 아니라 오류로 끝낸다.
            APIClient.shared.send = { throw FixtureError.unauthorized }
            await v.deleteAccount()
            check(v.accountDeletionError != nil, "인증 없는 요청 오류는 정리 없이 안내")
            checkNoCleanup(v, "토큰 없음")
        }
        do {
            scenarios += 1
            let v = fixture(); v.authSession.userId = nil; await v.deleteAccount()
            check(APIClient.shared.requests.isEmpty, "사용자 없으면 탈퇴 전송 금지"); checkNoCleanup(v, "사용자 없음")
        }
        do {
            scenarios += 1
            let v = fixture(), gate = Gate(); APIClient.shared.send = { try await gate.wait() }
            let task = Task { await v.deleteAccount() }; await until { gate.waiting }
            task.cancel(); gate.finish(.success(())); await task.value
            checkDeleted(v, "Task 취소만으로 이미 성공한 현재 계정 탈퇴 정리를 생략하지 않음")
        }
        if failures > 0 { print("\(failures)개 assertion 실패 / \(scenarios)개 시나리오"); exit(1) }
        print("PASS: 실제 탈퇴 함수 \(scenarios)개 시나리오(성공·차단·실패·단일전송·계정/토큰/API 변경·만료·Task 취소)")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='account-deletion-state-') as tmp:
    path = Path(tmp)
    swift = path / 'Regression.swift'
    swift.write_text(boundaries + action + tests)
    executable = path / 'regression'
    subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', str(path / 'module-cache'),
                    str(swift), '-o', str(executable)], check=True, timeout=120)
    subprocess.run([str(executable)], check=True, timeout=40)
