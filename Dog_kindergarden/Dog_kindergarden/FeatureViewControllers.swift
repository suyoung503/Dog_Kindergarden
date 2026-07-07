import UIKit

struct PetProfile {
    let name: String
    let breed: String
    let age: Int
    let weight: Double
    let gender: String
    let note: String
}

struct DiaryEntry {
    let dateText: String
    let content: String
    let mediaIcon: String
}

struct ChatMessageItem {
    let sender: String
    let content: String
    let isMine: Bool
    let isAuto: Bool
}

struct ReservationFlowContext {
    let reservationId: Int
    let roomId: Int
    let storeId: Int
}

enum MockData {
    static let pet = PetProfile(name: "초코", breed: "말티푸", age: 3, weight: 5.2, gender: "남아", note: "낯선 강아지에게 처음엔 조심스러워요. 닭고기 알러지가 있습니다.")
    static let pets = [
        PetProfile(name: "몽이", breed: "포메라니안", age: 3, weight: 3.2, gender: "남아", note: "겁이 많아요"),
        PetProfile(name: "초코", breed: "푸들", age: 5, weight: 4.4, gender: "여아", note: "활발해요"),
        PetProfile(name: "별이", breed: "말티즈", age: 1, weight: 2.8, gender: "여아", note: "사람을 좋아해요")
    ]
    static let diaries = [
        DiaryEntry(dateText: "오늘 오후 2:30", content: "초코가 친구들과 운동장에서 잘 놀았어요. 물도 충분히 마셨고 낮잠도 편하게 잤습니다.", mediaIcon: "photo"),
        DiaryEntry(dateText: "오늘 오전 11:10", content: "체크인 후 적응 시간을 가졌어요. 간식은 보호자님 요청대로 급여하지 않았습니다.", mediaIcon: "doc.text"),
        DiaryEntry(dateText: "어제 오후 5:20", content: "산책 후 발 닦기까지 완료했습니다. 컨디션 좋고 식사도 완식했어요.", mediaIcon: "video"),
    ]
    static let chatRooms: [(name: String, last: String, time: String, unread: Int, color: UIColor)] = [
        ("멍멍이 호텔", "네 픽업 가능하세요", "방금", 2, UIColor(hex: "#FFE6CC")),
        ("댕댕 유치원", "오늘 등원 사진 보내드려요", "10분", 0, UIColor(hex: "#BFE9D5")),
        ("포근 펫호텔", "예약 확정되었습니다!", "1시간", 0, UIColor(hex: "#C7E6F5")),
        ("왈왈케어", "준비물 안내 드릴게요", "어제", 1, UIColor(hex: "#FFF1A8"))
    ]
    static let messages = [
        ChatMessageItem(sender: "업체", content: "안녕하세요 보호자님! 맡겨멍 제휴 업체입니다.", isMine: false, isAuto: false),
        ChatMessageItem(sender: "업체", content: "예약 문의 감사합니다. 어떤 도움이 필요하실까요?", isMine: false, isAuto: false),
        ChatMessageItem(sender: "나", content: "토요일 1박 예약 가능할까요? 픽업도 되는지 궁금해요.", isMine: true, isAuto: false),
        ChatMessageItem(sender: "업체", content: "네 가능합니다. 분당구 내 픽업도 지원해요.", isMine: false, isAuto: false),
        ChatMessageItem(sender: "맡겨멍", content: "예약 요청이 완료되었습니다.", isMine: false, isAuto: true),
    ]
}
func pinScrollStack(
    scroll: UIScrollView,
    stack: UIStackView,
    in view: UIView,
    bottomInset: CGFloat = 0
) {

    scroll.translatesAutoresizingMaskIntoConstraints = false
    stack.translatesAutoresizingMaskIntoConstraints = false

    scroll.contentInsetAdjustmentBehavior = .never

    view.addSubview(scroll)
    scroll.addSubview(stack)

    NSLayoutConstraint.activate([

        scroll.topAnchor.constraint(equalTo: view.topAnchor),
        scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

        stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 12),

        // 핵심
        stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
        stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

        stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -bottomInset),

        // 핵심
        stack.widthAnchor.constraint(
            equalTo: view.widthAnchor,
            constant: -40
        )
    ])
}

final class ReservationViewController: UIViewController {
    private let store: DogCareStore
    private let dogSegment = UISegmentedControl(items: ["몽이", "초코", "별이"])
    private let serviceSegment = UISegmentedControl(items: ["유치원", "호텔 1박", "장기"])
    private let datePicker = UIDatePicker()
    private let timePicker = UIDatePicker()
    private let requestView = UITextView()

    init(store: DogCareStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "예약하기"
        view.backgroundColor = AppColor.background
        buildUI()
    }

    private func buildUI() {
        let scroll = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        scroll.translatesAutoresizingMaskIntoConstraints = false
        
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 12),
            
            // 핵심 수정
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -100),

            // 핵심 추가
            stack.widthAnchor.constraint(
                equalTo: scroll.widthAnchor,
                constant: -40
            )
        ])

        let summary = WhiteCardView()
        let summaryStack = UIStackView(arrangedSubviews: [
            titleLabel(store.name, size: 16),
            bodyLabel("토 6/13 · 호텔 1박", color: UIColor(hex: "#A07A55"))
        ])
        summaryStack.axis = .vertical
        summaryStack.spacing = 4
        let icon = squareIcon("house", bg: UIColor(hex: "#FFE6CC"))
        let row = UIStackView(arrangedSubviews: [icon, summaryStack])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        summary.embed(row, padding: 14)
        stack.addArrangedSubview(summary)

        dogSegment.selectedSegmentIndex = 0
        serviceSegment.selectedSegmentIndex = 1
        serviceSegment.selectedSegmentTintColor = AppColor.orange
        dogSegment.selectedSegmentTintColor = AppColor.orange

        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        timePicker.datePickerMode = .time
        timePicker.preferredDatePickerStyle = .compact

        requestView.text = "알레르기, 사료, 산책 시간 등 자유롭게 적어주세요"
        requestView.textColor = .secondaryLabel
        requestView.font = .systemFont(ofSize: 13)
        requestView.backgroundColor = .clear
        requestView.delegate = self
        requestView.heightAnchor.constraint(equalToConstant: 84).isActive = true

        stack.addArrangedSubview(sectionHeader("강아지 선택"))
        stack.addArrangedSubview(formCard(title: nil, content: dogSegment))
        stack.addArrangedSubview(sectionHeader("보호자 정보"))
        stack.addArrangedSubview(infoFields())
        stack.addArrangedSubview(sectionHeader("날짜 · 시간"))
        stack.addArrangedSubview(dateTimeCard())
        stack.addArrangedSubview(sectionHeader("서비스 선택"))
        stack.addArrangedSubview(formCard(title: nil, content: serviceSegment))
        stack.addArrangedSubview(sectionHeader("요청사항"))
        stack.addArrangedSubview(formCard(title: nil, content: requestView))
        stack.addArrangedSubview(priceCard())

        let footer = bottomCTA(title: "예약 신청하기") { [weak self] in
            self?.submitReservation()
        }
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func infoFields() -> UIView {
        let card = UIStackView(arrangedSubviews: [
            filledField(label: "이름", value: "김상민"),
            filledField(label: "연락처", value: "010-1234-5678"),
            filledField(label: "주소", value: "경기 성남시 분당구 정자로 1")
        ])
        card.axis = .vertical
        card.spacing = 10
        return card
    }

    private func dateTimeCard() -> UIView {
        let wrap = WhiteCardView()
        let stack = UIStackView(arrangedSubviews: [
            titleLabel("날짜 선택", size: 12),
            datePicker,
            titleLabel("시간", size: 12),
            timePicker
        ])
        stack.axis = .vertical
        stack.spacing = 10
        wrap.embed(stack, padding: 14)
        return wrap
    }

    private func priceCard() -> UIView {
        let wrap = WhiteCardView()
        let total = UILabel()
        total.text = "총 결제 금액   ₩60,000"
        total.font = .systemFont(ofSize: 18, weight: .bold)
        total.textColor = AppColor.orange
        wrap.embed(total, padding: 14)
        return wrap
    }

    private func submitReservation() {
        let type: ReservationKind = serviceSegment.selectedSegmentIndex == 2 ? .regular : .normal
        let message = requestView.textColor == .secondaryLabel ? "" : requestView.text ?? ""
        Task { [weak self] in
            guard let self else { return }
            var context = ReservationFlowContext(reservationId: 1, roomId: 1, storeId: Int(store.id) ?? 1)
            do {
                let response = try await APIClient.shared.createReservation(store: store, startDate: datePicker.date, endDate: datePicker.date.addingTimeInterval(60*60*24), type: type, message: message)
                let reservationId = response.reservationId ?? response.id ?? 1
                context = ReservationFlowContext(reservationId: reservationId, roomId: reservationId, storeId: Int(store.id) ?? 1)
            } catch {
                print("예약 요청 실패: \(error)")
            }
            let pet = (try? await APIClient.shared.fetchPets().first) ?? MockData.pets[dogSegment.selectedSegmentIndex]
            await MainActor.run {
                self.navigationController?.pushViewController(BookingDoneViewController(store: self.store, pet: pet, context: context), animated: true)
            }
        }
    }
}

extension ReservationViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == .secondaryLabel {
            textView.text = ""
            textView.textColor = UIColor(hex: "#5B3A1F")
        }
    }
}

final class BookingDoneViewController: UIViewController {
    private let store: DogCareStore
    private let pet: PetProfile
    private let context: ReservationFlowContext

    init(store: DogCareStore, pet: PetProfile, context: ReservationFlowContext) {
        self.store = store; self.pet = pet; self.context = context
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: "#FAF3E7")
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])

        let circle = UIView()
        circle.backgroundColor = UIColor(hex: "#FFE6CC")
        circle.layer.cornerRadius = 64
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.widthAnchor.constraint(equalToConstant: 128).isActive = true
        circle.heightAnchor.constraint(equalToConstant: 128).isActive = true
        let icon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        icon.tintColor = UIColor(hex: "#5BB58A")
        icon.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56)
        ])

        stack.addArrangedSubview(circle)
        stack.addArrangedSubview(titleLabel("예약 신청이 완료됐어요!", size: 22))
        stack.addArrangedSubview(bodyLabel("\(store.name)에 대한 예약 요청이 접수되었습니다.", color: UIColor(hex: "#A07A55")))

        let button = PrimaryButton(title: "반려견 프로필 보기", target: self, action: #selector(openPet))
        button.widthAnchor.constraint(equalToConstant: 240).isActive = true
        stack.addArrangedSubview(button)
    }

    @objc private func openPet() {
        navigationController?.pushViewController(PetProfileViewController(store: store, pet: pet, context: context), animated: true)
    }
}

final class PetProfileViewController: UIViewController {
    private let store: DogCareStore
    private let pet: PetProfile
    private let context: ReservationFlowContext
    private var pets: [PetProfile] = MockData.pets
    private let stack = UIStackView()
    private let countLabel = UILabel()
    private let addPetButton = UIButton(type: .system)
    private lazy var nextButton = PrimaryButton(title: "알림장 화면으로 이동", target: self, action: #selector(openDiary))

    init(store: DogCareStore, pet: PetProfile, context: ReservationFlowContext) {
        self.store = store; self.pet = pet; self.context = context
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "우리 아이 프로필"
        view.backgroundColor = AppColor.background
        navigationItem.rightBarButtonItem = nil
        buildUI()
    }

    private func buildUI() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12

        countLabel.font = .systemFont(ofSize: 14, weight: .bold)
        countLabel.textColor = UIColor(hex: "#7A5635")

        addPetButton.setTitle("새로운 강아지 등록하기", for: .normal)
        addPetButton.setTitleColor(UIColor(hex: "#5B3A1F"), for: .normal)
        addPetButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        addPetButton.backgroundColor = UIColor.white.withAlphaComponent(0.72)
        addPetButton.layer.cornerRadius = 24
        addPetButton.layer.borderWidth = 2
        addPetButton.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor
        addPetButton.heightAnchor.constraint(equalToConstant: 88).isActive = true
        addPetButton.addTarget(self, action: #selector(showAddPet), for: .touchUpInside)

        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -24),
            
        ])
        reloadPetCards()
    }

    private func reloadPetCards() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        countLabel.text = "총 \(pets.count)마리"
        stack.addArrangedSubview(countLabel)

        for pet in pets {
            stack.addArrangedSubview(makePetCard(for: pet))
        }

        stack.addArrangedSubview(addPetButton)
        stack.addArrangedSubview(nextButton)
    }

    private func makePetCard(for pet: PetProfile) -> UIView {
        let card = WhiteCardView()
        let icon = squareIcon("pawprint.fill", bg: UIColor(hex: "#FFE6CC"), size: 64)
        let name = titleLabel("\(pet.name) / \(pet.age)살", size: 15)
        let breed = bodyLabel(pet.breed, color: UIColor(hex: "#A07A55"))
        let tags = UIStackView(arrangedSubviews: [badge("사회성", bg: UIColor(hex: "#FFF1A8")), badge("건강", bg: UIColor(hex: "#BFE9D5"))])
        tags.axis = .horizontal
        tags.spacing = 6

        let info = UIStackView(arrangedSubviews: [name, breed, tags])
        info.axis = .vertical
        info.spacing = 6

        let edit = UIButton(type: .system)
        edit.setTitle("수정", for: .normal)
        edit.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        edit.setTitleColor(AppColor.orange, for: .normal)

        let row = UIStackView(arrangedSubviews: [icon, info, UIView(), edit])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center

        card.embed(row, padding: 14)
        return card
    }

    @objc private func showAddPet() {
        let addVC = AddPetViewController()
        addVC.onAdd = { [weak self] profile in
            self?.pets.append(profile)
            self?.reloadPetCards()
        }
        let nav = UINavigationController(rootViewController: addVC)
        present(nav, animated: true)
    }

    @objc private func openDiary() {
        navigationController?.pushViewController(DiaryViewController(store: store, pet: pet, context: context), animated: true)
    }
}

final class AddPetViewController: UIViewController {
    var onAdd: ((PetProfile) -> Void)?
    private let nameField = UITextField()
    private let ageField = UITextField()
    private let weightField = UITextField()
    private let breedField = UITextField()
    private let noteView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "강아지 등록하기"
        view.backgroundColor = AppColor.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        buildUI()
    }

    private func buildUI() {
        let stack = UIStackView(arrangedSubviews: [
            filledField(label: "이름", field: nameField, placeholder: "예: 몽이"),
            filledField(label: "나이", field: ageField, placeholder: "3"),
            filledField(label: "몸무게", field: weightField, placeholder: "3.5"),
            filledField(label: "견종", field: breedField, placeholder: "포메라니안"),
            noteCard(),
            PrimaryButton(title: "등록하기", target: self, action: #selector(saveTapped))
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    private func noteCard() -> UIView {
        noteView.text = "특이사항"
        noteView.textColor = .secondaryLabel
        noteView.delegate = self
        noteView.backgroundColor = .clear
        noteView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        return formCard(title: "특이사항", content: noteView)
    }

    @objc private func saveTapped() {
        let profile = PetProfile(
            name: nameField.text?.isEmpty == false ? nameField.text! : "새 강아지",
            breed: breedField.text?.isEmpty == false ? breedField.text! : "정보 없음",
            age: Int(ageField.text ?? "") ?? 0,
            weight: Double(weightField.text ?? "") ?? 0,
            gender: "미정",
            note: noteView.textColor == .secondaryLabel ? "" : noteView.text
        )
        onAdd?(profile)
        dismiss(animated: true)
    }

    @objc private func closeTapped() { dismiss(animated: true) }
}

extension AddPetViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == .secondaryLabel { textView.text = ""; textView.textColor = UIColor(hex: "#5B3A1F") }
    }
}

final class DiaryViewController: UIViewController {
    private let store: DogCareStore
    private let pet: PetProfile
    private let context: ReservationFlowContext
    private var diaries = MockData.diaries
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(store: DogCareStore, pet: PetProfile, context: ReservationFlowContext) {
        self.store = store; self.pet = pet; self.context = context
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "알림장"
        view.backgroundColor = AppColor.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "채팅", style: .plain, target: self, action: #selector(openChat))
        buildUI(); loadDiaries()
    }

    private func buildUI() {
        let header = WhiteCardView()
        let title = titleLabel("\(pet.name)의 오늘 기록", size: 18)
        let sub = bodyLabel("업체가 남긴 사진, 영상, 텍스트 기록을 날짜별로 확인합니다.", color: UIColor(hex: "#A07A55"))
        let stack = UIStackView(arrangedSubviews: [title, sub])
        stack.axis = .vertical; stack.spacing = 6
        header.embed(stack, padding: 16)
        header.translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.register(DiaryCell.self, forCellReuseIdentifier: DiaryCell.reuseIdentifier)

        let button = bottomCTA(title: "업체와 채팅하기") { [weak self] in self?.openChat() }
        view.addSubview(header)
        view.addSubview(tableView)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: button.topAnchor),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadDiaries() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await APIClient.shared.fetchDiaries(reservationId: self.context.reservationId)
                guard !result.isEmpty else { return }
                await MainActor.run { self.diaries = result; self.tableView.reloadData() }
            } catch { print("알림장 로드 실패: \(error)") }
        }
    }

    @objc private func openChat() {
        navigationController?.pushViewController(ChatViewController(store: store, context: context), animated: true)
    }
}

extension DiaryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { diaries.count }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 112 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DiaryCell.reuseIdentifier, for: indexPath) as! DiaryCell
        cell.configure(with: diaries[indexPath.row])
        return cell
    }
}

final class ChatListViewController: UIViewController {
    private let rooms = MockData.chatRooms
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "채팅"
        view.backgroundColor = AppColor.background
        buildUI()
    }

    private func buildUI() {
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20)
        ])
        for (idx, room) in rooms.enumerated() {
            let button = UIButton(type: .system)
            button.backgroundColor = .white
            button.layer.cornerRadius = 18
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor
            button.heightAnchor.constraint(equalToConstant: 78).isActive = true
            button.tag = idx
            button.addTarget(self, action: #selector(openRoom(_:)), for: .touchUpInside)

            let icon = squareIcon("message.fill", bg: room.color, size: 48)
            let name = titleLabel(room.name, size: 14)
            let last = bodyLabel(room.last, color: UIColor(hex: "#7A5635"))
            let text = UIStackView(arrangedSubviews: [name, last]); text.axis = .vertical; text.spacing = 4
            let meta = UILabel(); meta.text = room.time; meta.font = .systemFont(ofSize: 10); meta.textColor = UIColor(hex: "#A07A55")
            let row = UIStackView(arrangedSubviews: [icon, text, UIView(), meta]); row.axis = .horizontal; row.spacing = 12; row.alignment = .center
            let wrap = UIView(); wrap.translatesAutoresizingMaskIntoConstraints = false; button.addSubview(wrap); wrap.addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                wrap.topAnchor.constraint(equalTo: button.topAnchor), wrap.leadingAnchor.constraint(equalTo: button.leadingAnchor), wrap.trailingAnchor.constraint(equalTo: button.trailingAnchor), wrap.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                row.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14), row.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14), row.centerYAnchor.constraint(equalTo: wrap.centerYAnchor)
            ])
            stack.addArrangedSubview(button)
        }
    }

    @objc private func openRoom(_ sender: UIButton) {
        let store = DogCareStore(id: "1", name: rooms[sender.tag].name, status: "영업", roadAddress: "서울 강남구", lotAddress: "", phone: "", x: "", y: "")
        let context = ReservationFlowContext(reservationId: 1, roomId: 1, storeId: 1)
        navigationController?.pushViewController(ChatViewController(store: store, context: context), animated: true)
    }
}

final class ChatViewController: UIViewController {
    private let store: DogCareStore
    private let context: ReservationFlowContext
    private var messages = MockData.messages
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputField = UITextField()

    init(store: DogCareStore, context: ReservationFlowContext) {
        self.store = store; self.context = context
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = store.name
        view.backgroundColor = AppColor.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "리뷰", style: .plain, target: self, action: #selector(openReview))
        buildUI(); loadMessages()
    }

    private func buildUI() {
        let statusBar = WhiteCardView()
        let title = titleLabel(store.name, size: 14)
        let sub = bodyLabel("응답중", color: UIColor(hex: "#5BB58A"))
        let stack = UIStackView(arrangedSubviews: [title, sub]); stack.axis = .vertical; stack.spacing = 2
        let row = UIStackView(arrangedSubviews: [squareIcon("message", bg: UIColor(hex: "#FFE6CC"), size: 36), stack]); row.axis = .horizontal; row.spacing = 10; row.alignment = .center
        statusBar.embed(row, padding: 12)
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.register(ChatCell.self, forCellReuseIdentifier: ChatCell.reuseIdentifier)

        let inputWrap = UIView(); inputWrap.translatesAutoresizingMaskIntoConstraints = false; inputWrap.backgroundColor = .white
        inputWrap.layer.borderWidth = 1; inputWrap.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor
        let plus = UIButton(type: .system); plus.translatesAutoresizingMaskIntoConstraints = false; plus.setImage(UIImage(systemName: "plus"), for: .normal); plus.tintColor = UIColor(hex: "#5B3A1F"); plus.backgroundColor = UIColor(hex: "#FFE6CC"); plus.layer.cornerRadius = 18
        inputField.translatesAutoresizingMaskIntoConstraints = false; inputField.placeholder = "메시지를 입력해주세요"; inputField.backgroundColor = UIColor(hex: "#FAF3E7"); inputField.layer.cornerRadius = 18; inputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1)); inputField.leftViewMode = .always; inputField.delegate = self
        let send = UIButton(type: .system); send.translatesAutoresizingMaskIntoConstraints = false; send.setImage(UIImage(systemName: "paperplane.fill"), for: .normal); send.tintColor = .white; send.backgroundColor = AppColor.orange; send.layer.cornerRadius = 20; send.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        inputWrap.addSubview(plus); inputWrap.addSubview(inputField); inputWrap.addSubview(send)
        NSLayoutConstraint.activate([
            plus.leadingAnchor.constraint(equalTo: inputWrap.leadingAnchor, constant: 12), plus.centerYAnchor.constraint(equalTo: inputWrap.centerYAnchor), plus.widthAnchor.constraint(equalToConstant: 36), plus.heightAnchor.constraint(equalToConstant: 36),
            send.trailingAnchor.constraint(equalTo: inputWrap.trailingAnchor, constant: -12), send.centerYAnchor.constraint(equalTo: inputWrap.centerYAnchor), send.widthAnchor.constraint(equalToConstant: 40), send.heightAnchor.constraint(equalToConstant: 40),
            inputField.leadingAnchor.constraint(equalTo: plus.trailingAnchor, constant: 10), inputField.trailingAnchor.constraint(equalTo: send.leadingAnchor, constant: -10), inputField.topAnchor.constraint(equalTo: inputWrap.topAnchor, constant: 10), inputField.bottomAnchor.constraint(equalTo: inputWrap.bottomAnchor, constant: -10),
            inputWrap.heightAnchor.constraint(equalToConstant: 60)
        ])

        view.addSubview(statusBar); view.addSubview(tableView); view.addSubview(inputWrap)
        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            inputWrap.leadingAnchor.constraint(equalTo: view.leadingAnchor), inputWrap.trailingAnchor.constraint(equalTo: view.trailingAnchor), inputWrap.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            tableView.topAnchor.constraint(equalTo: statusBar.bottomAnchor, constant: 10), tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor), tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor), tableView.bottomAnchor.constraint(equalTo: inputWrap.topAnchor)
        ])
    }

    private func loadMessages() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await APIClient.shared.fetchMessages(roomId: self.context.roomId)
                guard !result.isEmpty else { return }
                await MainActor.run { self.messages = result; self.tableView.reloadData() }
            } catch { print("채팅 조회 실패: \(error)") }
        }
    }

    @objc private func sendTapped() {
        let text = (inputField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputField.text = ""
        Task { [weak self] in
            guard let self else { return }
            let item: ChatMessageItem
            do { item = try await APIClient.shared.sendMessage(roomId: self.context.roomId, content: text) }
            catch { item = ChatMessageItem(sender: "나", content: text, isMine: true, isAuto: false) }
            await MainActor.run {
                self.messages.append(item)
                self.tableView.reloadData()
                let idx = IndexPath(row: self.messages.count - 1, section: 0)
                self.tableView.scrollToRow(at: idx, at: .bottom, animated: true)
            }
        }
    }

    @objc private func openReview() {
        navigationController?.pushViewController(ReviewViewController(context: context), animated: true)
    }
}

extension ChatViewController: UITableViewDataSource, UITextFieldDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messages.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatCell.reuseIdentifier, for: indexPath) as! ChatCell
        cell.configure(with: messages[indexPath.row])
        return cell
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { sendTapped(); return true }
}

final class ReviewViewController: UIViewController {
    private let context: ReservationFlowContext
    private var reviews: [ReviewItem] = []
    private let ratingField = UITextField()
    private let revisitSwitch = UISwitch()
    private let contentView = UITextView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(context: ReservationFlowContext) { self.context = context; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "리뷰"
        view.backgroundColor = AppColor.background
        buildUI(); loadReviews()
    }

    private func buildUI() {
        ratingField.placeholder = "별점(0~5, 예: 4.5)"; ratingField.borderStyle = .roundedRect; ratingField.keyboardType = .decimalPad; ratingField.text = "5.0"
        contentView.text = "후기를 입력하세요"; contentView.textColor = .secondaryLabel; contentView.layer.cornerRadius = 10; contentView.layer.borderWidth = 1; contentView.layer.borderColor = UIColor.systemGray4.cgColor; contentView.heightAnchor.constraint(equalToConstant: 84).isActive = true; contentView.delegate = self
        let revisitLabel = UILabel(); revisitLabel.text = "재방문 의사"; revisitLabel.font = .systemFont(ofSize: 12, weight: .medium)
        let revisitRow = UIStackView(arrangedSubviews: [revisitLabel, revisitSwitch]); revisitRow.axis = .horizontal; revisitRow.distribution = .equalSpacing
        let form = UIStackView(arrangedSubviews: [ratingField, revisitRow, contentView, PrimaryButton(title: "리뷰 등록", target: self, action: #selector(submitTapped))]); form.axis = .vertical; form.spacing = 10
        let header = formCard(title: "리뷰 작성", content: form); header.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false; tableView.dataSource = self; tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ReviewCell")
        view.addSubview(header); view.addSubview(tableView)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12), header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8), tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor), tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor), tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadReviews() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await APIClient.shared.fetchStoreReviews(storeId: self.context.storeId)
                await MainActor.run { self.reviews = result; self.tableView.reloadData() }
            } catch { print("리뷰 조회 실패: \(error)") }
        }
    }

    @objc private func submitTapped() {
        let rating = Double(ratingField.text ?? "") ?? 5
        let content = contentView.textColor == .secondaryLabel ? "" : (contentView.text ?? "")
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await APIClient.shared.createReview(reservationId: self.context.reservationId, storeId: self.context.storeId, rating: rating, revisit: self.revisitSwitch.isOn, content: content)
                await MainActor.run { self.contentView.text = "후기를 입력하세요"; self.contentView.textColor = .secondaryLabel }
                self.loadReviews()
            } catch { print("리뷰 등록 실패: \(error)") }
        }
    }
}

extension ReviewViewController: UITableViewDataSource, UITextViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { reviews.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ReviewCell", for: indexPath)
        var cfg = cell.defaultContentConfiguration()
        let item = reviews[indexPath.row]
        cfg.text = "평점 \(item.rating) · \(item.revisit ? "재방문" : "단발")"
        cfg.secondaryText = item.content
        cfg.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = cfg
        return cell
    }
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == .secondaryLabel { textView.text = ""; textView.textColor = .label }
    }
}

final class MyPageViewController: UIViewController {
    private let store: DogCareStore?

    init(store: DogCareStore? = nil) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "마이페이지"
        view.backgroundColor = AppColor.background
        buildUI()
    }

    private func buildUI() {
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16), stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20)
        ])

        let profile = UIView(); profile.translatesAutoresizingMaskIntoConstraints = false
        profile.backgroundColor = UIColor(hex: "#F5A65B"); profile.layer.cornerRadius = 24
        let avatar = squareIcon("person.fill", bg: .white, size: 64, tint: UIColor(hex: "#5B3A1F"))
        let name = titleLabel("상민님", size: 17); name.textColor = .white
        let sub = bodyLabel("010-1234-5678 · 카카오 로그인", color: UIColor.white.withAlphaComponent(0.9))
        let info = UIStackView(arrangedSubviews: [name, sub]); info.axis = .vertical; info.spacing = 4
        let edit = UIButton(type: .system); edit.setTitle("수정", for: .normal); edit.setTitleColor(.white, for: .normal); edit.backgroundColor = UIColor.white.withAlphaComponent(0.25); edit.layer.cornerRadius = 14; edit.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        edit.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        let top = UIStackView(arrangedSubviews: [avatar, info, UIView(), edit]); top.axis = .horizontal; top.spacing = 12; top.alignment = .center
        let stats = UIStackView(arrangedSubviews: [stat("예약", "12"), stat("강아지", "3"), stat("포인트", "2,400")]); stats.axis = .horizontal; stats.spacing = 8; stats.distribution = .fillEqually
        let profileStack = UIStackView(arrangedSubviews: [top, stats]); profileStack.axis = .vertical; profileStack.spacing = 16; profileStack.translatesAutoresizingMaskIntoConstraints = false
        profile.addSubview(profileStack)
        NSLayoutConstraint.activate([
            profileStack.topAnchor.constraint(equalTo: profile.topAnchor, constant: 16), profileStack.leadingAnchor.constraint(equalTo: profile.leadingAnchor, constant: 16), profileStack.trailingAnchor.constraint(equalTo: profile.trailingAnchor, constant: -16), profileStack.bottomAnchor.constraint(equalTo: profile.bottomAnchor, constant: -16)
        ])
        stack.addArrangedSubview(profile)
        stack.addArrangedSubview(menuSection(title: "내 활동", rows: [
            rowItem("예약 내역"), rowItem("찜한 케어"), rowItem("채팅"), rowItem("쿠폰함")
        ]))
        stack.addArrangedSubview(menuSection(title: "내 정보", rows: [
            rowItem("우리 아이 프로필"), rowItem("알림 설정"), rowItem("앱 설정")
        ]))
        stack.addArrangedSubview(menuSection(title: "고객지원", rows: [
            rowItem("1:1 문의"), rowItem("공지사항"), rowItem("로그아웃")
        ]))
    }

    private func stat(_ title: String, _ value: String) -> UIView {
        let card = UIView(); card.backgroundColor = UIColor.white.withAlphaComponent(0.2); card.layer.cornerRadius = 16
        let v = UIStackView(arrangedSubviews: [titleLabel(value, size: 15), bodyLabel(title, color: UIColor.white.withAlphaComponent(0.9))]); v.axis = .vertical; v.spacing = 4; v.alignment = .center; v.translatesAutoresizingMaskIntoConstraints = false
        (v.arrangedSubviews[0] as? UILabel)?.textColor = .white
        card.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: card.topAnchor, constant: 12), v.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8), v.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8), v.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }

    private func rowItem(_ text: String) -> UIView {
        let button = UIButton(type: .system)
        button.setTitle(text, for: .normal)
        button.setTitleColor(UIColor(hex: "#5B3A1F"), for: .normal)
        button.contentHorizontalAlignment = .left
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    private func menuSection(title: String, rows: [UIView]) -> UIView {
        let titleLabelView = bodyLabel(title, color: UIColor(hex: "#A07A55"))
        titleLabelView.font = .systemFont(ofSize: 12, weight: .bold)
        let card = WhiteCardView()
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 2
        card.embed(stack, padding: 12)
        let wrap = UIStackView(arrangedSubviews: [titleLabelView, card])
        wrap.axis = .vertical
        wrap.spacing = 6
        return wrap
    }
}

enum AppColor {
    static let background = UIColor(hex: "#FAF3E7")
    static let orange = UIColor(hex: "#F5A65B")
}

final class WhiteCardView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.cornerRadius = 20
        layer.borderWidth = 1
        layer.borderColor = UIColor(hex: "#EBD9BF").cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func embed(_ view: UIView, padding: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding)
        ])
    }
}

final class PrimaryButton: UIButton {
    init(title: String, target: Any?, action: Selector) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        backgroundColor = AppColor.orange
        tintColor = .white
        layer.cornerRadius = 16
        heightAnchor.constraint(equalToConstant: 52).isActive = true
        addTarget(target, action: action, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class DiaryCell: UITableViewCell {
    static let reuseIdentifier = "DiaryCell"
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(with entry: DiaryEntry) {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        let card = WhiteCardView(); card.translatesAutoresizingMaskIntoConstraints = false
        let icon = squareIcon(entry.mediaIcon, bg: UIColor(hex: "#FFE6CC"), size: 40, symbol: true)
        let date = bodyLabel(entry.dateText, color: AppColor.orange); date.font = .systemFont(ofSize: 12, weight: .bold)
        let text = bodyLabel(entry.content, color: UIColor(hex: "#5B3A1F")); text.numberOfLines = 3
        let stack = UIStackView(arrangedSubviews: [date, text]); stack.axis = .vertical; stack.spacing = 6
        let row = UIStackView(arrangedSubviews: [icon, stack]); row.axis = .horizontal; row.spacing = 12; row.alignment = .top
        card.embed(row, padding: 14)
        contentView.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
    }
}

final class ChatCell: UITableViewCell {
    static let reuseIdentifier = "ChatCell"
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(with item: ChatMessageItem) {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        let bubble = PaddingLabel()
        bubble.numberOfLines = 0
        bubble.font = .systemFont(ofSize: 13)
        bubble.layer.cornerRadius = 18
        bubble.clipsToBounds = true
        bubble.text = item.content
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.insets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        if item.isMine {
            bubble.backgroundColor = AppColor.orange
            bubble.textColor = .white
        } else if item.isAuto {
            bubble.backgroundColor = UIColor(hex: "#FFF1DC")
            bubble.textColor = UIColor(hex: "#7A5635")
        } else {
            bubble.backgroundColor = .white
            bubble.textColor = UIColor(hex: "#5B3A1F")
            bubble.layer.borderWidth = 1
            bubble.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor
        }
        contentView.addSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.74),
            item.isMine ? bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16) : bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        ])
    }
}

final class PaddingLabel: UILabel {
    var insets = UIEdgeInsets.zero
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

func titleLabel(_ text: String, size: CGFloat) -> UILabel {
    let l = UILabel(); l.text = text; l.font = .systemFont(ofSize: size, weight: .bold); l.textColor = UIColor(hex: "#5B3A1F"); l.numberOfLines = 0; return l
}

func bodyLabel(_ text: String, color: UIColor) -> UILabel {
    let l = UILabel(); l.text = text; l.font = .systemFont(ofSize: 12); l.textColor = color; l.numberOfLines = 0; return l
}

func badge(_ text: String, bg: UIColor) -> UILabel {
    let l = UILabel(); l.text = "  \(text)  "; l.font = .systemFont(ofSize: 10, weight: .semibold); l.textColor = UIColor(hex: "#5B3A1F"); l.backgroundColor = bg; l.layer.cornerRadius = 10; l.clipsToBounds = true; return l
}

func squareIcon(_ symbol: String, bg: UIColor, size: CGFloat = 48, tint: UIColor = UIColor(hex: "#5B3A1F"), symbol useSymbol: Bool = true) -> UIView {
    let wrap = UIView(); wrap.translatesAutoresizingMaskIntoConstraints = false; wrap.backgroundColor = bg; wrap.layer.cornerRadius = 16; wrap.widthAnchor.constraint(equalToConstant: size).isActive = true; wrap.heightAnchor.constraint(equalToConstant: size).isActive = true
    let iv = UIImageView(image: useSymbol ? UIImage(systemName: symbol) : nil); iv.translatesAutoresizingMaskIntoConstraints = false; iv.tintColor = tint; iv.contentMode = .scaleAspectFit
    wrap.addSubview(iv)
    NSLayoutConstraint.activate([
        iv.centerXAnchor.constraint(equalTo: wrap.centerXAnchor), iv.centerYAnchor.constraint(equalTo: wrap.centerYAnchor), iv.widthAnchor.constraint(equalToConstant: size * 0.44), iv.heightAnchor.constraint(equalToConstant: size * 0.44)
    ])
    return wrap
}

func formCard(title: String?, content: UIView) -> UIView {
    let card = WhiteCardView()
    if let title {
        let t = titleLabel(title, size: 13)
        let stack = UIStackView(arrangedSubviews: [t, content])
        stack.axis = .vertical; stack.spacing = 8
        card.embed(stack, padding: 14)
    } else {
        card.embed(content, padding: 14)
    }
    return card
}

func filledField(label: String, value: String) -> UIView {
    let field = UITextField(); field.text = value; field.font = .systemFont(ofSize: 13, weight: .medium); field.textColor = UIColor(hex: "#5B3A1F")
    return filledField(label: label, field: field, placeholder: nil)
}

func filledField(label: String, field: UITextField, placeholder: String?) -> UIView {
    field.placeholder = placeholder
    field.textColor = UIColor(hex: "#5B3A1F")
    field.font = .systemFont(ofSize: 13, weight: .medium)
    return formCard(title: label, content: field)
}

func sectionHeader(_ text: String) -> UILabel {
    let l = UILabel(); l.text = text; l.font = .systemFont(ofSize: 14, weight: .bold); l.textColor = UIColor(hex: "#5B3A1F"); return l
}

func bottomCTA(title: String, action: @escaping () -> Void) -> UIView {
    let wrap = UIView(); wrap.translatesAutoresizingMaskIntoConstraints = false; wrap.backgroundColor = .white; wrap.layer.borderWidth = 1; wrap.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor
    let button = ClosureButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.action = action
    button.setTitle(title, for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
    button.backgroundColor = AppColor.orange
    button.layer.cornerRadius = 16
    wrap.addSubview(button)
    NSLayoutConstraint.activate([
        wrap.heightAnchor.constraint(equalToConstant: 88),
        button.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 16), button.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -16), button.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 12), button.heightAnchor.constraint(equalToConstant: 52)
    ])
    return wrap
}

final class ClosureButton: UIButton {
    var action: (() -> Void)?
    override init(frame: CGRect) { super.init(frame: frame); addTarget(self, action: #selector(tap), for: .touchUpInside) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tap() { action?() }
}

private extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb & 0xFF0000) >> 16) / 255,
            green: CGFloat((rgb & 0x00FF00) >> 8) / 255,
            blue: CGFloat(rgb & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
