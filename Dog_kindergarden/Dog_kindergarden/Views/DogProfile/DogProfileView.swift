import SwiftUI
import Observation
import PhotosUI
import UIKit

// 백엔드 pets 테이블과 매핑되는 강아지 모델
struct Pet: Identifiable, Codable {
    let pet_id: Int
    let name: String
    let breed: String?
    let age: Int?
    let weight: Double?
    let gender: String?
    let note: String?
    let image_url: String?
    var id: Int { pet_id }
}

// 강아지 카드 배경색 — 순서대로 순환
private let dogCardColors: [Color] = [Color(hex: "#FFE6CC"), Color.brandGreenLight, Color.brandBlueLight]

@Observable
@MainActor
final class DogProfileViewModel {
    var showAddSheet = false
    var pets: [Pet] = []
    var isLoading = false
    var errorMessage: String?

    var dogName = ""
    var age = ""
    var weight = ""
    var breed = ""
    var gender = "남"
    var sociability = "좋음"
    var allergy = ""
    var notes = ""
    var selectedPhotoData: Data?
    var isPhotoLoading = false

    func reset() {
        dogName = ""; age = ""; weight = ""; breed = ""
        gender = "남"; sociability = "좋음"; allergy = ""; notes = ""
        selectedPhotoData = nil
    }

    // 강아지 목록 조회
    func loadPets(userId: Int) async {
        isLoading = true
        defer { isLoading = false }
        let url = APIEnvironment.apiBaseURL.appendingPathComponent("users/\(userId)/pets")
        do {
            let (data, _) = try await APITransport.data(for: APITransport.request(url: url))
            pets = try JSONDecoder().decode([Pet].self, from: data)
        } catch {
            errorMessage = "목록을 불러오지 못했어요."
        }
    }

    // 강아지 등록 — 성공 시 true. 사회성·알레르기·특이사항은 note 한 줄로 합쳐 저장
    func addPet(userId: Int) async -> Bool {
        errorMessage = nil
        let name = dogName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { errorMessage = "이름을 입력해주세요."; return false }

        var parts = ["사회성: \(sociability)"]
        let allergyTrim = allergy.trimmingCharacters(in: .whitespaces)
        if !allergyTrim.isEmpty { parts.append("알레르기: \(allergyTrim)") }
        let notesTrim = notes.trimmingCharacters(in: .whitespaces)
        if !notesTrim.isEmpty { parts.append("특이사항: \(notesTrim)") }

        var body: [String: Any] = ["name": name, "gender": gender, "note": parts.joined(separator: " / ")]
        let breedTrim = breed.trimmingCharacters(in: .whitespaces)
        if !breedTrim.isEmpty { body["breed"] = breedTrim }
        if let ageInt = parseInt(age) { body["age"] = ageInt }
        if let weightVal = parseDouble(weight) { body["weight"] = weightVal }
        if let selectedPhotoData {
            body["image_url"] = "data:image/jpeg;base64,\(selectedPhotoData.base64EncodedString())"
        }

        let url = APIEnvironment.apiBaseURL.appendingPathComponent("users/\(userId)/pets")
        var req = APITransport.request(url: url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            _ = try await APITransport.data(for: req)
            await loadPets(userId: userId)
            reset()
            return true
        } catch {
            errorMessage = "등록에 실패했어요."
            return false
        }
    }

    // 강아지 삭제
    func deletePet(petId: Int, userId: Int) async {
        errorMessage = nil
        let url = APIEnvironment.apiBaseURL.appendingPathComponent("pets/\(petId)")
        let req = APITransport.request(url: url, method: "DELETE")
        do {
            _ = try await APITransport.data(for: req)
            await loadPets(userId: userId)
        } catch {
            errorMessage = "삭제에 실패했어요."
        }
    }

    // "3살" → 3
    private func parseInt(_ s: String) -> Int? {
        Int(s.filter { $0.isNumber })
    }
    // "3.5kg" → 3.5
    private func parseDouble(_ s: String) -> Double? {
        Double(s.filter { $0.isNumber || $0 == "." })
    }

    func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        isPhotoLoading = true
        defer { isPhotoLoading = false }
        do {
            guard let original = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: original),
                  let normalized = image.normalizedPetPhoto(maxDimension: 1_024, compression: 0.72) else {
                errorMessage = "사진을 불러오지 못했어요."
                return
            }
            guard normalized.count <= 750_000 else {
                errorMessage = "사진 용량이 너무 커요. 다른 사진을 선택해주세요."
                return
            }
            selectedPhotoData = normalized
            errorMessage = nil
        } catch {
            errorMessage = "사진을 불러오지 못했어요."
        }
    }
}

private extension UIImage {
    func normalizedPetPhoto(maxDimension: CGFloat, compression: CGFloat) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: compression)
    }
}

private func petImage(from value: String?) -> UIImage? {
    guard let value,
          let comma = value.firstIndex(of: ","),
          value[..<comma].contains(";base64"),
          let data = Data(base64Encoded: String(value[value.index(after: comma)...])) else { return nil }
    return UIImage(data: data)
}

struct DogProfileView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession
    @State private var vm = DogProfileViewModel()
    @State private var petToDelete: Pet?
    @State private var selectedPet: Pet?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                navBar
                dogList
            }
            .padding(.bottom, 24)
        }
        .background(Color.brandCream.ignoresSafeArea())
        .sheet(isPresented: $vm.showAddSheet) {
            AddDogSheet(vm: vm, userId: authSession.userId)
        }
        .sheet(item: $selectedPet) { pet in
            PetDetailSheet(pet: pet, index: vm.pets.firstIndex { $0.id == pet.id } ?? 0)
        }
        .alert(
            "강아지 삭제",
            isPresented: Binding(get: { petToDelete != nil }, set: { if !$0 { petToDelete = nil } }),
            presenting: petToDelete
        ) { pet in
            Button("삭제", role: .destructive) {
                guard let uid = authSession.userId else { return }
                Task { await vm.deletePet(petId: pet.pet_id, userId: uid) }
            }
            Button("취소", role: .cancel) {}
        } message: { pet in
            Text("\(pet.name) 프로필을 삭제하면 되돌릴 수 없어요.")
        }
        .task {
            if let uid = authSession.userId { await vm.loadPets(userId: uid) }
        }
    }

    // MARK: - Nav

    private var navBar: some View {
        HStack {
            HStack(spacing: 12) {
                Button(action: router.back) {
                    Circle()
                        .fill(.white)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.brandBeigeBorder, lineWidth: 1))
                        .overlay(Image(systemName: "chevron.left").font(.system(size: 15)).foregroundStyle(Color.brandBrown))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("우리 아이 프로필")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(Color.brandBrown)
                    Text("총 \(vm.pets.count)마리")
                        .font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
                }
            }
            Spacer()
            Button(action: { vm.showAddSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 12))
                    Text("등록").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Color.brandOrange)
                .clipShape(Capsule())
                .shadow(color: Color.brandOrange.opacity(0.7), radius: 7, x: 0, y: 6)
            }
        }
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
    }

    // MARK: - List

    private var dogList: some View {
        VStack(spacing: 12) {
            if vm.isLoading && vm.pets.isEmpty {
                ProgressView().tint(Color.brandOrange).padding(.vertical, 24)
            } else {
                ForEach(Array(vm.pets.enumerated()), id: \.element.id) { idx, pet in
                    dogCard(pet, index: idx)
                }
            }
            addButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func dogCard(_ pet: Pet, index: Int) -> some View {
        let ageText = pet.age.map { "\($0)살" } ?? "나이 미상"
        var subParts: [String] = []
        if let g = pet.gender, !g.isEmpty { subParts.append(g) }
        subParts.append(pet.breed ?? "견종 미상")
        return HStack(spacing: 12) {
            // 본문 탭 → 상세 시트
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(dogCardColors[index % dogCardColors.count])
                        .frame(width: 64, height: 64)
                    if let image = petImage(from: pet.image_url) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipped()
                    } else {
                        Image(dogAvatarName(index)).resizable().scaledToFit().frame(width: 44, height: 44)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(pet.name)
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.brandBrown)
                        Text(ageText)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.brandBrownMid)
                    }
                    Text(subParts.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Color.brandBrownMid)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedPet = pet }

            Button(action: { petToDelete = pet }) {
                ZStack {
                    Circle().fill(Color(hex: "#FFE6E6")).frame(width: 32, height: 32)
                    Image(systemName: "minus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
        .overlay(RoundedRectangle(cornerRadius: Radius.pill).stroke(Color.brandBeigeBorder, lineWidth: 1))
        .shadow(color: Color.brandBrown.opacity(0.1), radius: 7, x: 0, y: 6)
    }

    private var addButton: some View {
        Button(action: { vm.showAddSheet = true }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color(hex: "#FFE6CC")).frame(width: 40, height: 40)
                    Image(systemName: "plus")
                        .font(.system(size: 18)).foregroundStyle(Color.brandOrange)
                }
                Text("새로운 강아지 등록하기")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.brandBrown)
                Text("상세 정보를 입력해주세요")
                    .font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(.white.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
            .overlay(RoundedRectangle(cornerRadius: Radius.pill).stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4])).foregroundStyle(Color.brandBeigeBorder))
        }
    }

}

// MARK: - AddDogSheet

struct AddDogSheet: View {
    @Bindable var vm: DogProfileViewModel
    let userId: Int?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photoButton
                    Group {
                        sheetField("이름", text: $vm.dogName, placeholder: "예: 몽이")
                        HStack(spacing: 10) {
                            sheetField("나이",   text: $vm.age,    placeholder: "3살")
                            sheetField("몸무게", text: $vm.weight, placeholder: "3.5kg")
                        }
                        sheetField("견종", text: $vm.breed, placeholder: "포메라니안")
                        HStack(spacing: 10) {
                            pickField("성별",   options: ["남","여"],       selected: $vm.gender)
                            pickField("사회성", options: ["좋음","보통","낮음"], selected: $vm.sociability)
                        }
                        sheetField("알레르기", text: $vm.allergy, placeholder: "예: 닭고기")
                        sheetField("특이사항", text: $vm.notes,   placeholder: "겁이 많아요", multiline: true)
                    }

                    Button(action: {
                        guard let userId else { return }
                        Task {
                            if await vm.addPet(userId: userId) { dismiss() }
                        }
                    }) {
                        HStack(spacing: 6) {
                            if vm.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                EmojiIcon(emoji: "🐾", size: 16)
                                Text("등록하기").font(.system(size: 15, weight: .bold))
                            }
                        }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.brandOrange)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                            .shadow(color: Color.brandOrange.opacity(0.7), radius: 9, x: 0, y: 8)
                    }
                    .disabled(userId == nil || vm.isLoading)

                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .background(Color.brandCream.ignoresSafeArea())
            .navigationTitle("강아지 등록하기")
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
        }
        .onChange(of: selectedPhotoItem) { _, item in
            Task { await vm.loadPhoto(from: item) }
        }
    }

    private var photoButton: some View {
        let selectedPhotoData = vm.selectedPhotoData
        let isPhotoLoading = vm.isPhotoLoading

        return PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#FFE6CC"))
                        .frame(width: 96, height: 96)
                        .overlay(Circle().stroke(.white, lineWidth: 4).shadow(radius: 4))
                    if let data = selectedPhotoData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 92, height: 92)
                            .clipShape(Circle())
                    } else if isPhotoLoading {
                        ProgressView().tint(Color.brandOrange)
                    } else {
                        EmojiIcon(emoji: "🐶", size: 48)
                    }
                }
                Circle()
                    .fill(Color.brandOrange)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "camera.fill").font(.system(size: 13)).foregroundStyle(.white))
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedPhotoData == nil ? "갤러리에서 강아지 사진 선택" : "강아지 사진 변경")
    }

    private func sheetField(_ label: String, text: Binding<String>, placeholder: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "#7a5635"))
            if multiline {
                TextEditor(text: text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBrown)
                    .frame(height: 60)
                    .padding(14)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBrown)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
            }
        }
    }

    private func pickField(_ label: String, options: [String], selected: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "#7a5635"))
            HStack(spacing: 4) {
                ForEach(options, id: \.self) { opt in
                    Button(action: { selected.wrappedValue = opt }) {
                        Text(opt)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selected.wrappedValue == opt ? Color.brandOrange : .clear)
                            .foregroundStyle(selected.wrappedValue == opt ? .white : Color(hex: "#7a5635"))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    }
                }
            }
            .padding(4)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        }
    }
}

// MARK: - PetDetailSheet

struct PetDetailSheet: View {
    let pet: Pet
    let index: Int
    @Environment(\.dismiss) private var dismiss

    // note "사회성: 좋음 / 알레르기: 닭고기 / 특이사항: ..." → [(label, value)]
    private var detailPairs: [(String, String)] {
        guard let note = pet.note, !note.isEmpty else { return [] }
        return note.components(separatedBy: " / ").map { part in
            if let range = part.range(of: ": ") {
                return (String(part[..<range.lowerBound]), String(part[range.upperBound...]))
            }
            return ("메모", part)
        }
    }

    // 성별·견종을 앞에 두고, note에서 파싱한 사회성/알레르기/특이사항을 이어붙임
    private var infoRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let g = pet.gender, !g.isEmpty { rows.append(("성별", g)) }
        if let b = pet.breed, !b.isEmpty { rows.append(("견종", b)) }
        rows.append(contentsOf: detailPairs)
        return rows
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if infoRows.isEmpty {
                        Text("등록된 상세 정보가 없어요")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.brandBrownMid)
                            .padding(.top, 8)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(infoRows.enumerated()), id: \.offset) { _, pair in
                                detailRow(label: pair.0, value: pair.1)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.brandCream.ignoresSafeArea())
            .navigationTitle(pet.name)
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
        }
    }

    private var header: some View {
        let ageText = pet.age.map { "\($0)살" } ?? "나이 미상"
        return VStack(spacing: 12) {
            ZStack {
                Circle().fill(dogCardColors[index % dogCardColors.count]).frame(width: 96, height: 96)
                if let image = petImage(from: pet.image_url) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 96, height: 96).clipShape(Circle())
                } else {
                    Image(dogAvatarName(index)).resizable().scaledToFit().frame(width: 64, height: 64)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(pet.name)
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(Color.brandBrown)
                Text(ageText)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.brandBrownMid)
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.brandBrownMid)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color.brandBrown)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }
}
