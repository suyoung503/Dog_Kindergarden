import SwiftUI

// 강아지 아바타 — 프로필 미설정 시 돌아가며 사용 (dog_a는 화질 문제로 제외)
let dogAvatars = ["dog_b", "dog_c"]

/// 인덱스 기반으로 강아지 아바타를 순환 선택
func dogAvatarName(_ index: Int) -> String {
    dogAvatars[((index % dogAvatars.count) + dogAvatars.count) % dogAvatars.count]
}

// 이모지 문자열 → 에셋 이미지 이름 매핑 (PNG가 있는 것만)
extension String {
    var petAssetName: String? {
        switch self {
        case "🐶": return "dog_b"          // 기본 강아지
        case "🐕": return "dog_c"          // 강아지(다른 종)
        case "🦴": return "emoji_bone"
        case "🏠": return "kindergarden"    // house → 유치원 아이콘
        case "🏨": return "emoji_hotel"     // 호텔
        case "✂️", "✂": return "emoji_scissors"
        case "🐾": return "icon_paw"        // 발바닥
        default: return nil
        }
    }
}

/// 이모지를 그린다. 대응 PNG가 있으면 이미지로, 없으면 이모지 텍스트로 폴백.
struct EmojiIcon: View {
    let emoji: String
    var size: CGFloat = 20

    var body: some View {
        if emoji.hasPrefix("sf:") {
            // SF Symbol ("sf:message.fill" 형태)
            Image(systemName: String(emoji.dropFirst(3)))
                .font(.system(size: size * 0.9))
        } else if emoji.hasPrefix("img:") {
            // 에셋 이미지 직접 지정 ("img:dog_c" 형태)
            Image(String(emoji.dropFirst(4)))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else if let name = emoji.petAssetName {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(emoji)
                .font(.system(size: size))
        }
    }
}

/// 섹션 제목 등 "이모지 + 텍스트" 문자열. 맨 앞 이모지가 PNG면 이미지로 교체.
struct EmojiTitle: View {
    let title: String
    var size: CGFloat = 14
    var weight: Font.Weight = .bold
    var color: Color = Color.brandBrown

    var body: some View {
        if let first = title.first, let asset = String(first).petAssetName {
            HStack(spacing: 5) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size + 3, height: size + 3)
                Text(String(title.dropFirst()).trimmingCharacters(in: .whitespaces))
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(color)
            }
        } else {
            Text(title)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
        }
    }
}
