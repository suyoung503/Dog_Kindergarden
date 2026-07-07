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
    var name: String {
        didSet { UserDefaults.standard.set(name, forKey: "profile_name") }
    }
    var phone: String {
        didSet { UserDefaults.standard.set(phone, forKey: "profile_phone") }
    }
    var address: String {
        didSet { UserDefaults.standard.set(address, forKey: "profile_address") }
    }

    init() {
        name    = UserDefaults.standard.string(forKey: "profile_name")    ?? "보호자"
        phone   = UserDefaults.standard.string(forKey: "profile_phone")   ?? ""
        address = UserDefaults.standard.string(forKey: "profile_address") ?? ""
    }
}
