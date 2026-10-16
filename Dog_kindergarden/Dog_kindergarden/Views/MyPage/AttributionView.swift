import SwiftUI

struct AttributionView: View {
    @Environment(AppRouter.self) private var router

    private let credits: [IconCredit] = [
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
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                navBar

                Text("맡겨멍에서 사용하는 일부 아이콘은 Flaticon 제작자의 저작물입니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBrownMid)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    ForEach(credits) { credit in
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
                                    Text("제작자: \(credit.creator) · Flaticon")
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

                        if credit.id != credits.last?.id {
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

private struct IconCredit: Identifiable {
    let assetName: String
    let title: String
    let creator: String
    let sourceURL: String

    var id: String { assetName }
    var url: URL { URL(string: sourceURL)! }
}
