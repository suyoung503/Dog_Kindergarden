//
//  UserProfile.swift
//  Dog_kindergarden
//
//  Created by su young on 7/3/26.
//

import Foundation
import Observation

@Observable
final class UserProfile {
    private(set) var revision: UInt = 0

    var name: String {
        didSet { revision &+= 1; UserDefaults.standard.set(name, forKey: "profile_name") }
    }
    var phone: String {
        didSet { revision &+= 1; UserDefaults.standard.set(phone, forKey: "profile_phone") }
    }
    var email: String {
        didSet { revision &+= 1; UserDefaults.standard.set(email, forKey: "profile_email") }
    }
    var address: String {
        didSet { revision &+= 1; UserDefaults.standard.set(address, forKey: "profile_address") }
    }

    init() {
        name    = UserDefaults.standard.string(forKey: "profile_name")    ?? "보호자"
        phone   = UserDefaults.standard.string(forKey: "profile_phone")   ?? ""
        email   = UserDefaults.standard.string(forKey: "profile_email")   ?? ""
        address = UserDefaults.standard.string(forKey: "profile_address") ?? ""
    }

    enum EmailValidationError: Error { case invalidFormat }

    // 선택 입력의 기본 형식만 확인하며 메일의 실소유 여부를 인증하지 않는다.
    static func normalizedEmail(_ value: String) throws -> String {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.utf16.count <= 254,
              email.isEmpty || email.range(of: #"^[^\s@]+@[^\s@.]+(?:\.[^\s@.]+)+$"#, options: .regularExpression) != nil else {
            throw EmailValidationError.invalidFormat
        }
        return email
    }

    func applyServerEmail(_ value: String?) {
        email = value ?? ""
    }

    func applyServerProfile(_ user: UserResponse) {
        name = user.nickname ?? ""
        phone = user.phone ?? ""
        address = user.address ?? ""
        applyServerEmail(user.email)
    }

    // 저장 중인 새 프로필을 먼저 시작한 조회 응답이 덮지 않게 한다.
    func invalidatePendingRefresh() {
        revision &+= 1
    }

    func clearAfterAccountDeletion() {
        name = "보호자"
        phone = ""
        email = ""
        address = ""
        UserDefaults.standard.removeObject(forKey: "profile_name")
        UserDefaults.standard.removeObject(forKey: "profile_phone")
        UserDefaults.standard.removeObject(forKey: "profile_email")
        UserDefaults.standard.removeObject(forKey: "profile_address")
    }
}
