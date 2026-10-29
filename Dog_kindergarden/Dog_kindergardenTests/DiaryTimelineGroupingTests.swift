import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("알림장 최초 게시일별 타임라인")
@MainActor
struct DiaryTimelineGroupingTests {
    private func entry(_ id: Int, _ createdAt: String?, content: String = "기록") -> DiaryEntry {
        DiaryEntry(diaryId: id, content: content, createdAt: createdAt, photos: nil)
    }

    @Test("같은 게시일 글은 한 날짜 아래 서버 게시 시각순으로 모인다")
    func sameDay() {
        let groups = DiaryTimelineGrouping.groups([
            entry(2, "2026-12-01 07:00:00"), entry(1, "2026-12-01 00:00:00")
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.title == "2026년 12월 1일")
        #expect(groups.first?.entries.map(\.id) == [1, 2])
        #expect(DiaryTimelineGrouping.timeLabel("2026-12-01 07:00:00") == "오후 4:00")
    }

    @Test("UTC 오후 3시부터 다음 KST 날짜이며 연말에도 같은 기준이다")
    func midnightAndYearBoundary() {
        let groups = DiaryTimelineGrouping.groups([
            entry(4, "2026-12-31 15:00:00"), entry(2, "2026-11-30 15:00:00"),
            entry(1, "2026-11-30 14:59:59"), entry(3, "2026-12-31 14:59:59")
        ])
        #expect(groups.map(\.title) == ["2026년 11월 30일", "2026년 12월 1일", "2026년 12월 31일", "2027년 1월 1일"])
        #expect(groups.flatMap(\.entries).map(\.id) == [1, 2, 3, 4])
        #expect(DiaryTimelineGrouping.timeLabel("2026-11-30 15:00:00") == "오전 12:00")
    }

    @Test("동일 게시 시각은 diary_id 오름차순으로 안정적으로 정렬한다")
    func tieBreak() {
        let groups = DiaryTimelineGrouping.groups([
            entry(9, "2026-12-01 07:00:00"), entry(3, "2026-12-01 07:00:00"), entry(7, "2026-12-01 06:59:59")
        ])
        #expect(groups.first?.entries.map(\.id) == [7, 3, 9])
    }

    @Test("첫 글 삭제 시 다음 글 위 날짜가 유지되고 하루 전체 삭제 시 날짜도 사라진다")
    func deletion() {
        let first = entry(1, "2026-12-01 00:00:00")
        let second = entry(2, "2026-12-01 07:00:00")
        let nextDay = entry(3, "2026-12-02 00:00:00")
        #expect(DiaryTimelineGrouping.groups([first, second, nextDay]).count == 2)
        let afterFirstDeletion = DiaryTimelineGrouping.groups([second, nextDay])
        #expect(afterFirstDeletion.first?.title == "2026년 12월 1일")
        #expect(afterFirstDeletion.first?.entries.map(\.id) == [2])
        #expect(DiaryTimelineGrouping.groups([nextDay]).map(\.title) == ["2026년 12월 2일"])
        #expect(DiaryTimelineGrouping.groups([]).isEmpty)
    }

    @Test("내용 수정이나 당일 글 추가는 최초 게시일 구분을 바꾸거나 반복하지 않는다")
    func editingAndAppending() {
        let edited = entry(1, "2026-12-01 07:00:00", content: "다음날 수정한 내용")
        let groups = DiaryTimelineGrouping.groups([entry(2, "2026-12-01 08:00:00"), edited])
        #expect(groups.map(\.title) == ["2026년 12월 1일"])
        #expect(groups.first?.entries.map(\.id) == [1, 2])
        #expect(groups.first?.entries.first?.content == "다음날 수정한 내용")
    }

    @Test("윤년은 허용하지만 존재하지 않는 날짜나 누락된 시각은 숨기지 않고 마지막에 둔다")
    func invalidDatesRemainVisible() {
        let invalid = [nil, "", "not-a-date", "2026-02-29 01:00:00", "2024-02-30 01:00:00", "2026-13-01 01:00:00", "2026-12-01 24:00:00", "2026-2-01 01:00:00", "2026-12-01 01:00:00 trailing", "2026-12-01T00:00:00+25:00", "2026-12-01T00:00:00+09:60", "2026-12-01T00:00:00Z\n"]
        var entries = invalid.enumerated().map { entry($0.offset + 10, $0.element) }
        entries.insert(entry(1, "2024-02-29 14:59:59"), at: 3)
        let groups = DiaryTimelineGrouping.groups(entries.reversed())
        #expect(groups.map(\.title) == ["2024년 2월 29일", "날짜 확인 필요"])
        #expect(groups.flatMap(\.entries).count == entries.count)
        #expect(groups.last?.entries.map(\.id) == Array(10..<(10 + invalid.count)))
        for raw in invalid { #expect(DiaryTimelineGrouping.timeLabel(raw) == "게시 시간 미확인") }
    }

    @Test("ISO UTC와 명시적 시간대 게시 시각도 같은 KST 날짜로 묶는다")
    func isoTimestamp() {
        let groups = DiaryTimelineGrouping.groups([
            entry(2, "2026-12-01T00:00:00.123Z"), entry(1, "2026-12-01T09:00:00+09:00"),
            entry(3, "2026-02-29T00:00:00Z")
        ])
        #expect(groups.map(\.title) == ["2026년 12월 1일", "날짜 확인 필요"])
        #expect(groups.first?.entries.map(\.id) == [1, 2])
        #expect(DiaryTimelineGrouping.timeLabel("2026-12-01T00:00:00.123Z") == "오전 9:00")
    }

    @Test("주어진 예약 기록 전체를 유지하고 다른 호출의 기록을 섞지 않는다")
    func independentReservationInputs() {
        let firstReservation = [entry(1, "2026-12-01 00:00:00"), entry(2, "2026-12-03 00:00:00")]
        let otherReservation = [entry(3, "2026-12-02 00:00:00")]
        #expect(DiaryTimelineGrouping.groups(firstReservation).flatMap(\.entries).map(\.id) == [1, 2])
        #expect(DiaryTimelineGrouping.groups(otherReservation).flatMap(\.entries).map(\.id) == [3])
        #expect(DiaryTimelineGrouping.groups(firstReservation).flatMap(\.entries).map(\.id) == [1, 2])
    }
}
