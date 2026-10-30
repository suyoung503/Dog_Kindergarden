import SwiftUI
import PhotosUI
import UIKit

// 알림장 타임라인 — 보호자·사장님 공용. router.diaryContext.canWrite면 사장님 시점(작성/수정/삭제).
// 예약 1건에 엔트리 여러 개가 시간순으로 쌓인다.
struct DiaryTimelineView: View {
    var embedded = false
    var embeddedContext: DiaryContext? = nil
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession
    @Environment(AppNotificationService.self) private var notificationService

    @State private var timeline = DiaryTimelineState()
    @State private var composer: DiaryComposerMode?
    @State private var composerContext: (identity: DiaryTimelineIdentity, lease: UInt)?
    @State private var pendingDelete: DiaryEntry?
    @State private var galleryPhotos: [DiaryPhoto] = []
    @State private var galleryIndex = 0
    @State private var isGalleryPresented = false

    private var context: DiaryContext? { embeddedContext ?? router.diaryContext }
    private var canWrite: Bool { context?.canWrite ?? false }
    private var timelineIdentity: DiaryTimelineIdentity {
        DiaryTimelineIdentity(
            userId: authSession.userId,
            token: AuthTokenStore.load(),
            baseURL: APIEnvironment.apiBaseURL,
            reservationId: context?.reservationId,
            canWrite: canWrite
        )
    }
    private var entries: [DiaryEntry] { timeline.identity == timelineIdentity ? timeline.entries : [] }
    private var loadPhase: AsyncLoadPhase { timeline.identity == timelineIdentity ? timeline.loadPhase : .loading }

    var body: some View {
        VStack(spacing: 0) {
            if !embedded { navBar }
            ScrollView {
                if entries.isEmpty {
                    emptyContent
                } else {
                    VStack(spacing: 12) {
                        loadStatusHeader
                        ForEach(DiaryTimelineGrouping.groups(entries)) { day in
                            daySeparator(day.title)
                            ForEach(day.entries) { entry in
                                entryCard(entry)
                            }
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
        .task(id: timelineIdentity) {
            guard !Task.isCancelled else { return }
            let identity = timelineIdentity
            let lease = timeline.activate(identity)
            defer { timeline.invalidate(lease: lease) }
            let updates = notificationService.updates()
            await load(for: identity, lease: lease)
            for await _ in updates {
                guard !Task.isCancelled else { return }
                await load(for: identity, lease: lease)
            }
        }
        .onDisappear { timeline.invalidate() }
        .onChange(of: timelineIdentity) { _, _ in
            composer = nil
            pendingDelete = nil
            isGalleryPresented = false
            galleryPhotos = []
        }
        .onChange(of: timeline.accessFailureRevision) { _, _ in
            composer = nil
            pendingDelete = nil
            isGalleryPresented = false
            galleryPhotos = []
        }
        .sheet(item: $composer) { mode in
            if let savedContext = composerContext {
                DiaryComposer(
                    reservationId: savedContext.identity.reservationId ?? 0,
                    mode: mode,
                    onSaved: { Task { await load(for: savedContext.identity, lease: savedContext.lease) } }
                )
            }
        }
        .fullScreenCover(isPresented: $isGalleryPresented) {
            DiaryPhotoGalleryView(photos: galleryPhotos, selectedIndex: $galleryIndex)
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
            AuthenticatedPetImage(value: context?.petImageUrl)
                .frame(width: 40, height: 40)
                .background(Color.brandGreenLight)
                .clipShape(Circle())
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

    @ViewBuilder
    private var emptyContent: some View {
        switch loadPhase {
        case .idle, .loading:
            AsyncLoadingStateView(message: "알림장을 불러오는 중이에요")
        case .loaded:
            emptyState
        case .failed(let message):
            AsyncLoadFailureView(message: message) {
                retryLoad()
            }
        }
    }

    @ViewBuilder
    private var loadStatusHeader: some View {
        switch loadPhase {
        case .loading:
            AsyncRefreshIndicator()
        case .failed(let message):
            AsyncLoadFailureView(message: message, compact: true) {
                retryLoad()
            }
        case .idle, .loaded:
            EmptyView()
        }
    }

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

    private func daySeparator(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
    }

    private func entryCard(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(DiaryTimelineGrouping.timeLabel(entry.createdAt))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.brandOrange)
                Spacer()
                if canWrite {
                    Menu {
                        Button("수정") { presentComposer(.edit(entry)) }
                        Button("삭제", role: .destructive) { pendingDelete = entry }
                    } label: {
                        if timeline.deletingIDs.contains(entry.id) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.brandBrownLight)
                                .frame(width: 28, height: 20, alignment: .trailing)
                        }
                    }
                    .disabled(timeline.deletingIDs.contains(entry.id))
                }
            }
            Text(entry.content ?? "")
                .font(.system(size: 14))
                .foregroundStyle(Color.brandBrown)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            let photos = entry.photos ?? []
            if !photos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                        AuthenticatedDiaryImage(
                            photo: photo,
                            onOpen: {
                                galleryPhotos = photos
                                galleryIndex = index
                                isGalleryPresented = true
                            },
                            actionLabel: "알림장 사진 \(index + 1) 전체 화면으로 보기"
                        )
                        .frame(width: 84, height: 84)
                        .background(Color.brandCream)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                        .clipped()
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    // MARK: - Write bar

    private var writeBar: some View {
        Button(action: { presentComposer(.create) }) {
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

    // MARK: - Actions

    private func load(for identity: DiaryTimelineIdentity, lease: UInt) async {
        await timeline.load(
            for: identity,
            lease: lease,
            currentIdentity: { timelineIdentity },
            fetch: { try await APIClient.shared.fetchDiaries(reservationId: $0) }
        )
    }

    private func presentComposer(_ mode: DiaryComposerMode) {
        let identity = timelineIdentity
        guard identity.canWrite, timeline.identity == identity else { return }
        composerContext = (identity, timeline.lease)
        composer = mode
    }

    private func retryLoad() {
        let identity = timelineIdentity
        let lease = timeline.lease
        Task { await load(for: identity, lease: lease) }
    }

    private func delete(_ entry: DiaryEntry) {
        guard let did = entry.diaryId else { return }
        let identity = timelineIdentity
        let lease = timeline.lease
        pendingDelete = nil
        Task {
            await timeline.delete(
                diaryId: did,
                for: identity,
                lease: lease,
                currentIdentity: { timelineIdentity },
                remove: { try await APIClient.shared.deleteDiary(diaryId: $0) }
            )
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

private struct PendingDiaryPhoto: Identifiable {
    let id = UUID()
    let data: Data
}

private enum DiaryComposerError: Error {
    case missingDiaryID
}

private struct DiaryComposer: View {
    let reservationId: Int
    let mode: DiaryComposerMode
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var existingPhotos: [DiaryPhoto]
    @State private var photosToDelete: [DiaryPhoto] = []
    @State private var pendingPhotos: [PendingDiaryPhoto] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var createdDiaryID: Int?
    @State private var isSaving = false
    @State private var isPhotoLoading = false
    @State private var errorMessage: String?
    @State private var photoMessage: String?
    @FocusState private var focused: Bool

    init(reservationId: Int, mode: DiaryComposerMode, onSaved: @escaping () -> Void) {
        self.reservationId = reservationId
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .create:
            _text = State(initialValue: "")
            _existingPhotos = State(initialValue: [])
        case .edit(let entry):
            _text = State(initialValue: entry.content ?? "")
            _existingPhotos = State(initialValue: entry.photos ?? [])
        }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var remainingPhotoCount: Int {
        DiaryPhotoPolicy.remainingSelectionCount(
            existingCount: existingPhotos.count,
            newSelectionCount: pendingPhotos.count
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("닫기") { dismiss() }
                    .font(.system(size: 14))
                    .foregroundStyle(Color.brandBrownMid)
                    .disabled(isSaving || isPhotoLoading)
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
                .disabled(!canSave || isSaving || isPhotoLoading)
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
            .frame(minHeight: 150)

            photoSection

            if let message = photoMessage ?? errorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .accessibilityLabel(message)
            }
        }
        .background(Color.brandCream)
        .presentationDetents([.medium, .large])
        .onAppear { focused = true }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(from: items) }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("사진")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                Spacer()
                Text("\(existingPhotos.count + pendingPhotos.count) / \(DiaryPhotoPolicy.maxPhotoCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.brandBrownMid)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(existingPhotos) { photo in
                        existingPhotoThumbnail(photo)
                    }
                    ForEach(pendingPhotos) { photo in
                        pendingPhotoThumbnail(photo)
                    }
                    if remainingPhotoCount > 0 {
                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: remainingPhotoCount,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            VStack(spacing: 5) {
                                if isPhotoLoading {
                                    ProgressView().tint(Color.brandOrange)
                                } else {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Color.brandOrange)
                                }
                                Text("사진 추가")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.brandBrownMid)
                            }
                            .frame(width: 78, height: 78)
                            .background(.white.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.lg)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(Color.brandBeigeBorder)
                            )
                        }
                        .disabled(isSaving || isPhotoLoading)
                        .accessibilityLabel("알림장 사진 추가, \(remainingPhotoCount)장 선택 가능")
                    }
                }
            }

            Text("원본 5MB 이하 · JPEG 1.5MB 이하로 저장")
                .font(.system(size: 10))
                .foregroundStyle(Color.brandBrownLight)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func existingPhotoThumbnail(_ photo: DiaryPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            AuthenticatedDiaryImage(photo: photo)
                .frame(width: 78, height: 78)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                .clipped()

            removeButton(label: "기존 알림장 사진 삭제") {
                existingPhotos.removeAll { $0.id == photo.id }
                if photo.photoId != nil { photosToDelete.append(photo) }
            }
        }
    }

    private func pendingPhotoThumbnail(_ photo: PendingDiaryPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: photo.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .clipped()
                    .accessibilityLabel("새 알림장 사진")
            }

            removeButton(label: "새 알림장 사진 선택 취소") {
                pendingPhotos.removeAll { $0.id == photo.id }
            }
        }
    }

    private func removeButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.black.opacity(0.65))
                .clipShape(Circle())
        }
        .offset(x: 5, y: -5)
        .accessibilityLabel(label)
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadPhotos(from items: [PhotosPickerItem]) async {
        isPhotoLoading = true
        photoMessage = nil
        defer {
            pickerItems = []
            isPhotoLoading = false
        }

        var failures = 0
        for item in items.prefix(remainingPhotoCount) {
            do {
                guard let file = try await item.loadTransferable(type: DiaryPhotoFile.self) else {
                    throw DiaryPhotoNormalizationError.invalidImage
                }
                defer { try? FileManager.default.removeItem(at: file.url) }
                let fileSize = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard fileSize <= DiaryPhotoPolicy.maxOriginalByteCount else {
                    throw DiaryPhotoNormalizationError.originalTooLarge
                }
                let original = try Data(contentsOf: file.url, options: .mappedIfSafe)
                let normalized = try DiaryPhotoNormalizer.normalize(original)
                pendingPhotos.append(PendingDiaryPhoto(data: normalized))
            } catch DiaryPhotoNormalizationError.originalTooLarge {
                failures += 1
                photoMessage = "5MB를 초과한 원본 사진은 추가할 수 없어요."
            } catch {
                failures += 1
                photoMessage = "일부 사진을 처리하지 못했어요. 다른 사진을 선택해주세요."
            }
        }
        if failures > 1 {
            photoMessage = "\(failures)장의 사진을 처리하지 못했어요. 원본은 장당 5MB 이하여야 해요."
        }
    }

    private func save() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        photoMessage = nil
        defer { isSaving = false }

        do {
            let diaryID = try await saveContent(trimmed)
            var deletionFailures = 0
            var uploadFailures = 0

            for photo in photosToDelete {
                guard let photoID = photo.photoId else { continue }
                do {
                    try await APIClient.shared.deleteDiaryPhoto(photoId: photoID)
                    photosToDelete.removeAll { $0.id == photo.id }
                } catch {
                    deletionFailures += 1
                }
            }

            for pending in pendingPhotos {
                do {
                    let uploaded = try await APIClient.shared.uploadDiaryPhoto(
                        diaryId: diaryID,
                        jpegData: pending.data,
                        idempotencyKey: pending.id
                    )
                    pendingPhotos.removeAll { $0.id == pending.id }
                    existingPhotos.append(uploaded)
                } catch {
                    uploadFailures += 1
                }
            }

            onSaved()
            guard deletionFailures == 0, uploadFailures == 0 else {
                errorMessage = partialFailureMessage(
                    deletionFailures: deletionFailures,
                    uploadFailures: uploadFailures
                )
                return
            }
            dismiss()
        } catch {
            errorMessage = "저장에 실패했어요. 잠시 후 다시 시도해주세요."
        }
    }

    private func saveContent(_ content: String) async throws -> Int {
        switch mode {
        case .create:
            if let createdDiaryID {
                try await APIClient.shared.updateDiary(diaryId: createdDiaryID, content: content)
                return createdDiaryID
            }
            let created = try await APIClient.shared.createDiary(reservationId: reservationId, content: content)
            guard let diaryID = created.diaryId else { throw DiaryComposerError.missingDiaryID }
            createdDiaryID = diaryID
            return diaryID
        case .edit(let entry):
            guard let diaryID = entry.diaryId else { throw DiaryComposerError.missingDiaryID }
            try await APIClient.shared.updateDiary(diaryId: diaryID, content: content)
            return diaryID
        }
    }

    private func partialFailureMessage(deletionFailures: Int, uploadFailures: Int) -> String {
        var parts: [String] = []
        if deletionFailures > 0 { parts.append("사진 \(deletionFailures)장 삭제") }
        if uploadFailures > 0 { parts.append("사진 \(uploadFailures)장 업로드") }
        return "내용은 저장됐지만 \(parts.joined(separator: ", "))에 실패했어요. 실패한 작업만 다시 시도할 수 있어요."
    }
}
