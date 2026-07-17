import SwiftUI

// 알림장 타임라인 — 보호자·사장님 공용. router.diaryContext.canWrite면 사장님 시점(작성/수정/삭제).
// 예약 1건에 엔트리 여러 개가 시간순으로 쌓인다.
struct DiaryTimelineView: View {
    @Environment(AppRouter.self) private var router

    @State private var entries: [DiaryEntry] = []
    @State private var isLoading = true
    @State private var composer: DiaryComposerMode?
    @State private var pendingDelete: DiaryEntry?

    private var context: DiaryContext? { router.diaryContext }
    private var canWrite: Bool { context?.canWrite ?? false }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ScrollView {
                if isLoading {
                    ProgressView().padding(.top, 100)
                } else if entries.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(entries) { entry in
                            entryCard(entry)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            if canWrite { writeBar }
        }
        .background(Color.brandCream.ignoresSafeArea())
        .task { await load() }
        .sheet(item: $composer) { mode in
            DiaryComposer(
                reservationId: context?.reservationId ?? 0,
                mode: mode,
                onSaved: { Task { await load() } }
            )
        }
        .alert("이 알림장을 삭제할까요?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("닫기", role: .cancel) {}
            Button("삭제", role: .destructive) {
                if let target = pendingDelete { delete(target) }
            }
        } message: {
            Text("삭제하면 보호자에게도 보이지 않아요. 되돌릴 수 없어요.")
        }
    }

    // MARK: - Nav

    private var navBar: some View {
        HStack(spacing: 12) {
            Button(action: router.back) {
                Circle()
                    .fill(.white)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.brandBeigeBorder, lineWidth: 1))
                    .overlay(Image(systemName: "chevron.left").font(.system(size: 15)).foregroundStyle(Color.brandBrown))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(context?.petName ?? "우리 아이") 알림장")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                Text(context?.storeName ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brandBrownMid)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
        .padding(.bottom, 12)
        .background(.white)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            EmojiIcon(emoji: "📔", size: 48)
            Text(canWrite ? "첫 알림장을 남겨보세요" : "아직 등록된 알림장이 없어요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Text(canWrite
                 ? "오늘 하루 어떻게 지냈는지 보호자에게 전해주세요"
                 : "가게가 알림장을 남기면 여기에 모여요")
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrownMid)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.top, 100)
    }

    // MARK: - Entry card

    private func entryCard(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(formatted(entry.createdAt))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.brandOrange)
                Spacer()
                if canWrite {
                    Menu {
                        Button("수정") { composer = .edit(entry) }
                        Button("삭제", role: .destructive) { pendingDelete = entry }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.brandBrownLight)
                            .frame(width: 28, height: 20, alignment: .trailing)
                    }
                }
            }
            Text(entry.content ?? "")
                .font(.system(size: 14))
                .foregroundStyle(Color.brandBrown)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    // MARK: - Write bar

    private var writeBar: some View {
        Button(action: { composer = .create }) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil").font(.system(size: 14, weight: .bold))
                Text("알림장 쓰기").font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.brandOrange)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .shadow(color: Color.brandOrange.opacity(0.6), radius: 8, x: 0, y: 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.white)
        .overlay(alignment: .top) { Divider().foregroundStyle(Color.brandBeigeBorder) }
    }

    // MARK: - Helpers

    // 서버 created_at(UTC)을 KST로 변환해 표시
    private func formatted(_ raw: String?) -> String {
        guard let raw else { return "" }
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        inFmt.timeZone = TimeZone(identifier: "UTC")
        guard let date = inFmt.date(from: raw) else { return raw }
        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "ko_KR")
        outFmt.timeZone = TimeZone(identifier: "Asia/Seoul")
        outFmt.dateFormat = "M월 d일 (E) a h:mm"
        return outFmt.string(from: date)
    }

    // MARK: - Actions

    private func load() async {
        defer { isLoading = false }
        guard let rid = context?.reservationId else { return }
        entries = (try? await APIClient.shared.fetchDiaries(reservationId: rid)) ?? []
    }

    private func delete(_ entry: DiaryEntry) {
        guard let did = entry.diaryId else { return }
        entries.removeAll { $0.diaryId == did }
        Task {
            do {
                try await APIClient.shared.deleteDiary(diaryId: did)
            } catch {
                await load()   // 실패 시 서버 상태로 복원
            }
        }
    }
}

// MARK: - Composer

// 작성/수정 겸용 시트. 작성 성공 시 서버가 보호자 채팅방에 자동 메시지를 남긴다(수정은 없음).
enum DiaryComposerMode: Identifiable {
    case create
    case edit(DiaryEntry)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let entry): return "edit-\(entry.id)"
        }
    }
}

private struct DiaryComposer: View {
    let reservationId: Int
    let mode: DiaryComposerMode
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    init(reservationId: Int, mode: DiaryComposerMode, onSaved: @escaping () -> Void) {
        self.reservationId = reservationId
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .create: _text = State(initialValue: "")
        case .edit(let entry): _text = State(initialValue: entry.content ?? "")
        }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("닫기") { dismiss() }
                    .font(.system(size: 14))
                    .foregroundStyle(Color.brandBrownMid)
                Spacer()
                Text(isEdit ? "알림장 수정" : "새 알림장")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                Spacer()
                Button(action: { Task { await save() } }) {
                    if isSaving {
                        ProgressView().tint(Color.brandOrange)
                    } else {
                        Text(isEdit ? "저장" : "등록")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(canSave ? Color.brandOrange : Color.brandBrownLight)
                    }
                }
                .disabled(!canSave || isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().foregroundStyle(Color.brandBeigeBorder)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("오늘 하루 어떻게 지냈는지 남겨주세요")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.brandBrownLight)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                }
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.brandBrown)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .focused($focused)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
        .background(Color.brandCream)
        .presentationDetents([.medium, .large])
        .onAppear { focused = true }
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            switch mode {
            case .create:
                try await APIClient.shared.createDiary(reservationId: reservationId, content: trimmed)
            case .edit(let entry):
                try await APIClient.shared.updateDiary(diaryId: entry.diaryId ?? 0, content: trimmed)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = "저장에 실패했어요. 잠시 후 다시 시도해주세요."
        }
    }
}
