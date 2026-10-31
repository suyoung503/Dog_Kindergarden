import SwiftUI

struct AttributionView: View {
    @Environment(AppRouter.self) private var router

    static let credits: [IconCredit] = [
        IconCredit(
            assetName: "icon_paw",
            title: "강아지 발자국 아이콘",
            creator: "DinosoftLabs",
            sourceURL: "https://www.flaticon.com/authors/dinosoftlabs"
        ),
        IconCredit(
            assetName: "dog_c",
            title: "푸들 아이콘",
            creator: "Iconfromus",
            sourceURL: "https://www.flaticon.com/authors/iconfromus"
        ),
        IconCredit(
            assetName: "dog_b",
            title: "비숑 프리제 아이콘",
            creator: "Iconfromus",
            sourceURL: "https://www.flaticon.com/authors/iconfromus"
        ),
        IconCredit(
            assetName: "kindergarden",
            title: "유치원 아이콘",
            creator: "RIkas Dzihab",
            sourceURL: "https://www.flaticon.com/authors/rikas-dzihab"
        ),
        IconCredit(
            assetName: "emoji_chat",
            title: "채팅 아이콘",
            creator: "Catalin Fertu",
            sourceURL: "https://www.flaticon.com/free-icon/chat-oval-speech-bubbles-symbol_55009"
        ),
        IconCredit(
            assetName: "emoji_calendar",
            title: "달력 아이콘",
            creator: "photo3idea_studio",
            sourceURL: "https://www.flaticon.com/authors/photo3idea-studio"
        ),
        IconCredit(
            assetName: "emoji_note",
            title: "메모 아이콘",
            creator: "Magnific",
            sourceURL: "https://www.flaticon.com/authors/magnific"
        ),
        IconCredit(
            assetName: "emoji_hotel",
            title: "호텔 아이콘",
            creator: "Google LLC",
            sourceURL: "https://github.com/googlefonts/noto-emoji/blob/9481ce20ef21f0c658344417901228e73aaf3480/png/512/emoji_u1f3e8.png",
            provider: "Noto Emoji"
        ),
        IconCredit(
            assetName: "emoji_bone",
            title: "뼈다귀 아이콘",
            creator: "Google LLC",
            sourceURL: "https://github.com/googlefonts/noto-emoji/blob/f3ae03f5e9b3b8516fa151f7168159ca1a3e7515/png/32/emoji_u1f9b4.png",
            provider: "Noto Emoji"
        )
    ]

    static let notoNotices: String? = {
        guard let url = Bundle.main.url(forResource: "NotoEmojiNotices", withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                navBar

                Text("맡겨멍은 Flaticon 제작자의 아이콘과 Google Noto Emoji 이미지를 사용합니다. 각 항목을 누르면 원본 출처를 확인할 수 있어요.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBrownMid)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    ForEach(Self.credits) { credit in
                        Link(destination: credit.url) {
                            HStack(spacing: 13) {
                                Image(credit.assetName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 34, height: 34)
                                    .padding(5)
                                    .background(Color.brandCream)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(credit.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.brandBrown)
                                    Text("제작자: \(credit.creator) · \(credit.provider)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.brandBrownMid)
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.brandBrownLight)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if credit.id != Self.credits.last?.id {
                            Divider()
                                .foregroundStyle(Color(hex: "#F1E2CB"))
                                .padding(.leading, 65)
                        }
                    }
                }
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .stroke(Color.brandBeigeBorder, lineWidth: 1)
                )
                .padding(.horizontal, 20)

                Link(destination: URL(string: "https://www.flaticon.com/license/license.pdf")!) {
                    Label("Flaticon 라이선스 확인", systemImage: "doc.text")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.brandBrownMid)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Google Noto Emoji")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Copyright 2013 Google LLC.\n호텔·뼈다귀 PNG는 원본 그대로 사용합니다. 이미지의 사용 버전에 포함된 저작권·라이선스 고지를 함께 제공합니다.")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)

                    Link("호텔 버전 라이선스 (Apache 2.0)", destination: URL(string: "https://github.com/googlefonts/noto-emoji/blob/9481ce20ef21f0c658344417901228e73aaf3480/LICENSE")!)
                    Link("뼈다귀 버전 저장소 라이선스 (OFL 1.1)", destination: URL(string: "https://github.com/googlefonts/noto-emoji/blob/f3ae03f5e9b3b8516fa151f7168159ca1a3e7515/LICENSE")!)

                    DisclosureGroup("저작권·라이선스 전문 (오프라인)") {
                        Text(verbatim: Self.notoNotices ?? "라이선스 파일을 읽지 못했어요. 위 원본 라이선스 링크에서 확인해 주세요.")
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrownMid)
                .padding(16)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .background(Color.brandCream.ignoresSafeArea())
    }

    private var navBar: some View {
        HStack(spacing: 12) {
            Button(action: router.back) {
                Circle()
                    .fill(.white)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.brandBeigeBorder, lineWidth: 1))
                    .overlay(
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.brandBrown)
                    )
            }

            Text("오픈소스·아이콘 출처")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
    }
}

struct IconCredit: Identifiable {
    let assetName: String
    let title: String
    let creator: String
    let sourceURL: String
    var provider: String = "Flaticon"

    var id: String { assetName }
    var url: URL { URL(string: sourceURL)! }
}
