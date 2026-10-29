import SwiftUI

struct BookingDoneView: View {
    @Environment(AppRouter.self) private var router
    @State private var calendarState: CalendarAddState = .idle
    @State private var showCalendarDeniedAlert = false

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
                    .padding(.top, 96)

                Text("예약 신청이 완료됐어요!")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                    .padding(.top, 28)

                Text("\(booking?.storeName ?? "가게")에서 예약을 확인하고\n곧 연락드릴게요")
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
        .task {
            if let reservationId = booking?.reservationId,
               CalendarService.hasReservationEvent(reservationId: reservationId) {
                calendarState = .saved
            }
        }
        .alert("캘린더 권한이 꺼져 있어요", isPresented: $showCalendarDeniedAlert) {
            Button("설정에서 허용") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("나중에", role: .cancel) {}
        } message: {
            Text("예약은 정상적으로 접수됐어요. 설정에서 캘린더 접근을 허용한 뒤 다시 추가할 수 있어요.")
        }
    }

    // MARK: - Success icon

    private var successIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#FFE6CC"))
                    .frame(width: 128, height: 128)
                    .shadow(color: Color.brandOrange.opacity(0.4), radius: 20, x: 0, y: 20)
                if booking?.dogImageURL != nil {
                    AuthenticatedPetImage(value: booking?.dogImageURL)
                        .frame(width: 128, height: 128)
                        .clipShape(Circle())
                } else {
                    EmojiIcon(emoji: "🐶", size: 64)
                }
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
            summaryRow("가격 안내", booking?.price ?? "-")
        }
        .padding(20)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
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
            Button(action: addToCalendar) {
                HStack(spacing: 7) {
                    if calendarState == .saving {
                        ProgressView().tint(Color.brandOrange)
                    } else {
                        Image(systemName: calendarState == .saved ? "checkmark.circle.fill" : "calendar.badge.plus")
                    }
                    Text(calendarState == .saved ? "캘린더에 추가됨" : "캘린더에 추가")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(calendarState == .saved ? Color.brandGreen : Color.brandOrange)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
            }
            .disabled(calendarState == .saving || calendarState == .saved || booking == nil)

            if calendarState == .failed {
                Text("일정을 추가하지 못했어요. 잠시 후 다시 시도해주세요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else if calendarState != .saved {
                Text("버튼을 누를 때만 캘린더 접근을 요청해요.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brandBrownMid)
            }

            Button(action: {
                if let b = booking {
                    router.selectedChat = b.storeName
                    router.selectedRoomId = b.roomId
                }
                router.chatRoomAsOwner = false
                router.chatRoomAvatar = storeTypeEmoji(router.selectedPin?.type)
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

    private func addToCalendar() {
        guard let booking,
              let date = CalendarService.parseSchedule(booking.schedule),
              calendarState != .saving else {
            calendarState = .failed
            return
        }
        calendarState = .saving
        Task {
            let saved = await CalendarService.addReservationEvent(
                reservationId: booking.reservationId,
                title: "\(booking.storeName) 예약 신청",
                notes: booking.dogName.isEmpty ? nil : "\(booking.dogName) 맡김",
                date: date,
                isAllDay: booking.isAllDay,
                durationHours: booking.durationHours
            )
            if saved {
                calendarState = .saved
            } else {
                calendarState = .failed
                if CalendarService.isAccessDenied { showCalendarDeniedAlert = true }
            }
        }
    }
}

private enum CalendarAddState: Equatable {
    case idle
    case saving
    case saved
    case failed
}
