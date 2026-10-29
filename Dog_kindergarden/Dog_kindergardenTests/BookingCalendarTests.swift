import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("예약 달력 선택과 탐색 분리")
@MainActor
struct BookingCalendarTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-27T15:10:00Z")!
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        BookingCalendarState.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("첫 선택은 한국 기준 오늘 자정이고 오늘은 현재 시각보다 이르더라도 선택 가능")
    func todayAndPast() {
        var state = BookingCalendarState(selection: now, now: now)
        #expect(state.selectedDate == day(2026, 10, 28))
        #expect(state.canSelect(DateComponents(year: 2026, month: 10, day: 28), now: now))
        #expect(!state.canSelect(DateComponents(year: 2026, month: 10, day: 27), now: now))
        let selectedPast = state.select(DateComponents(year: 2026, month: 10, day: 27), now: now)
        #expect(!selectedPast)
        #expect(state.selectedDate == day(2026, 10, 28))
        #expect(!state.canSelect(nil, now: now))
    }

    @Test("월·연도 헤더와 이전/다음 월 탐색은 실제 선택일을 이동시키지 않는다")
    func browsingKeepsSelectedDay() {
        var state = BookingCalendarState(selection: day(2026, 10, 31), now: now)
        for components in [DateComponents(year: 2026, month: 11), DateComponents(year: 2027, month: 2), DateComponents(year: 2026, month: 10), DateComponents(year: 2028, month: 2)] {
            state.browse(components)
            #expect(state.selectedDate == day(2026, 10, 31))
            #expect(state.visibleMonth.year == components.year)
            #expect(state.visibleMonth.month == components.month)
            #expect(state.visibleMonth.day == nil)
        }
    }

    @Test("직접 누른 다른 달 날짜만 선택하며 월말을 작은 달 28일로 강제 보정하지 않는다")
    func directDaySelection() {
        var state = BookingCalendarState(selection: day(2026, 10, 31), now: now)
        state.browse(DateComponents(year: 2027, month: 2))
        #expect(state.selectedDate == day(2026, 10, 31))
        let selectedDay = state.select(DateComponents(year: 2027, month: 2, day: 12), now: now)
        #expect(selectedDay)
        #expect(state.selectedDate == day(2027, 2, 12))
        #expect(state.visibleMonth.month == 2)
        let selectedMonth = state.select(DateComponents(year: 2027, month: 2), now: now)
        #expect(!selectedMonth)
        #expect(state.selectedDate == day(2027, 2, 12))
    }

    @Test("윤년·잘못된 날짜를 검증하고 외부 바인딩 변경만 선택과 표시 월을 함께 갱신한다")
    func leapYearAndExternalBinding() {
        var state = BookingCalendarState(selection: now, now: now)
        #expect(!state.canSelect(DateComponents(year: 2027, month: 2, day: 29), now: now))
        let selectedLeapDay = state.select(DateComponents(year: 2028, month: 2, day: 29), now: now)
        #expect(selectedLeapDay)
        #expect(state.selectedDate == day(2028, 2, 29))
        state.synchronize(selection: day(2027, 1, 5), now: now)
        #expect(state.selectedDate == day(2027, 1, 5))
        #expect(state.visibleMonth == DateComponents(year: 2027, month: 1))
        state.synchronize(selection: day(2020, 1, 1), now: now)
        #expect(state.selectedDate == day(2026, 10, 28))
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

@Suite("예약 UIKit 달력 실제 델리게이트")
@MainActor
struct BookingCalendarDelegateTests {

    private func day(_ day: Int) -> Date {
        BookingCalendarState.calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    private func drainNormalization() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("과거 초기 바인딩은 다음 메인 실행에서 오늘로 정규화하고 탐색 월은 유지한다")
    func pastBindingIsNormalizedWithoutResettingBrowse() async {
        var selected = day(27)
        let parent = BookingCalendar(selection: Binding(get: { selected }, set: { selected = $0 }))
        let coordinator = BookingCalendar.Coordinator(parent: parent, now: { day(28) })
        let view = parent.makeCalendarView(coordinator: coordinator)
        let behavior = view.selectionBehavior as! UICalendarSelectionSingleDate
        #expect(selected == day(27)) // UIViewRepresentable update 중에는 바인딩을 쓰지 않는다.
        #expect(coordinator.state.selectedDate == day(28))
        #expect(BookingCalendarState.calendar.date(from: behavior.selectedDate!) == day(28))
        view.setVisibleDateComponents(DateComponents(year: 2027, month: 2), animated: false)
        coordinator.calendarView(view, didChangeVisibleDateComponentsFrom: DateComponents(year: 2026, month: 10))
        await drainNormalization()
        #expect(selected == day(28))
        coordinator.synchronizeSelection(in: view)
        #expect(view.visibleDateComponents.month == 2)
        #expect(coordinator.state.visibleMonth == DateComponents(year: 2027, month: 2))
    }

    @Test("자정 후 같은 바인딩이라도 어제 선택을 오늘로 정규화한다")
    func midnightRolloverNormalizesAllThreeSelections() async {
        var now = day(28).addingTimeInterval(23 * 3600 + 59 * 60)
        var selected = day(28)
        let parent = BookingCalendar(selection: Binding(get: { selected }, set: { selected = $0 }))
        let coordinator = BookingCalendar.Coordinator(parent: parent, now: { now })
        let view = parent.makeCalendarView(coordinator: coordinator)
        now = day(29)
        coordinator.synchronizeSelection(in: view)
        #expect(selected == day(28))
        #expect(coordinator.state.selectedDate == day(29))
        await drainNormalization()
        #expect(selected == day(29))
        let behavior = view.selectionBehavior as! UICalendarSelectionSingleDate
        #expect(BookingCalendarState.calendar.date(from: behavior.selectedDate!) == selected)
        #expect(!coordinator.dateSelection(behavior, canSelectDate: DateComponents(year: 2026, month: 10, day: 28)))
    }

    @Test("예약된 과거 값 정규화는 이후 사용자 선택 또는 외부 바인딩을 덮어쓰지 않는다")
    func deferredNormalizationCannotOverwriteNewSelection() async {
        var selected = day(27)
        let parent = BookingCalendar(selection: Binding(get: { selected }, set: { selected = $0 }))
        let coordinator = BookingCalendar.Coordinator(parent: parent, now: { day(28) })
        let view = parent.makeCalendarView(coordinator: coordinator)
        let behavior = view.selectionBehavior as! UICalendarSelectionSingleDate
        let future = DateComponents(year: 2026, month: 10, day: 31)
        behavior.setSelected(future, animated: false)
        coordinator.dateSelection(behavior, didSelectDate: future)
        await drainNormalization()
        #expect(selected == day(31))
        #expect(coordinator.state.selectedDate == selected)
        #expect(BookingCalendarState.calendar.date(from: behavior.selectedDate!) == selected)
        selected = day(27)
        coordinator.synchronizeSelection(in: view)
        selected = day(30)
        await drainNormalization()
        #expect(selected == day(30))
        coordinator.synchronizeSelection(in: view)
        #expect(coordinator.state.selectedDate == selected)
        #expect(BookingCalendarState.calendar.date(from: behavior.selectedDate!) == selected)
    }

    @Test("작은 화면 너비에서도 네이티브 달력의 높이를 자동 확보한다")
    func nativeCalendarUsesFittingHeight() {
        for width in [CGFloat(248), CGFloat(272), CGFloat(350)] {
            let calendar = BookingCalendar(selection: .constant(Date()))
            let host = UIHostingController(rootView: calendar.frame(width: width))
            let size = host.sizeThatFits(in: CGSize(width: width, height: 1000))
            #expect(abs(size.width - width) < 1)
            #expect(size.height > 200)
            #expect(size.height < 700)
        }
    }
    @Test("탐색 콜백은 바인딩 불변, 일자 콜백과 외부 변경만 선택 표시를 이동")
    func nativeDelegatesAndExternalBinding() {
        let calendar = BookingCalendarState.calendar
        let today = calendar.startOfDay(for: Date())
        var selected = today
        var didSelect = 0
        let parent = BookingCalendar(selection: Binding(get: { selected }, set: { selected = $0 })) { didSelect += 1 }
        let coordinator = parent.makeCoordinator()
        let view = parent.makeCalendarView(coordinator: coordinator)
        let behavior = view.selectionBehavior as! UICalendarSelectionSingleDate
        #expect(view.tintColor == .black)
        #expect(calendar.date(from: behavior.selectedDate!) == today)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: today)!
        let previousMonth = view.visibleDateComponents
        view.setVisibleDateComponents(calendar.dateComponents([.year, .month], from: nextMonth), animated: false)
        coordinator.calendarView(view, didChangeVisibleDateComponentsFrom: previousMonth)
        #expect(selected == today)
        #expect(calendar.date(from: behavior.selectedDate!) == today)
        #expect(didSelect == 0)
        coordinator.synchronizeSelection(in: view)
        #expect(view.visibleDateComponents.month == calendar.component(.month, from: nextMonth))
        #expect(selected == today)
        let target = calendar.dateComponents([.year, .month, .day], from: nextMonth)
        #expect(coordinator.dateSelection(behavior, canSelectDate: target))
        behavior.setSelected(target, animated: false)
        coordinator.dateSelection(behavior, didSelectDate: target)
        #expect(selected == calendar.startOfDay(for: nextMonth))
        #expect(calendar.date(from: behavior.selectedDate!) == selected)
        #expect(didSelect == 1)
        let external = calendar.date(byAdding: .month, value: 3, to: nextMonth)!
        selected = external
        coordinator.synchronizeSelection(in: view)
        #expect(calendar.date(from: behavior.selectedDate!) == external)
        #expect(view.visibleDateComponents.month == calendar.component(.month, from: external))
        #expect(didSelect == 1)
        let past = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: -1, to: today)!)
        #expect(!coordinator.dateSelection(behavior, canSelectDate: past))
        coordinator.dateSelection(behavior, didSelectDate: past)
        #expect(selected == external)
        coordinator.dateSelection(behavior, didSelectDate: nil)
        #expect(selected == external)
    }
}
#endif
