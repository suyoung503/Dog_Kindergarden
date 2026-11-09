#!/usr/bin/env python3
"""실제 탈퇴·로그인 설치·세션 종료 함수의 경계를 검사한다. 외부 상태만 격리한다.

운영 탈퇴, 네트워크, Keychain, UserDefaults, 캘린더, 카카오 SDK는 실행하지 않는다.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
view = (root / 'Dog_kindergarden/Dog_kindergarden/Views/MyPage/MyPageView.swift').read_text()
auth = (root / 'Dog_kindergarden/Dog_kindergarden/AuthSession.swift').read_text()


# 실제 함수 본문은 바꾸지 않고 SwiftUI/SDK 외부 경계에서만 격리한다.
def declaration(source, marker):
    begin = source.index(marker)
    opening = source.index('{', begin)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin:end].replace('private func', 'func', 1)


action = declaration(view, '    private func deleteAccount()')

boundaries = r'''
import Foundation

@MainActor final class MemoryDefaults {
    var values: [String: Any] = [:]
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
@MainActor enum UserDefaults { static let standard = MemoryDefaults() }
@MainActor enum AuthTokenStore {
    static var token: String? = "session-A"
    static func load() -> String? { token }
    static func save(_ value: String) { token = value }
    static func clear() { token = nil }
}
@MainActor enum APIEnvironment {
    static var apiBaseURL = URL(string: "https://api-a.example/api")!
}
enum AccountDeletionError: Error { case activeReservations(customer: Int, owner: Int) }
enum FixtureError: Error { case unavailable, unauthorized }
enum APIError: Error { case httpStatus(Int), badStatus }
@MainActor final class AuthSession {
    var userId: Int? = 1
    // ACTUAL_AUTH_GENERATION
    var isLoading = false
    var nickname = "계정 A"
    var isOwner = false
    var isAdmin = false
    var errorMessage: String?
    var deletions = 0
    func login(userId: Int, token: String, profile: UserProfile? = nil) {
        let data = try! JSONSerialization.data(withJSONObject: ["user_id": userId, "session_token": token, "nickname": "새 로그인"])
        let response = HTTPURLResponse(url: APIEnvironment.apiBaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        try! applyLoginResponse(data: data, response: response, fallbackNickname: "", profile: profile)
    }
    func expire() { clearLocalSession() }
    func completeAccountDeletion() { deletions += 1; expire() }
    // ACTUAL_AUTH_ACTIONS
}
@MainActor final class UserProfile {
    var name = "계정 A 프로필"
    var phone = "01011112222"
    var email = "a@example.test"
    var address = "계정 A 주소"
    func applyServerEmail(_ value: String?) { email = value ?? "" }
    var deletions = 0
    func clearAfterAccountDeletion() { deletions += 1; name = "보호자" }
}
@MainActor final class AppRouter {
    var screen = "계정 A 화면"
    var deletions: [Int] = []
    var purges: [Int] = []
    func clearAccountData(userId: Int, clearCurrentState: Bool = true) {
        purges.append(userId)
        if clearCurrentState { deletions.append(userId); screen = "start" }
    }
}
@MainActor final class AppNotificationService {
    static let shared = AppNotificationService()
    var inbox = "계정 A 알림"
    var deletions: [Int] = []
    var purges: [Int] = []
    func clearAfterAccountDeletion(userId: Int, clearCurrentState: Bool = true) {
        purges.append(userId)
        if clearCurrentState { deletions.append(userId); inbox = "" }
    }
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
        AppNotificationService.shared.purges = []
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
    @MainActor static func checkExpiredCleanup(_ v: Harness, _ label: String, expectedUser: Int? = nil) {
        check(v.authSession.userId == expectedUser && AuthTokenStore.load() == nil, "\(label): 기존 만료 처리 순서 유지")
        check(v.authSession.deletions == 0 && v.router.deletions.isEmpty, "\(label): SDK 연결 해제/화면 이동 재실행 금지")
        check(v.userProfile.deletions == 1 && CalendarService.deletions == 1, "\(label): 과거 프로필/캘린더 연결 정리")
        check(AppNotificationService.shared.deletions == [1] && v.router.purges == [1], "\(label): 과거 계정 알림/최근 본 가게 정리")
        check(!v.isDeletingAccount, "\(label): 진행 표시 해제")
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
                if change == "user" { v.authSession.login(userId: 2, token: "session-B") }
                if change == "token" { v.authSession.login(userId: 1, token: "replacement-A") }
                if change == "server" { APIEnvironment.apiBaseURL = URL(string: "https://api-b.example/api")! }
                if change == "expired" { v.authSession.expire() }
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
                if change == "expired" && outcome == "success" {
                    checkExpiredCleanup(v, label)
                    check(v.router.screen == "현재 화면" && v.accountDeletionError == "현재 화면 안내", "만료 성공은 현재 시작 화면/안내 보존")
                    continue
                }
                checkNoCleanup(v, label)
                check(v.authSession.userId == expectedUser && AuthTokenStore.load() == expectedToken, "\(label): 현재 인증 보존")
                check(v.userProfile.name == "현재 프로필" && v.router.screen == "현재 화면", "\(label): 현재 프로필/화면 보존")
                check(AppNotificationService.shared.inbox == "현재 알림" && CalendarService.mappings == "현재 연결", "\(label): 알림/일정 연결 보존")
                check(v.accountDeletionError == "현재 화면 안내" && v.showAccountDeletionSheet, "\(label): 오래된 응답 안내 차단")
                let expectedPurges = outcome == "success" && change != "server" ? [1] : []
                check(v.router.purges == expectedPurges && AppNotificationService.shared.purges == expectedPurges, "\(label): 같은 서버의 탈퇴 계정 저장값만 제거")
            }
        }
        for withProfile in [false, true] {
            scenarios += 1
            let v = fixture(), gate = Gate(); APIClient.shared.send = { try await gate.wait() }
            let task = Task { await v.deleteAccount() }; await until { gate.waiting }
            v.authSession.expire()
            v.authSession.login(userId: 2, token: "session-B", profile: withProfile ? v.userProfile : nil)
            if withProfile { v.userProfile.name = "계정 B 프로필" }
            v.authSession.expire()
            CalendarService.mappings = "계정 B 연결"
            AppNotificationService.shared.inbox = "계정 B 알림"
            v.router.screen = "계정 B 로그아웃 화면"
            let name = v.userProfile.name
            gate.finish(.success(())); await task.value
            checkNoCleanup(v, "B 로그인/로그아웃")
            check(v.userProfile.name == name && CalendarService.mappings == "계정 B 연결", "프로필 전달 여부와 관계없이 B 캐시 보존")
            check(v.router.screen == "계정 B 로그아웃 화면" && AppNotificationService.shared.inbox == "계정 B 알림", "B의 로그아웃 후 상태도 보존")
            check(v.router.purges == [1] && AppNotificationService.shared.purges == [1], "B와 별개인 A의 저장 키 정리")
        }
        do {
            scenarios += 1
            let v = fixture(), gate = Gate(); APIClient.shared.send = { try await gate.wait() }
            let task = Task { await v.deleteAccount() }; await until { gate.waiting }
            // 중간 clear 없이 새 로그인이 설치된 경우도 단순 A 만료로 오인하지 않는다.
            v.authSession.login(userId: 2, token: "session-B")
            v.authSession.expire()
            gate.finish(.success(())); await task.value
            checkNoCleanup(v, "직접 교체 로그인 후 종료")
        }
        do {
            scenarios += 1
            let v = fixture(), gate = Gate(); APIClient.shared.send = { try await gate.wait() }
            let task = Task { await v.deleteAccount() }; await until { gate.waiting }
            v.authSession.expire()
            // 같은 전역 토큰 저장소를 쓰는 다른 AuthSession에서도 로그인 이력을 지킨다.
            let other = AuthSession()
            other.login(userId: 2, token: "other-session-B")
            other.expire()
            v.userProfile.name = "다른 세션의 B 프로필"
            CalendarService.mappings = "다른 세션의 B 연결"
            gate.finish(.success(())); await task.value
            checkNoCleanup(v, "다른 AuthSession 로그인 후 종료")
            check(v.userProfile.name == "다른 세션의 B 프로필" && CalendarService.mappings == "다른 세션의 B 연결", "AuthSession 인스턴스가 달라도 B 보존")
        }
        for change in ["duplicate-expiry", "login-in-progress", "expired-other-api", "pending-expiry-observer", "replacement-expiry-observer"] {
            scenarios += 1
            let v = fixture(), gate = Gate(); APIClient.shared.send = { try await gate.wait() }
            let task = Task { await v.deleteAccount() }; await until { gate.waiting }
            if change == "pending-expiry-observer" || change == "replacement-expiry-observer" {
                if change == "replacement-expiry-observer" { v.authSession.login(userId: 1, token: "new-session-A") }
                AuthTokenStore.clear()
            } else { v.authSession.expire() }
            if change == "duplicate-expiry" { v.authSession.expire() }
            if change == "login-in-progress" { v.authSession.isLoading = true }
            if change == "expired-other-api" { APIEnvironment.apiBaseURL = URL(string: "https://api-b.example/api")! }
            gate.finish(.success(())); await task.value
            if change == "expired-other-api" { checkNoCleanup(v, change); check(v.router.purges.isEmpty, "다른 API의 같은 ID 키를 추측 삭제하지 않음") }
            else if change == "replacement-expiry-observer" { checkNoCleanup(v, change) }
            else { checkExpiredCleanup(v, change, expectedUser: change == "pending-expiry-observer" ? 1 : nil) }
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

generation = [line for line in auth.splitlines()
              if line.strip().startswith(('private static var loginGeneration:', 'var sessionGeneration:'))]
assert len(generation) == 2, '실제 AuthSession 로그인 세대 저장소/접근자를 찾는다'
boundaries = boundaries.replace('// ACTUAL_AUTH_GENERATION', '\n'.join(generation))
boundaries = boundaries.replace('// ACTUAL_AUTH_ACTIONS', '\n'.join([
    declaration(auth, '    private func applyLoginResponse('),
    declaration(auth, '    private func clearLocalSession()'),
]))

with tempfile.TemporaryDirectory(prefix='account-deletion-state-') as tmp:
    path = Path(tmp)
    swift = path / 'Regression.swift'
    swift.write_text(boundaries + action + tests)
    executable = path / 'regression'
    subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', str(path / 'module-cache'),
                    str(swift), '-o', str(executable)], check=True, timeout=120)
    subprocess.run([str(executable)], check=True, timeout=40)
