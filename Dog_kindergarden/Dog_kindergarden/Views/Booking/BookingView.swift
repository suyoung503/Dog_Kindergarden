import SwiftUI
import Observation

// 강아지 카드 배경색 — 순서대로 순환

@Observable
@MainActor
final class BookingViewModel {
    var selectedPetId: Int?
    var selectedService = "시간권"
    var selectedDate = Date()
    // 시간권 시작 시간 — 자유 선택 (기본 14:00)
    var startTime = ReservationSchedule.calendar.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()
    var hours = 1               // 시간권 이용 시간
    var request = ""

    var pets: [Pet] = []
    var isLoading = false
    var errorMessage: String?
    var storePriceInfo: String?
    var isPriceLoading = false

    // D1에 저장된 업체 가격표에서 서비스별로 가장 가까운 행을 찾아 표시한다.
    // 일치하는 항목이 없을 때만 업체 확인으로 안내하며 임의 금액을 계산하지 않는다.
    var services: [(name: String, price: String)] {
        [
            ("시간권", matchedPrice(keywords: ["시간", "반일"])),
            ("종일권", matchedPrice(keywords: ["종일", "데이케어", "유치원", "주간"])),
            ("하루 숙박권", matchedPrice(keywords: ["숙박", "1박", "호텔"])),
        ]
    }
    let hourOptions = Array(1...6)

    var isHourly: Bool { selectedService == "시간권" }
    // 화면 표시·서버 reservation_type 공용 — 시간권은 이용 시간 포함
    var serviceLabel: String { isHourly ? "시간권 \(hours)시간" : selectedService }

    // "2026-07-12 (일)" — 예약 문자열(연도 포함, 서버·캘린더가 정확한 날짜로 해석)과 화면 표시에 공용
    var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = ReservationSchedule.calendar
        formatter.timeZone = ReservationSchedule.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd (E)"
        return formatter.string(from: selectedDate)
    }

    // "14:00" — 시간권 예약 문자열용 시작 시간
    var timeLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = ReservationSchedule.calendar
        formatter.timeZone = ReservationSchedule.calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: startTime)
    }

    var selectedPet: Pet? { pets.first { $0.pet_id == selectedPetId } }
    var selectedPriceText: String {
        services.first(where: { $0.name == selectedService })?.price ?? "가격 업체 확인"
    }

    var formattedStorePriceInfo: String? {
        guard let value = storePriceInfo?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: " / ", with: "\n")
    }

    private var priceLines: [String] {
        (formattedStorePriceInfo ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func matchedPrice(keywords: [String]) -> String {
        guard !priceLines.isEmpty else { return "가격 업체 확인" }
        return priceLines.first { line in
            keywords.contains { line.localizedCaseInsensitiveContains($0) }
        } ?? "가격표에서 확인"
    }

    // 강아지 목록 조회
    func loadPets(userId: Int) async {
        let url = APIEnvironment.apiBaseURL.appendingPathComponent("users/\(userId)/pets")
        do {
            let (data, _) = try await APITransport.data(for: APITransport.request(url: url))
            pets = try JSONDecoder().decode([Pet].self, from: data)
            if selectedPetId == nil { selectedPetId = pets.first?.pet_id }
        } catch {
            errorMessage = "강아지 목록을 불러오지 못했어요."
        }
    }

    func loadStorePrice(storeKey: String) async {
        isPriceLoading = true
        defer { isPriceLoading = false }
        do {
            storePriceInfo = try await APIClient.shared.fetchStoreDetail(storeKey: storeKey)?.priceInfo
        } catch {
            // 가격 호출 실패가 예약 입력 전체를 막지는 않도록 하되, 없는 값처럼 오인하지 않게 안내한다.
            storePriceInfo = nil
            errorMessage = "가격 정보를 불러오지 못했어요. 예약 전 업체에 확인해주세요."
        }
    }

    // 예약 신청 — 성공 시 BookingResult 반환
    func submit(userId: Int, storeName: String, storeKey: String, storeAddress: String, storeType: String,
                guardianPhone: String? = nil, guardianAddress: String? = nil) async -> BookingResult? {
        errorMessage = nil
        guard let pet = selectedPet else { errorMessage = "강아지를 선택해주세요."; return nil }
        isLoading = true
        defer { isLoading = false }

        // 시간권만 시간 포함, 종일권·숙박권은 날짜만 ("2026-07-12 (일)")
        let submittedService = selectedService
        let submittedHours = hours
        let submittedDate = selectedDate
        let submittedTime = startTime
        let submittedRequest = request
        let submittedType = serviceLabel
        let schedule = ReservationSchedule.booking(date: submittedDate, time: submittedTime,
                                                   service: submittedService, hours: submittedHours)
        // 응답 대기 중 선택이 바뀌어도 완료화면은 실제 제출한 예약을 표시한다.
        let price = selectedPriceText
        let isAllDay = submittedService != "시간권"
        let durationHours = isAllDay ? 1 : submittedHours
        var body: [String: Any] = [
            "user_id": userId,
            "pet_id": pet.pet_id,
            "store_key": storeKey,
            "store_name": storeName,
            "store_address": storeAddress,
            "store_type": storeType,
            "start_date": schedule.start,
            "end_date": schedule.end,
            "reservation_type": submittedType,
            "request_message": submittedRequest,
        ]
        if let guardianPhone { body["guardian_phone"] = guardianPhone }
        if let guardianAddress { body["guardian_address"] = guardianAddress }

        let url = APIEnvironment.apiBaseURL.appendingPathComponent("reservations")
        var req = APITransport.request(url: url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await APITransport.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rid = json["reservation_id"] as? Int,
                  let roomId = json["room_id"] as? Int else {
                errorMessage = "예약에 실패했어요."
                return nil
            }
            return BookingResult(
                reservationId: rid,
                roomId: roomId,
                storeName: storeName,
                dogName: pet.name,
                dogBreed: pet.breed ?? "",
                schedule: schedule.start,
                price: price,
                isAllDay: isAllDay,
                durationHours: durationHours,
                dogImageURL: pet.image_url
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
    @State private var bottomPanelInset: CGFloat = 34
    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable {
        case phone, address, request
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                navBar
                    .simultaneousGesture(dismissKeyboardTap)
                summaryCard
                    .simultaneousGesture(dismissKeyboardTap)
                dogSection
                    .simultaneousGesture(dismissKeyboardTap)
                guardianSection
                serviceSection
                    .simultaneousGesture(dismissKeyboardTap)
                dateTimeSection
                requestSection
                totalSection
                    .simultaneousGesture(dismissKeyboardTap)
            }
            .padding(.bottom, 16)
            // 배경만 탭을 받아 입력란 사이의 포커스 이동을 방해하지 않는다.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = nil }
            }
        }
        .background {
            Color.brandCream.ignoresSafeArea()
                .onTapGesture { focusedField = nil }
        }

        .safeAreaInset(edge: .bottom, spacing: 0) {
            confirmButton
                .simultaneousGesture(dismissKeyboardTap)
        }
        .onAppear { bottomPanelInset = UIApplication.safeAreaBottom }
        .task {
            guardianPhone = userProfile.phone
            guardianAddress = userProfile.address
            if let uid = authSession.userId { await vm.loadPets(userId: uid) }
            let key = router.selectedPin?.storeKey ?? router.selectedStore
            await vm.loadStorePrice(storeKey: key)
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
                EmojiIcon(emoji: storeTypeEmoji(router.selectedPin?.type), size: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(router.selectedStore)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.brandBrown)
                Text("\(vm.dateLabel) · \(vm.serviceLabel)")
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
                            Button(action: {
                                focusedField = nil
                                vm.selectedPetId = pet.pet_id
                            }) {
                                VStack(spacing: 0) {
                                    ZStack {
                                        if pet.image_url != nil {
                                            AuthenticatedPetImage(value: pet.image_url)
                                                .frame(width: 48, height: 48)
                                                .clipShape(Circle())
                                        } else {
                                            Image(dogAvatarName(idx)).resizable().scaledToFit()
                                                .frame(width: 48, height: 48)
                                                .clipShape(Circle())
                                        }
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
                                        .strokeBorder(vm.selectedPetId == pet.pet_id ? Color.brandOrange : Color.brandBeigeBorder, lineWidth: 2)
                                )
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
        BookingSection(title: "보호자 정보") {
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Button(action: {
                        focusedField = nil
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
                editField(label: "연락처", text: $guardianPhone, placeholder: "연락처를 입력하세요", field: .phone)
                editField(label: "주소",  text: $guardianAddress, placeholder: "주소를 입력하세요", field: .address)
            }
        }
    }

    // MARK: - Date / Time

    private var dateTimeSection: some View {
        BookingSection(title: vm.isHourly ? "📅 날짜 · 시간" : "📅 날짜") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13)).foregroundStyle(Color.brandOrange)
                    Text("날짜 선택")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandBrown)
                }
                .onTapGesture { focusedField = nil }
                BookingCalendar(selection: $vm.selectedDate) {
                    focusedField = nil
                }
                // 시간권만 시작 시간·이용 시간 선택 (종일권·숙박권은 날짜만)
                if vm.isHourly {
                    Divider().foregroundStyle(Color.brandBeigeBorder)
                    HStack {
                        Text("시작 시간")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandBrown)
                        Spacer()
                        DatePicker("시작 시간", selection: $vm.startTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "ko_KR"))
                            .environment(\.timeZone, BookingCalendarState.calendar.timeZone)
                            .tint(Color.brandOrange)
                    }
                    Text("이용 시간")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandBrown)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(vm.hourOptions, id: \.self) { h in
                            Button(action: {
                                focusedField = nil
                                vm.hours = h
                            }) {
                                Text("\(h)시간")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(vm.hours == h ? Color.brandBrown : Color.brandCream)
                                    .foregroundStyle(vm.hours == h ? .white : Color.brandBrown)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                            }
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
                    Button(action: {
                        focusedField = nil
                        vm.selectedService = s.name
                    }) {
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
        BookingSection(title: "요청사항") {
            TextEditor(text: $vm.request)
                .focused($focusedField, equals: .request)
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
        VStack(alignment: .leading, spacing: 6) {
            Label(vm.formattedStorePriceInfo == nil ? "가격은 업체마다 다릅니다" : "업체 등록 가격표", systemImage: "info.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            if vm.isPriceLoading {
                ProgressView().tint(Color.brandOrange)
            } else if let priceInfo = vm.formattedStorePriceInfo {
                Text(priceInfo)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.brandOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("수집된 가격은 참고용이며 예약 확정 전 업체와 서비스 범위와 최종 가격을 확인해주세요. 앱에서는 결제를 진행하지 않습니다.")
                .font(.system(size: 11))
                .foregroundStyle(Color.brandBrownMid)
                .fixedSize(horizontal: false, vertical: true)
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
        .padding(.top, 12)
        .padding(.bottom, max(20, bottomPanelInset / 2 + 12))
        .background(.white)
        .overlay(alignment: .top) { Divider().foregroundStyle(Color.brandBeigeBorder) }
    }

    private func submitBooking() {
        focusedField = nil
        guard let uid = authSession.userId else { return }
        // 자정 직후에는 달력의 지연 바인딩 보정보다 제출이 먼저 실행될 수 있다.
        vm.selectedDate = BookingCalendarState(selection: vm.selectedDate).selectedDate
        // 입력한 보호자 정보 영구 저장 (다음 예약 때 자동 불러오기)
        if !guardianPhone.isEmpty { userProfile.phone = guardianPhone }
        if !guardianAddress.isEmpty { userProfile.address = guardianAddress }
        let pin = router.selectedPin
        let storeName = pin?.name ?? router.selectedStore
        let submittedPhone = guardianPhone
        let submittedAddress = guardianAddress
        Task {
            if let result = await vm.submit(
                userId: uid,
                storeName: storeName,
                storeKey: pin?.storeKey ?? "",
                storeAddress: pin?.address ?? "",
                storeType: pin?.type ?? "",
                guardianPhone: submittedPhone,
                guardianAddress: submittedAddress
            ) {
                router.lastBooking = result
                router.go(.bookingDone)
            }
        }
    }

    // MARK: - Helpers

    private var dismissKeyboardTap: some Gesture {
        TapGesture().onEnded { focusedField = nil }
    }

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

    private func editField(label: String, text: Binding<String>, placeholder: String, field: InputField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(Color.brandBrownMid)
            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
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
