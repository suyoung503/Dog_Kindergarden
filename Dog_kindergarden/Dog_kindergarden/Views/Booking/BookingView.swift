import SwiftUI
import Observation

// 강아지 카드 배경색 — 순서대로 순환
private let dogBgColors: [Color] = [Color(hex: "#FFE6CC"), Color.brandGreenLight, Color.brandBlueLight]

@Observable
@MainActor
final class BookingViewModel {
    var selectedPetId: Int?
    var selectedService = "호텔 1박"
    var selectedDate = Date()
    var selectedTime = "14:00"
    var request = ""

    var pets: [Pet] = []
    var isLoading = false
    var errorMessage: String?

    let services: [(name: String, price: String)] = [
        ("유치원 반일권", "₩20,000"),
        ("유치원 종일권", "₩35,000"),
        ("호텔 1박",      "₩50,000"),
        ("장기 이용",     "₩40,000~"),
    ]
    let times = ["10:00","12:00","14:00","16:00","18:00","20:00"]

    // "2026-07-12 (일)" — 예약 문자열(연도 포함, 서버·캘린더가 정확한 날짜로 해석)과 화면 표시에 공용
    var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd (E)"
        return formatter.string(from: selectedDate)
    }

    private let baseURL = "https://matgyeomung-api.dog-kindergarden.workers.dev"

    var selectedPet: Pet? { pets.first { $0.pet_id == selectedPetId } }

    private func servicePrice(_ name: String) -> String {
        services.first { $0.name == name }?.price ?? ""
    }

    // 픽업 서비스 고정 금액
    let pickupPrice = 10000

    // "₩50,000" / "₩40,000~" → 50000 / 40000
    private func priceValue(_ s: String) -> Int {
        Int(s.filter { $0.isNumber }) ?? 0
    }
    var selectedServicePrice: Int { priceValue(servicePrice(selectedService)) }
    var totalPrice: Int { selectedServicePrice + pickupPrice }

    // 50000 → "₩50,000"
    func won(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return "₩" + (f.string(from: NSNumber(value: n)) ?? "\(n)")
    }

    // 강아지 목록 조회
    func loadPets(userId: Int) async {
        guard let url = URL(string: "\(baseURL)/api/users/\(userId)/pets") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            pets = try JSONDecoder().decode([Pet].self, from: data)
            if selectedPetId == nil { selectedPetId = pets.first?.pet_id }
        } catch {
            errorMessage = "강아지 목록을 불러오지 못했어요."
        }
    }

    // 예약 신청 — 성공 시 BookingResult 반환
    func submit(userId: Int, storeName: String, storeKey: String, storeAddress: String, storeType: String) async -> BookingResult? {
        errorMessage = nil
        guard let petId = selectedPetId else { errorMessage = "강아지를 선택해주세요."; return nil }
        isLoading = true
        defer { isLoading = false }

        let schedule = "\(dateLabel) \(selectedTime)"
        let body: [String: Any] = [
            "user_id": userId,
            "pet_id": petId,
            "store_key": storeKey,
            "store_name": storeName,
            "store_address": storeAddress,
            "store_type": storeType,
            "start_date": schedule,
            "end_date": schedule,
            "reservation_type": selectedService,
            "request_message": request,
        ]

        guard let url = URL(string: "\(baseURL)/api/reservations") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 201,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rid = json["reservation_id"] as? Int,
                  let roomId = json["room_id"] as? Int else {
                errorMessage = "예약에 실패했어요."
                return nil
            }
            let pet = selectedPet
            return BookingResult(
                reservationId: rid,
                roomId: roomId,
                storeName: storeName,
                dogName: pet?.name ?? "",
                dogBreed: pet?.breed ?? "",
                schedule: schedule,
                price: won(totalPrice)
            )
        } catch {
            errorMessage = "예약에 실패했어요."
            return nil
        }
    }
}

struct BookingView: View {
    @Environment(AppRouter.self) private var router
    @Environment(UserProfile.self) private var userProfile
    @Environment(AuthSession.self) private var authSession
    @State private var vm = BookingViewModel()
    @State private var guardianPhone = ""
    @State private var guardianAddress = ""
    @State private var showCalendarDeniedAlert = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    navBar
                    summaryCard
                    dogSection
                    guardianSection
                    dateTimeSection
                    serviceSection
                    requestSection
                    totalSection
                }
                .padding(.bottom, 80)
            }
            .background(Color.brandCream.ignoresSafeArea())

            confirmButton
        }
        .task {
            guardianPhone = userProfile.phone
            guardianAddress = userProfile.address
            if let uid = authSession.userId { await vm.loadPets(userId: uid) }
        }
        .alert("캘린더 권한이 꺼져 있어요", isPresented: $showCalendarDeniedAlert) {
            Button("설정에서 허용") {
                router.go(.bookingDone)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("건너뛰기", role: .cancel) { router.go(.bookingDone) }
        } message: {
            Text("예약은 완료됐어요. 설정에서 캘린더 접근을 허용하면 다음 예약부터 일정이 자동으로 저장돼요.")
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
            Text("예약하기")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#FFE6CC")).frame(width: 48, height: 48)
                EmojiIcon(emoji: "🐶", size: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(router.selectedStore)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.brandBrown)
                Text("\(vm.dateLabel) · \(vm.selectedService)")
                    .font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
            }
            Spacer()
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Dog

    private var dogSection: some View {
        BookingSection(title: "🐶 강아지 선택") {
            if vm.pets.isEmpty {
                Text("등록된 강아지가 없어요. 먼저 강아지를 등록해주세요.")
                    .font(.system(size: 12)).foregroundStyle(Color.brandBrownMid)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(vm.pets.enumerated()), id: \.element.id) { idx, pet in
                            Button(action: { vm.selectedPetId = pet.pet_id }) {
                                VStack(spacing: 0) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: Radius.lg)
                                            .fill(dogBgColors[idx % dogBgColors.count])
                                            .frame(width: 48, height: 48)
                                        Image(dogAvatarName(idx)).resizable().scaledToFit().frame(width: 30, height: 30)
                                    }
                                    .padding(.bottom, 6)
                                    Text(pet.name).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandBrown)
                                    Text(pet.age.map { "\($0)살" } ?? "나이 미상").font(.system(size: 10)).foregroundStyle(Color.brandBrownMid)
                                }
                                .padding(12)
                                .frame(width: 100)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.xl)
                                        .stroke(vm.selectedPetId == pet.pet_id ? Color.brandOrange : Color.brandBeigeBorder, lineWidth: 2)
                                )
                                .background(vm.selectedPetId == pet.pet_id ? Color(hex: "#FFF1DC") : .clear, in: RoundedRectangle(cornerRadius: Radius.xl))
                            }
                        }
                    }
                }
                if let pet = vm.selectedPet {
                    VStack(spacing: 4) {
                        infoRow("이름", pet.name)
                        infoRow("나이 / 견종", "\(pet.age.map { "\($0)살" } ?? "나이 미상") / \(pet.breed ?? "견종 미상")")
                        infoRow("몸무게", pet.weight.map { "\($0)kg" } ?? "미상")
                        infoRow("메모", pet.note ?? "없음")
                    }
                    .padding(12)
                    .background(Color(hex: "#FFF1DC"))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                }
            }
        }
    }

    // MARK: - Guardian

    private var guardianSection: some View {
        BookingSection(title: "👤 보호자 정보") {
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Button(action: {
                        guardianPhone = userProfile.phone
                        guardianAddress = userProfile.address
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                            Text("자동 불러오기")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.brandGreen)
                    }
                    .disabled(userProfile.phone.isEmpty && userProfile.address.isEmpty)
                }
                formField(label: "이름", value: userProfile.name.isEmpty ? "이름 미설정" : userProfile.name)
                editField(label: "연락처", text: $guardianPhone, placeholder: "연락처를 입력하세요")
                editField(label: "주소",  text: $guardianAddress, placeholder: "주소를 입력하세요")
            }
        }
    }

    // MARK: - Date / Time

    private var dateTimeSection: some View {
        BookingSection(title: "📅 날짜 · 시간") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13)).foregroundStyle(Color.brandOrange)
                    Text("날짜 선택")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandBrown)
                }
                DatePicker("예약 날짜", selection: $vm.selectedDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ko_KR"))
                    .tint(Color.brandOrange)
                Divider().foregroundStyle(Color.brandBeigeBorder)
                Text("시간")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandBrown)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(vm.times, id: \.self) { t in
                        Button(action: { vm.selectedTime = t }) {
                            Text(t)
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(vm.selectedTime == t ? Color.brandBrown : Color.brandCream)
                                .foregroundStyle(vm.selectedTime == t ? .white : Color.brandBrown)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                        }
                    }
                }
            }
            .padding(12)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        }
    }

    // MARK: - Service

    private var serviceSection: some View {
        BookingSection(title: "🦴 서비스 선택") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(vm.services, id: \.name) { s in
                    Button(action: { vm.selectedService = s.name }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.name)
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandBrown)
                            Text(s.price)
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandOrange)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(vm.selectedService == s.name ? Color(hex: "#FFF1DC") : .white)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.xl)
                                .stroke(vm.selectedService == s.name ? Color.brandOrange : Color.brandBeigeBorder, lineWidth: 2)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Request

    private var requestSection: some View {
        BookingSection(title: "✍️ 요청사항") {
            TextEditor(text: $vm.request)
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrown)
                .frame(height: 72)
                .padding(14)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if vm.request.isEmpty {
                        Text("알레르기, 사료, 산책 시간 등 자유롭게 적어주세요")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.brandBrownLight)
                            .padding(.horizontal, 18)
                            .padding(.top, 22)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Total

    private var totalSection: some View {
        VStack(spacing: 4) {
            HStack {
                Text(vm.selectedService).font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
                Spacer()
                Text(vm.won(vm.selectedServicePrice)).font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
            }
            HStack {
                Text("픽업 서비스").font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
                Spacer()
                Text(vm.won(vm.pickupPrice)).font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
            }
            Divider().foregroundStyle(Color.brandBeigeBorder).padding(.vertical, 4)
            HStack {
                Text("총 결제 금액").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.brandBrown)
                Spacer()
                Text(vm.won(vm.totalPrice)).font(.system(size: 20, weight: .bold)).foregroundStyle(Color.brandOrange)
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Confirm button

    private var confirmButton: some View {
        VStack(spacing: 8) {
            if let error = vm.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
            }
            Text("가게 사정으로 예약이 취소될 수 있어요. 취소되면 채팅으로 알려드려요.")
                .font(.system(size: 11))
                .foregroundStyle(Color.brandBrown.opacity(0.6))
            Button(action: submitBooking) {
                HStack(spacing: 6) {
                    if vm.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                        Text("예약 신청하기").font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.brandOrange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                .shadow(color: Color.brandOrange.opacity(0.7), radius: 9, x: 0, y: 8)
            }
            .disabled(vm.isLoading || vm.selectedPetId == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.white)
        .overlay(alignment: .top) { Divider().foregroundStyle(Color.brandBeigeBorder) }
    }

    private func submitBooking() {
        guard let uid = authSession.userId else { return }
        // 입력한 보호자 정보 영구 저장 (다음 예약 때 자동 불러오기)
        if !guardianPhone.isEmpty { userProfile.phone = guardianPhone }
        if !guardianAddress.isEmpty { userProfile.address = guardianAddress }
        let pin = router.selectedPin
        let storeName = pin?.name ?? router.selectedStore
        Task {
            if let result = await vm.submit(
                userId: uid,
                storeName: storeName,
                storeKey: pin?.storeKey ?? "",
                storeAddress: pin?.address ?? "",
                storeType: pin?.type ?? ""
            ) {
                router.lastBooking = result
                // 예약 요청과 동시에 내 기기 캘린더에 일정 추가
                // (취소 시 삭제: 내가 취소하면 즉시, 사장님이 취소하면 예약 내역 열 때 동기화)
                if let date = CalendarService.parseSchedule(result.schedule) {
                    let saved = await CalendarService.addReservationEvent(
                        reservationId: result.reservationId,
                        title: "\(result.storeName) 예약",
                        notes: result.dogName.isEmpty ? nil : "\(result.dogName) 맡김",
                        date: date
                    )
                    // 권한 거부 상태면 시스템 알림이 다시 뜨지 않으므로 설정 이동을 직접 안내
                    if !saved && CalendarService.isAccessDenied {
                        showCalendarDeniedAlert = true
                        return
                    }
                }
                router.go(.bookingDone)
            }
        }
    }

    // MARK: - Helpers

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
            Spacer()
            Text(v).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: "#7a5635"))
        }
    }

    private func formField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(Color.brandBrownMid)
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.brandBrown)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    private func editField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(Color.brandBrownMid)
            TextField(placeholder, text: text)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.brandBrown)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }
}

// MARK: - BookingSection

struct BookingSection<Content: View>: View {
    let title: String
    var badge: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                EmojiTitle(title: title)
                Spacer()
                if let badge {
                    Text(badge).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.brandGreen)
                }
            }
            content
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}
