import Foundation

// 달력 탐색과 예약일 선택은 서로 다른 상태다. 한국 날짜의 자정부터 오늘을 허용한다.
struct BookingCalendarState {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private(set) var selectedDate: Date
    private(set) var visibleMonth: DateComponents

    init(selection: Date, now: Date = Date()) {
        selectedDate = max(Self.calendar.startOfDay(for: selection), Self.calendar.startOfDay(for: now))
        visibleMonth = Self.calendar.dateComponents([.year, .month], from: selectedDate)
    }

    mutating func browse(_ month: DateComponents) {
        visibleMonth = DateComponents(year: month.year, month: month.month)
    }

    func canSelect(_ components: DateComponents?, now: Date = Date()) -> Bool {
        guard let components, let year = components.year, let month = components.month, let day = components.day,
              let date = Self.calendar.date(from: DateComponents(year: year, month: month, day: day)),
              Self.calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: year, month: month, day: day)
        else { return false }
        return date >= Self.calendar.startOfDay(for: now)
    }

    @discardableResult
    mutating func select(_ components: DateComponents?, now: Date = Date()) -> Bool {
        guard canSelect(components, now: now), let components,
              let date = Self.calendar.date(from: DateComponents(year: components.year, month: components.month, day: components.day))
        else { return false }
        selectedDate = date
        visibleMonth = Self.calendar.dateComponents([.year, .month], from: date)
        return true
    }

    mutating func synchronize(selection: Date, now: Date = Date()) {
        self = Self(selection: selection, now: now)
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

struct BookingCalendar: UIViewRepresentable {
    @Binding var selection: Date
    var onSelect: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UICalendarView {
        makeCalendarView(coordinator: context.coordinator)
    }

    func makeCalendarView(coordinator: Coordinator) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.calendar = BookingCalendarState.calendar
        calendarView.timeZone = BookingCalendarState.calendar.timeZone
        calendarView.locale = Locale(identifier: "ko_KR")
        calendarView.tintColor = .black
        calendarView.delegate = coordinator
        let behavior = UICalendarSelectionSingleDate(delegate: coordinator)
        calendarView.selectionBehavior = behavior
        calendarView.setVisibleDateComponents(coordinator.state.visibleMonth, animated: false)
        behavior.setSelected(BookingCalendarState.calendar.dateComponents([.year, .month, .day], from: coordinator.state.selectedDate), animated: false)
        calendarView.setContentCompressionResistancePriority(.required, for: .vertical)
        coordinator.synchronizeSelection(in: calendarView)
        return calendarView
    }

    func updateUIView(_ calendarView: UICalendarView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronizeSelection(in: calendarView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        uiView.systemLayoutSizeFitting(
            CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: BookingCalendar
        private(set) var state: BookingCalendarState
        private let now: () -> Date

        init(parent: BookingCalendar, now: @escaping () -> Date = Date.init) {
            self.parent = parent
            self.now = now
            state = BookingCalendarState(selection: parent.selection, now: now())
        }

        func synchronizeSelection(in calendarView: UICalendarView) {
            let input = parent.selection
            let normalized = BookingCalendarState(selection: input, now: now())
            apply(normalized, to: calendarView)
            guard input != normalized.selectedDate else { return }
            // UIKit update 중 SwiftUI 바인딩을 쓰지 않는다. 이후 사용자가 고른 값도 보존한다.
            Task { @MainActor [weak self, weak calendarView] in
                guard let self, let calendarView, self.parent.selection == input else { return }
                let current = BookingCalendarState(selection: input, now: self.now())
                self.apply(current, to: calendarView)
                self.parent.selection = current.selectedDate
            }
        }

        private func apply(_ normalized: BookingCalendarState, to calendarView: UICalendarView) {
            guard normalized.selectedDate != state.selectedDate else { return }
            state = normalized
            (calendarView.selectionBehavior as? UICalendarSelectionSingleDate)?.setSelected(
                BookingCalendarState.calendar.dateComponents([.year, .month, .day], from: state.selectedDate), animated: false)
            calendarView.setVisibleDateComponents(state.visibleMonth, animated: false)
        }

        func calendarView(_ calendarView: UICalendarView, didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents) {
            state.browse(calendarView.visibleDateComponents)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool {
            state.canSelect(dateComponents, now: now())
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard state.select(dateComponents, now: now()) else {
                selection.setSelected(BookingCalendarState.calendar.dateComponents([.year, .month, .day], from: state.selectedDate), animated: false)
                return
            }
            parent.selection = state.selectedDate
            parent.onSelect()
        }
    }
}
#endif
