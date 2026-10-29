import SwiftUI

struct OwnerReservationCalendarView: View {
    @Binding var selectedDate: Date
    let reservations: [PendingReservation]
    @State private var showsMonth = false
    private let calendar = OwnerReservationCalendar.self

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Button { selectedDate = calendar.addingDays(-7, to: selectedDate) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("이전 주")
                Button { showsMonth = true } label: {
                    HStack(spacing: 6) {
                        Text(calendar.label(selectedDate, format: "yyyy년 M월"))
                        Image(systemName: "calendar")
                    }
                    .font(.system(size: 15, weight: .semibold)).frame(minHeight: 44)
                }
                .accessibilityLabel("월 달력 열기, \(calendar.label(selectedDate, format: "yyyy년 M월"))")
                Spacer(minLength: 0)
                Button("오늘") { selectedDate = calendar.today() }
                    .font(.system(size: 13, weight: .semibold)).frame(minWidth: 44, minHeight: 44)
                Button { selectedDate = calendar.addingDays(7, to: selectedDate) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("다음 주")
            }
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(calendar.week(containing: selectedDate), id: \.self) { date in
                            dayButton(date)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: max(308, geometry.size.width))
                }
            }
            .frame(height: 76)
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .sheet(isPresented: $showsMonth) {
            OwnerReservationMonthSheet(selectedDate: $selectedDate, reservations: reservations)
        }
    }

    private func dayButton(_ date: Date) -> some View {
        let count = calendar.reservations(reservations, on: date).count
        let selected = date == selectedDate
        return Button { selectedDate = date } label: {
            VStack(spacing: 4) {
                Text(calendar.label(date, format: "E")).font(.system(size: 11))
                Text(calendar.label(date, format: "d")).font(.system(size: 16, weight: .bold))
                Text(count == 0 ? "—" : "\(count)건").font(.system(size: 10))
            }
            .foregroundStyle(selected ? .white : Color.brandBrown)
            .frame(minWidth: 44, minHeight: 72)
            .background(selected ? Color.brandOrange : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(calendar.label(date, format: "M월 d일 EEEE")), 확정 예약 \(count)건")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct OwnerReservationMonthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    let reservations: [PendingReservation]
    @State private var displayedMonth: Date
    private let calendar = OwnerReservationCalendar.self

    init(selectedDate: Binding<Date>, reservations: [PendingReservation]) {
        _selectedDate = selectedDate
        self.reservations = reservations
        _displayedMonth = State(initialValue: selectedDate.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Button { displayedMonth = calendar.addingMonths(-1, to: displayedMonth) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("이전 달")
                    Spacer()
                    Text(calendar.label(displayedMonth, format: "yyyy년 M월")).font(.headline)
                    Spacer()
                    Button { displayedMonth = calendar.addingMonths(1, to: displayedMonth) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("다음 달")
                }
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44), spacing: 0), count: 7), spacing: 4) {
                            ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) { day in
                                Text(day).font(.caption).frame(minHeight: 28)
                            }
                            ForEach(Array(calendar.monthDays(containing: displayedMonth).enumerated()), id: \.offset) { _, date in
                                if let date { monthDay(date) }
                                else { Color.clear.frame(height: 52).accessibilityHidden(true) }
                            }
                        }
                        .frame(width: max(308, geometry.size.width))
                    }
                }
                Text("날짜 아래 숫자는 해당 이용일의 확정 예약 수예요.")
                    .font(.caption).foregroundStyle(Color.brandBrownMid)
                Spacer(minLength: 0)
            }
            .padding(16)
            .foregroundStyle(Color.brandBrown)
            .background(Color.brandCream.ignoresSafeArea())
            .navigationTitle("이용일 선택").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.frame(minHeight: 44) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func monthDay(_ date: Date) -> some View {
        let count = calendar.reservations(reservations, on: date).count
        let selected = date == selectedDate
        return Button { selectedDate = date; dismiss() } label: {
            VStack(spacing: 4) {
                Text(calendar.label(date, format: "d")).font(.system(size: 15, weight: .semibold))
                Text(count == 0 ? " " : "\(count)건").font(.system(size: 10))
            }
            .foregroundStyle(selected ? .white : Color.brandBrown)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selected ? Color.brandOrange : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(calendar.label(date, format: "yyyy년 M월 d일 EEEE")), 확정 예약 \(count)건")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
