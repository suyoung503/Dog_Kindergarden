import SwiftUI

// 운영자 전용 가게 등록 요청함. 서버도 is_admin을 다시 확인하므로 화면 노출만으로 권한을 판단하지 않는다.
struct OwnerApplicationAdminView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession

    @State private var applications: [StoreOwnerApplication] = []
    @State private var isLoading = false
    @State private var processingId: Int?
    @State private var errorMessage: String?
    @State private var confirmation: Confirmation?

    private struct Confirmation: Identifiable {
        enum Action: Equatable { case approve, reject }
        let application: StoreOwnerApplication
        let action: Action
        var id: String { "\(application.id)-\(action)" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                navBar
                if isLoading {
                    ProgressView("등록 요청을 불러오는 중이에요")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if applications.isEmpty {
                    emptyState
                } else {
                    Text("신청자의 정보와 가게 정보를 실제로 확인한 뒤 승인해주세요.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.brandBrownMid)
                        .padding(.horizontal, 20)
                    ForEach(applications) { application in
                        applicationCard(application)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.brandCream.ignoresSafeArea())
        .task { await load() }
        .alert(item: $confirmation) { confirmation in
            let isApproval = confirmation.action == .approve
            return Alert(
                title: Text(isApproval ? "가게 등록을 승인할까요?" : "가게 등록을 거절할까요?"),
                message: Text(isApproval
                    ? "승인하면 이 계정이 \(confirmation.application.storeName ?? "가게")의 예약·채팅·알림장을 관리할 수 있어요."
                    : "거절하면 사장님 화면의 승인 대기 상태가 종료돼요."),
                primaryButton: .cancel(Text("취소")),
                secondaryButton: isApproval
                    ? .default(Text("승인")) { run(.approve, application: confirmation.application) }
                    : .destructive(Text("거절")) { run(.reject, application: confirmation.application) }
            )
        }
    }

    private var navBar: some View {
        HStack(spacing: 12) {
            Button(action: router.back) {
                Circle()
                    .fill(.white)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.brandBeigeBorder, lineWidth: 1))
                    .overlay(Image(systemName: "chevron.left").font(.system(size: 15)).foregroundStyle(Color.brandBrown))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("가게 등록 요청")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                Text("운영자 전용")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.brandOrange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 34))
                .foregroundStyle(Color.brandOrange)
            Text("승인 대기 중인 요청이 없어요")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    private func applicationCard(_ application: StoreOwnerApplication) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(application.storeName ?? "가게")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.brandBrown)
                    if let address = application.storeAddress, !address.isEmpty {
                        Text(address)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.brandBrownMid)
                    }
                }
                Spacer()
                Text("승인 대기")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.brandOrange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.brandOrange.opacity(0.12))
                    .clipShape(Capsule())
            }

            Divider().overlay(Color.brandBeigeBorder)

            VStack(alignment: .leading, spacing: 8) {
                detailRow("신청자", application.nickname ?? "이름 미등록")
                detailRow("연락처", nonEmpty(application.phone) ?? "미등록")
                detailRow("이메일", nonEmpty(application.email) ?? "미등록")
                detailRow("주소", nonEmpty(application.address) ?? "미등록")
                detailRow("사용자 번호", String(application.userId))
                if let appliedAt = application.appliedAt {
                    detailRow("요청 시각", appliedAt)
                }
            }

            HStack(spacing: 10) {
                Button("거절") {
                    confirmation = Confirmation(application: application, action: .reject)
                }
                .buttonStyle(AdminActionButtonStyle(color: Color.brandBrownMid, filled: false))

                Button("승인") {
                    confirmation = Confirmation(application: application, action: .approve)
                }
                .buttonStyle(AdminActionButtonStyle(color: Color.brandOrange, filled: true))
            }
            .disabled(processingId != nil)
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        .padding(.horizontal, 20)
        .opacity(processingId == application.id ? 0.55 : 1)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.brandBrownMid)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrown)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func load() async {
        guard authSession.isAdmin else {
            errorMessage = "운영자 계정만 확인할 수 있어요."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            applications = try await APIClient.shared.fetchPendingStoreOwnerApplications()
        } catch {
            errorMessage = "등록 요청을 불러오지 못했어요."
        }
    }

    private func run(_ action: Confirmation.Action, application: StoreOwnerApplication) {
        processingId = application.id
        errorMessage = nil
        Task {
            defer { processingId = nil }
            do {
                switch action {
                case .approve:
                    try await APIClient.shared.approveStoreOwnerApplication(id: application.id)
                case .reject:
                    try await APIClient.shared.rejectStoreOwnerApplication(id: application.id)
                }
                applications.removeAll { $0.id == application.id }
            } catch {
                errorMessage = action == .approve
                    ? "승인에 실패했어요. 가게 연결 상태를 확인해주세요."
                    : "거절 처리에 실패했어요. 다시 시도해주세요."
            }
        }
    }
}

private struct AdminActionButtonStyle: ButtonStyle {
    let color: Color
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(filled ? .white : color)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(filled ? color : color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
