import SwiftUI

// 보호자들이 인증한 펫 태그 묶음 (가로 래핑)
struct FlowTags: View {
    let tags: [String]
    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { t in
                    Text(t)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "#2c6b4a"))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.brandGreenLight)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct ReviewWriteSheet: View {
    let storeName: String
    let onSubmit: (ReviewDraft) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ReviewDraft()
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 별점
                    VStack(alignment: .leading, spacing: 8) {
                        Text("별점").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.brandBrown)
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: i <= draft.rating ? "star.fill" : "star")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Color.brandOrange)
                                    .onTapGesture { draft.rating = i }
                            }
                        }
                    }

                    // 펫 특화 체크박스
                    VStack(alignment: .leading, spacing: 8) {
                        Text("우리 아이 기준 체크 🐾")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.brandBrown)
                        Text("다음 보호자에게 그대로 필터가 됩니다")
                            .font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
                        checkRow("📹 CCTV 실시간 확인됐어요", $draft.cctv)
                        checkRow("🚗 픽업/드랍 가능했어요", $draft.pickup)
                        checkRow("🐕 대형견도 받아줬어요", $draft.largeDog)
                        checkRow("💛 분리불안 케어 잘해줬어요", $draft.separationCare)
                        checkRow("🔁 또 맡기고 싶어요 (재방문)", $draft.revisit)
                    }

                    // 자유 텍스트
                    VStack(alignment: .leading, spacing: 8) {
                        Text("우리 아이는 어땠나요?")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.brandBrown)
                        TextEditor(text: $draft.content)
                            .font(.system(size: 13))
                            .frame(height: 100)
                            .padding(10)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
                    }

                    Button(action: submit) {
                        Text(submitting ? "올리는 중…" : "리뷰 등록")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Color.brandOrange)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                    }
                    .disabled(submitting)
                }
                .padding(20)
            }
            .background(Color.brandCream)
            .navigationTitle("\(storeName) 리뷰")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Color.brandBrown)
                    }
                }
            }
        }
    }

    private func checkRow(_ label: String, _ flag: Binding<Bool>) -> some View {
        Button(action: { flag.wrappedValue.toggle() }) {
            HStack {
                Image(systemName: flag.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(flag.wrappedValue ? Color.brandOrange : Color.brandBrownLight)
                Text(label).font(.system(size: 13)).foregroundStyle(Color.brandBrown)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private func submit() {
        submitting = true
        Task {
            let ok = await onSubmit(draft)
            await MainActor.run {
                submitting = false
                if ok { dismiss() }
            }
        }
    }
}
