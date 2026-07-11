import SwiftUI

// 사장님 '내 가게' 관리 — 등록된 가게 확인·해제 + 공공데이터 상호명 검색으로 등록
struct MyStoreSheet: View {
    @Environment(BoardingStore.self) private var boarding
    @Environment(AuthSession.self) private var authSession
    @Environment(\.dismiss) private var dismiss

    @State private var myStores: [OwnerStoreResponse] = []
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var pendingClaim: MapPin?

    // 상호명 부분일치 검색 (2글자 이상, 최대 30개)
    private var results: [MapPin] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return Array(boarding.pins.filter { $0.name.contains(q) }.prefix(30))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    registeredSection
                    searchSection
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .background(Color.brandCream.ignoresSafeArea())
            .navigationTitle("내 가게")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.brandBrown)
                    }
                }
            }
            .task { await load() }
            .alert("내 가게로 등록할까요?", isPresented: Binding(get: { pendingClaim != nil }, set: { if !$0 { pendingClaim = nil } })) {
                Button("취소", role: .cancel) {}
                Button("등록") {
                    if let pin = pendingClaim { claim(pin) }
                }
            } message: {
                Text("\(pendingClaim?.name ?? "")\n등록하면 이 가게로 온 문의가 채팅 목록 '받은 문의'에 보여요.")
            }
        }
    }

    // MARK: - 등록된 가게

    private var registeredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("등록된 내 가게")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.brandBrownMid)
            if myStores.isEmpty {
                Text("아직 등록한 가게가 없어요. 아래에서 상호명으로 검색해 등록해주세요.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brandBrownMid)
                    .padding(.vertical, 8)
            } else {
                ForEach(myStores, id: \.storeId) { store in
                    HStack(spacing: 10) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.name ?? "가게")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.brandBrown)
                                if let addr = store.address, !addr.isEmpty {
                                    Text(addr)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.brandBrownMid)
                                        .lineLimit(1)
                                }
                            }
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(hex: "#2c6b4a"))
                        }
                        Spacer()
                        Button(action: { unclaim(store) }) {
                            Text("해제")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.brandOrange)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.brandOrange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - 검색

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("가게 검색")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.brandBrownMid)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.brandBrownLight)
                TextField("가게 상호명을 입력해주세요", text: $query)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBrown)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))

            if query.trimmingCharacters(in: .whitespaces).count < 2 {
                Text("2글자 이상 입력하면 전국 등록 업체에서 찾아드려요")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brandBrownLight)
            } else if results.isEmpty {
                Text("검색 결과가 없어요. 상호명을 다시 확인해주세요.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brandBrownMid)
                    .padding(.vertical, 8)
            } else {
                ForEach(results) { pin in
                    resultRow(pin)
                }
            }
        }
    }

    private func resultRow(_ pin: MapPin) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                if !pin.address.isEmpty {
                    Text(pin.address)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.brandBrownMid)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isMine(pin) {
                Text("내 가게")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "#2c6b4a"))
            } else {
                Button(action: { pendingClaim = pin }) {
                    Text("등록")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.brandOrange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    // MARK: - Actions

    private func isMine(_ pin: MapPin) -> Bool {
        myStores.contains { ($0.storeKey ?? "") == pin.storeKey }
    }

    private func load() async {
        guard let uid = authSession.userId else { return }
        myStores = (try? await APIClient.shared.fetchOwnerStores(userId: uid)) ?? []
    }

    private func claim(_ pin: MapPin) {
        guard let uid = authSession.userId else { return }
        errorMessage = nil
        Task {
            do {
                try await APIClient.shared.claimStore(
                    userId: uid, storeKey: pin.storeKey,
                    storeName: pin.name, storeAddress: pin.address
                )
                await load()
            } catch {
                errorMessage = "등록에 실패했어요. 이미 다른 사장님의 가게일 수 있어요."
            }
        }
    }

    private func unclaim(_ store: OwnerStoreResponse) {
        guard let uid = authSession.userId, let sid = store.storeId else { return }
        errorMessage = nil
        Task {
            do {
                try await APIClient.shared.unclaimStore(userId: uid, storeId: sid)
                await load()
            } catch {
                errorMessage = "해제에 실패했어요. 다시 시도해주세요."
            }
        }
    }
}
