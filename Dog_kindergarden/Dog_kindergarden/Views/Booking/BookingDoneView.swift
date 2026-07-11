import SwiftUI

struct BookingDoneView: View {
    @Environment(AppRouter.self) private var router

    private var booking: BookingResult? { router.lastBooking }

    private var dogText: String {
        guard let b = booking, !b.dogName.isEmpty else { return "-" }
        let breed = b.dogBreed.isEmpty ? "" : " (\(b.dogBreed))"
        return b.dogName + breed
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                successIcon
                    .padding(.top, 60)

                Text("예약 신청이 완료됐어요!")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                    .padding(.top, 28)

                Text("\(booking?.storeName ?? "가게")에서 예약을 확인하고\n곧 연락드릴게요 🐾")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBrownMid)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 8)

                summaryCard
                    .padding(.top, 24)

                actionButtons
                    .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "#FFF1DC"), Color.brandCream],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - Success icon

    private var successIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#FFE6CC"))
                    .frame(width: 128, height: 128)
                    .shadow(color: Color.brandOrange.opacity(0.4), radius: 20, x: 0, y: 20)
                EmojiIcon(emoji: "🐶", size: 64)
            }
            ZStack {
                Circle()
                    .fill(Color.brandGreen)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(Color.brandCream, lineWidth: 4))
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .offset(x: 8, y: 8)
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(spacing: 0) {
            summaryRow("가게",    booking?.storeName ?? "-")
            dashedDivider
            summaryRow("강아지",  dogText)
            dashedDivider
            summaryRow("일정",    booking?.schedule ?? "-")
            dashedDivider
            summaryRow("결제 예정", booking?.price ?? "-")
        }
        .padding(20)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
        .overlay(RoundedRectangle(cornerRadius: Radius.pill).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    private func summaryRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12)).foregroundStyle(Color.brandBrownMid)
            Spacer()
            Text(v).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.brandBrown)
        }
        .padding(.vertical, 6)
    }

    private var dashedDivider: some View {
        Rectangle()
            .fill(Color.brandBeigeBorder)
            .frame(height: 1)
            .overlay(
                GeometryReader { geo in
                    Path { p in
                        p.move(to: .zero)
                        p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    }
                    .stroke(Color.brandBeigeBorder, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                }
            )
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: {
                if let b = booking {
                    router.selectedChat = b.storeName
                    router.selectedRoomId = b.roomId
                }
                router.chatRoomAsOwner = false
                router.go(.chatRoom)
            }) {
                Text("가게와 채팅하기")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
            }
            Button(action: {
                router.stack = [.home]
            }) {
                Text("홈으로 돌아가기")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.brandOrange)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                    .shadow(color: Color.brandOrange.opacity(0.7), radius: 9, x: 0, y: 8)
            }
        }
    }
}
