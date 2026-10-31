import Foundation
import Testing
@testable import Dog_kindergarden

// 같은 Keychain과 standard defaults를 쓰는 모든 인증 fixture를 함께 직렬화한다.
@Suite("Shared authentication state", .serialized)
struct AuthStateTests {}

extension AuthStateTests {
@Suite("Optional profile email", .serialized)
@MainActor
struct ProfileEmailTests {
    @Test("Blank optional email is allowed and surrounding whitespace is trimmed")
    func normalization() throws {
        #expect(try UserProfile.normalizedEmail("") == "")
        #expect(try UserProfile.normalizedEmail(" \n\t") == "")
        #expect(try UserProfile.normalizedEmail("  owner+profile@Example.co.kr  ") == "owner+profile@Example.co.kr")
    }

    @Test("Invalid email format, internal whitespace, and excessive length are rejected")
    func invalidEmail() {
        for email in ["bad", "a@b", "a b@example.com", "a\n@example.com", "a@@example.com", "@example.com", "a@example.", String(repeating: "a", count: 243) + "@example.com"] {
            #expect(throws: UserProfile.EmailValidationError.invalidFormat) {
                try UserProfile.normalizedEmail(email)
            }
        }
    }

    @Test("Server nil replaces another account's cached email")
    func serverEmailReplacement() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "profile_email")
        defer { defaults.set(previous, forKey: "profile_email") }
        let profile = UserProfile()
        profile.email = "previous@example.com"
        #expect(UserProfile().email == "previous@example.com")
        profile.applyServerEmail(nil)
        #expect(profile.email == "")
        #expect(UserProfile().email == "")
        profile.applyServerEmail("current@example.com")
        #expect(UserProfile().email == "current@example.com")
    }

    @Test("Email is included in update requests, including an explicit blank deletion")
    func requestEncoding() throws {
        for email in ["owner@example.com", ""] {
            let body = UserUpdateRequest(nickname: "보호자", phone: "", address: "", email: email)
            let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: String])
            #expect(json["email"] == email)
        }
    }

    @Test("Email update response decodes a string, null, or an absent optional field")
    func responseDecoding() throws {
        for (json, expected) in [(#"{"email":"owner@example.com"}"#, "owner@example.com" as String?), (#"{"email":null}"#, nil), ("{}", nil)] {
            let response = try JSONDecoder().decode(UserResponse.self, from: Data(json.utf8))
            #expect(response.email == expected)
        }
    }

    @Test("Account deletion removes cached email")
    func deletionClearsEmail() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "profile_email")
        defer { defaults.set(previous, forKey: "profile_email") }
        defaults.set("other@example.com", forKey: "profile_email")
        UserProfile().clearAfterAccountDeletion()
        #expect(defaults.object(forKey: "profile_email") == nil)
    }
}
}
