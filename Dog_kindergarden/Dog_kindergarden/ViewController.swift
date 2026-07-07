import UIKit

final class ViewController: UIViewController {
    private let dataManager = DataManager()
    private var allStores: [DogCareStore] = []
    private var filteredStores: [DogCareStore] = []

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let searchField = UITextField()
    private let chipsScrollView = UIScrollView()
    private let chipsStack = UIStackView()

    private let mapCard = UIView()
    private let mapGrid = UIView()

    private let recentTitle = UILabel()
    private let recentScrollView = UIScrollView()
    private let recentStack = UIStackView()

    private let floatingContainer = UIStackView()
    private let floatingMainButton = UIButton(type: .system)
    private var isFloatingOpen = false

    private let provinces = [
        "서울", "경기", "강원", "충북", "충남", "경북", "경남", "전북", "전남", "제주"
    ]


    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
    }

    private func setupUI() {
        view.backgroundColor = UIColor(hex: "#FAF3E7")
        title = "맡겨멍"
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.hidesBackButton = true

        configureScroll()
        configureHeader()
        configureSearch()
        configureChips()
        configureMapCard()
        configureRecent()
        configureFloatingMenu()
    }
    private func configureScroll() {

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentInsetAdjustmentBehavior = .never

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.alignment = .fill
        contentStack.distribution = .fill

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([

            // ScrollView
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // ContentStack
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -100),

            // 핵심
            contentStack.widthAnchor.constraint(
                equalTo: view.widthAnchor,
                constant: -32
            )
        ])
    }
    private func configureHeader() {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let profileButton = UIButton(type: .system)
        profileButton.translatesAutoresizingMaskIntoConstraints = false
        profileButton.addTarget(self, action: #selector(openMyLikeScreen), for: .touchUpInside)

        let avatar = UILabel()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.text = "U"
        avatar.textAlignment = .center
        avatar.font = .systemFont(ofSize: 20)
        avatar.backgroundColor = UIColor(hex: "#FFE6CC")
        avatar.layer.cornerRadius = 20
        avatar.layer.borderWidth = 2
        avatar.layer.borderColor = UIColor(hex: "#F5A65B").cgColor
        avatar.clipsToBounds = true

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = "상민님 "
        nameLabel.font = .systemFont(ofSize: 16, weight: .bold)
        nameLabel.textColor = UIColor(hex: "#5B3A1F")

        let subLabel = UILabel()
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.text = "오늘도 멍멍이 케어를 찾아볼까요?"
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = UIColor(hex: "#A07A55")

        let textStack = UIStackView(arrangedSubviews: [nameLabel, subLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        profileButton.addSubview(avatar)
        profileButton.addSubview(textStack)

        let bell = UIButton(type: .system)
        bell.translatesAutoresizingMaskIntoConstraints = false
        bell.setImage(UIImage(systemName: "bell"), for: .normal)
        bell.tintColor = UIColor(hex: "#5B3A1F")
        bell.backgroundColor = .white
        bell.layer.cornerRadius = 20
        bell.layer.borderWidth = 1
        bell.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor

        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = UIColor(hex: "#F5A65B")
        dot.layer.cornerRadius = 4
        bell.addSubview(dot)

        header.addSubview(profileButton)
        header.addSubview(bell)

        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 50),

            profileButton.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            profileButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            profileButton.heightAnchor.constraint(equalToConstant: 46),
            profileButton.widthAnchor.constraint(equalToConstant: 240),

            avatar.leadingAnchor.constraint(equalTo: profileButton.leadingAnchor),
            avatar.centerYAnchor.constraint(equalTo: profileButton.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),

            textStack.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: profileButton.centerYAnchor),

            bell.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            bell.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            bell.widthAnchor.constraint(equalToConstant: 40),
            bell.heightAnchor.constraint(equalToConstant: 40),

            dot.topAnchor.constraint(equalTo: bell.topAnchor, constant: 10),
            dot.trailingAnchor.constraint(equalTo: bell.trailingAnchor, constant: -10),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8)
        ])

        contentStack.addArrangedSubview(header)
    }

    private func configureSearch() {
        let searchWrap = UIView()
        searchWrap.translatesAutoresizingMaskIntoConstraints = false
        searchWrap.backgroundColor = .white
        searchWrap.layer.cornerRadius = 14
        searchWrap.layer.borderWidth = 1
        searchWrap.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor(hex: "#C9A27A")

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "지역, 가게 이름으로 검색"
        searchField.textColor = UIColor(hex: "#5B3A1F")
        searchField.font = .systemFont(ofSize: 13)
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)

        searchWrap.addSubview(icon)
        searchWrap.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchWrap.heightAnchor.constraint(equalToConstant: 48),
            icon.leadingAnchor.constraint(equalTo: searchWrap.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: searchWrap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchWrap.trailingAnchor, constant: -12),
            searchField.centerYAnchor.constraint(equalTo: searchWrap.centerYAnchor)
        ])

        contentStack.addArrangedSubview(searchWrap)
    }

    private func configureChips() {
        chipsScrollView.translatesAutoresizingMaskIntoConstraints = false
        chipsScrollView.showsHorizontalScrollIndicator = false
        chipsStack.translatesAutoresizingMaskIntoConstraints = false
        chipsStack.axis = .horizontal
        chipsStack.spacing = 8

        chipsScrollView.addSubview(chipsStack)
        NSLayoutConstraint.activate([
            chipsScrollView.heightAnchor.constraint(equalToConstant: 36),
            chipsStack.topAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.topAnchor),
            chipsStack.bottomAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.bottomAnchor),
            chipsStack.leadingAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.leadingAnchor),
            chipsStack.trailingAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.trailingAnchor),
            chipsStack.heightAnchor.constraint(equalTo: chipsScrollView.frameLayoutGuide.heightAnchor)
        ])

        [
            (" 호텔", "#FFE6CC"),
            (" 유치원", "#BFE9D5"),
            (" 미용", "#FFF1A8"),
            (" 산책", "#C7E6F5")
        ].forEach { item in
            let btn = chipButton(title: item.0, color: UIColor(hex: item.1))
            chipsStack.addArrangedSubview(btn)
        }

        contentStack.addArrangedSubview(chipsScrollView)
    }

    private func configureMapCard() {
        let titleLabel = UILabel()
        titleLabel.text = "지역을 선택해주세요"
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = UIColor(hex: "#5B3A1F")

        let subLabel = UILabel()
        subLabel.text = "도를 누르면 시·군으로 들어가요"
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = UIColor(hex: "#A07A55")

        let titleWrap = UIStackView(arrangedSubviews: [titleLabel, subLabel])
        titleWrap.axis = .vertical
        titleWrap.spacing = 2
        contentStack.addArrangedSubview(titleWrap)

        mapCard.translatesAutoresizingMaskIntoConstraints = false
        mapCard.backgroundColor = .white
        mapCard.layer.cornerRadius = 22
        mapCard.layer.borderWidth = 1
        mapCard.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor

        mapGrid.translatesAutoresizingMaskIntoConstraints = false
        mapCard.addSubview(mapGrid)

        NSLayoutConstraint.activate([
            mapCard.heightAnchor.constraint(equalToConstant: 290),
            mapGrid.topAnchor.constraint(equalTo: mapCard.topAnchor, constant: 14),
            mapGrid.leadingAnchor.constraint(equalTo: mapCard.leadingAnchor, constant: 14),
            mapGrid.trailingAnchor.constraint(equalTo: mapCard.trailingAnchor, constant: -14),
            mapGrid.bottomAnchor.constraint(equalTo: mapCard.bottomAnchor, constant: -14)
        ])

        drawProvinceButtons()
        contentStack.addArrangedSubview(mapCard)
    }

    private func drawProvinceButtons() {
        let rows: [[String]] = [
            ["서울", "경기", "강원"],
            ["충북", "충남", "경북"],
            ["전북", "전남", "경남"],
            ["제주"]
        ]

        let v = UIStackView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.axis = .vertical
        v.spacing = 10

        for row in rows {
            let h = UIStackView()
            h.axis = .horizontal
            h.distribution = .fillEqually
            h.spacing = 10
            for name in row {
                let b = UIButton(type: .system)
                b.setTitle(name, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
                b.setTitleColor(name == "경기" ? .white : UIColor(hex: "#5B3A1F"), for: .normal)
                b.backgroundColor = name == "경기" ? UIColor(hex: "#F5A65B") : UIColor(hex: "#FFE6CC")
                b.layer.cornerRadius = 14
                b.heightAnchor.constraint(equalToConstant: 50).isActive = true
                b.addTarget(self, action: #selector(selectProvince), for: .touchUpInside)
                h.addArrangedSubview(b)
            }
            if row.count == 1 {
                h.addArrangedSubview(UIView())
                h.addArrangedSubview(UIView())
            } else if row.count == 2 {
                h.addArrangedSubview(UIView())
            }
            v.addArrangedSubview(h)
        }

        mapGrid.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: mapGrid.topAnchor, constant: 4),
            v.leadingAnchor.constraint(equalTo: mapGrid.leadingAnchor, constant: 4),
            v.trailingAnchor.constraint(equalTo: mapGrid.trailingAnchor, constant: -4)
        ])
    }

    private func configureRecent() {
        recentTitle.text = "최근 본 케어"
        recentTitle.font = .systemFont(ofSize: 15, weight: .bold)
        recentTitle.textColor = UIColor(hex: "#5B3A1F")
        contentStack.addArrangedSubview(recentTitle)

        recentScrollView.translatesAutoresizingMaskIntoConstraints = false
        recentScrollView.showsHorizontalScrollIndicator = false
        recentStack.translatesAutoresizingMaskIntoConstraints = false
        recentStack.axis = .horizontal
        recentStack.spacing = 10
        recentScrollView.addSubview(recentStack)

        NSLayoutConstraint.activate([
            recentScrollView.heightAnchor.constraint(equalToConstant: 160),
            recentStack.topAnchor.constraint(equalTo: recentScrollView.contentLayoutGuide.topAnchor),
            recentStack.bottomAnchor.constraint(equalTo: recentScrollView.contentLayoutGuide.bottomAnchor),
            recentStack.leadingAnchor.constraint(equalTo: recentScrollView.contentLayoutGuide.leadingAnchor),
            recentStack.trailingAnchor.constraint(equalTo: recentScrollView.contentLayoutGuide.trailingAnchor),
            recentStack.heightAnchor.constraint(equalTo: recentScrollView.frameLayoutGuide.heightAnchor)
        ])

        contentStack.addArrangedSubview(recentScrollView)
    }

    private func configureFloatingMenu() {
        floatingContainer.translatesAutoresizingMaskIntoConstraints = false
        floatingContainer.axis = .vertical
        floatingContainer.alignment = .trailing
        floatingContainer.spacing = 8
        view.addSubview(floatingContainer)

        NSLayoutConstraint.activate([
            floatingContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            floatingContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        [
            ("강아지 프로필", "person.fill", #selector(openProfile)),
            ("채팅", "message.fill", #selector(openChat)),
            ("예약 내역", "calendar", #selector(openBooking))
        ].forEach { item in
            let b = UIButton(type: .system)

            var config = UIButton.Configuration.plain()

            config.title = item.0
            config.image = UIImage(systemName: item.1)

            // 이미지와 텍스트 사이 간격
            config.imagePadding = 8

            // 버튼 내부 여백
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 8,
                leading: 12,
                bottom: 8,
                trailing: 12
            )

            b.configuration = config

            b.tintColor = UIColor(hex: "#5B3A1F")
            b.backgroundColor = .white
            b.layer.cornerRadius = 18
            b.layer.borderWidth = 2
            b.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor
            b.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)

            b.alpha = 0
            b.isHidden = true
            b.addTarget(self, action: item.2, for: .touchUpInside)

            floatingContainer.addArrangedSubview(b)
        }

        floatingMainButton.translatesAutoresizingMaskIntoConstraints = false
        floatingMainButton.setTitle("+", for: .normal)
        floatingMainButton.titleLabel?.font = .systemFont(ofSize: 24)
        floatingMainButton.tintColor = .white
        floatingMainButton.backgroundColor = UIColor(hex: "#F5A65B")
        floatingMainButton.layer.cornerRadius = 28
        floatingMainButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
        floatingMainButton.heightAnchor.constraint(equalToConstant: 56).isActive = true
        floatingMainButton.addTarget(self, action: #selector(toggleFloating), for: .touchUpInside)
        floatingContainer.addArrangedSubview(floatingMainButton)
    }

    private func loadData() {
        allStores = dataManager.loadStores()
        filteredStores = allStores

        Task { [weak self] in
            do {
                let apiStores = try await APIClient.shared.fetchStores()
                guard !apiStores.isEmpty else { return }
                await MainActor.run {
                    self?.allStores = apiStores
                    self?.filteredStores = apiStores
                    self?.reloadRecentStores()
                }
            } catch {
                await MainActor.run {
                    self?.reloadRecentStores()
                }
            }
        }

        reloadRecentStores()
    }

    private func reloadRecentStores() {
        recentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for store in filteredStores.prefix(6) {
            recentStack.addArrangedSubview(recentCard(store))
        }
    }

    private func recentCard(_ store: DogCareStore) -> UIView {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .white
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor
        button.widthAnchor.constraint(equalToConstant: 146).isActive = true
        button.addTarget(self, action: #selector(openStoreFromCard(_:)), for: .touchUpInside)
        button.accessibilityIdentifier = store.id

        let emoji = UILabel()
        emoji.text = ""
        emoji.textAlignment = .center
        emoji.font = .systemFont(ofSize: 28)
        emoji.backgroundColor = UIColor(hex: "#FFE6CC")
        emoji.layer.cornerRadius = 10
        emoji.clipsToBounds = true
        emoji.translatesAutoresizingMaskIntoConstraints = false

        let name = UILabel()
        name.text = store.name
        name.font = .systemFont(ofSize: 12, weight: .bold)
        name.textColor = UIColor(hex: "#5B3A1F")
        name.numberOfLines = 2

        let area = UILabel()
        area.text = store.displayAddress
        area.font = .systemFont(ofSize: 10)
        area.textColor = UIColor(hex: "#A07A55")
        area.numberOfLines = 2

        let rating = UILabel()
        rating.text = "평점 4.8"
        rating.font = .systemFont(ofSize: 10, weight: .bold)
        rating.textColor = UIColor(hex: "#F5A65B")

        let stack = UIStackView(arrangedSubviews: [name, area, rating])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(emoji)
        button.addSubview(stack)

        NSLayoutConstraint.activate([
            emoji.topAnchor.constraint(equalTo: button.topAnchor, constant: 10),
            emoji.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
            emoji.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10),
            emoji.heightAnchor.constraint(equalToConstant: 60),

            stack.topAnchor.constraint(equalTo: emoji.bottomAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10)
        ])

        return button
    }

    private func chipButton(title: String, color: UIColor) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle("  \(title)  ", for: .normal)
        b.setTitleColor(UIColor(hex: "#5B3A1F"), for: .normal)
        b.backgroundColor = color
        b.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        b.layer.cornerRadius = 18
        
        return b
    }

    @objc private func searchChanged() {
        let keyword = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            filteredStores = allStores
        } else {
            filteredStores = allStores.filter {
                $0.name.localizedCaseInsensitiveContains(keyword) ||
                $0.displayAddress.localizedCaseInsensitiveContains(keyword)
            }
        }
        reloadRecentStores()
    }

    @objc private func selectProvince(_ sender: UIButton) {
        guard let name = sender.currentTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
        searchField.text = name
        searchChanged()
    }

    @objc private func toggleFloating() {
        isFloatingOpen.toggle()
        for view in floatingContainer.arrangedSubviews.dropLast() {
            view.isHidden = !isFloatingOpen
            UIView.animate(withDuration: 0.2) {
                view.alpha = self.isFloatingOpen ? 1 : 0
            }
        }
    }

    @objc private func openStoreFromCard(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier,
              let store = filteredStores.first(where: { $0.id == id }) ?? allStores.first else { return }
        let detail = StoreDetailViewController(store: store)
        navigationController?.pushViewController(detail, animated: true)
    }

    @objc private func openProfile() {
        let context = ReservationFlowContext(reservationId: 1, roomId: 1, storeId: Int(allStores.first?.id ?? "1") ?? 1)
        navigationController?.pushViewController(PetProfileViewController(store: allStores.first ?? DataManager().loadStores().first!, pet: MockData.pet, context: context), animated: true)
    }

    @objc private func openChat() {
        let store = allStores.first ?? DataManager().loadStores().first!
        let context = ReservationFlowContext(reservationId: 1, roomId: 1, storeId: Int(store.id) ?? 1)
        navigationController?.pushViewController(ChatListViewController(), animated: true)
    }

    @objc private func openBooking() {
        guard let store = allStores.first ?? DataManager().loadStores().first else { return }
        navigationController?.pushViewController(ReservationViewController(store: store), animated: true)
    }

    @objc private func openMyLikeScreen() {
        navigationController?.pushViewController(MyPageViewController(store: allStores.first), animated: true)
    }
}

final class StoreDetailViewController: UIViewController {
    private let store: DogCareStore

    init(store: DogCareStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: "#FAF3E7")
        title = "가게 상세"
        buildUI()
    }

    private func buildUI() {
        let scroll = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20)
        ])

        let hero = UIView()
        hero.backgroundColor = UIColor(hex: "#FFE6CC")
        hero.layer.cornerRadius = 24
        hero.heightAnchor.constraint(equalToConstant: 200).isActive = true

        let icon = UILabel()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.text = ""
        icon.font = .systemFont(ofSize: 64)
        hero.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: hero.centerYAnchor)
        ])

        let titleCard = UIView()
        titleCard.backgroundColor = .white
        titleCard.layer.cornerRadius = 20
        titleCard.layer.borderWidth = 1
        titleCard.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor

        let name = UILabel()
        name.text = store.name
        name.font = .systemFont(ofSize: 18, weight: .bold)
        name.textColor = UIColor(hex: "#5B3A1F")

        let address = UILabel()
        address.text = store.displayAddress
        address.font = .systemFont(ofSize: 12)
        address.textColor = UIColor(hex: "#A07A55")
        address.numberOfLines = 0

        let chips = UIStackView(arrangedSubviews: [
            smallTag("호텔", "#FFE6CC"), smallTag("유치원", "#BFE9D5"), smallTag("산책", "#C7E6F5")
        ])
        chips.axis = .horizontal
        chips.spacing = 6

        let info = UILabel()
        info.text = " 4.9  ·  08:00 ~ 22:00  ·  031-000-0000"
        info.font = .systemFont(ofSize: 12, weight: .semibold)
        info.textColor = UIColor(hex: "#F5A65B")

        let inner = UIStackView(arrangedSubviews: [name, address, chips, info])
        inner.axis = .vertical
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        titleCard.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: titleCard.topAnchor, constant: 14),
            inner.leadingAnchor.constraint(equalTo: titleCard.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: titleCard.trailingAnchor, constant: -14),
            inner.bottomAnchor.constraint(equalTo: titleCard.bottomAnchor, constant: -14)
        ])

        let reserve = UIButton(type: .system)
        reserve.setTitle("예약하기", for: .normal)
        reserve.setImage(UIImage(systemName: "checkmark"), for: .normal)
        reserve.semanticContentAttribute = .forceRightToLeft
        reserve.tintColor = .white
        reserve.backgroundColor = UIColor(hex: "#F5A65B")
        reserve.layer.cornerRadius = 16
        reserve.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        reserve.heightAnchor.constraint(equalToConstant: 54).isActive = true
        reserve.addTarget(self, action: #selector(openReservation), for: .touchUpInside)

        stack.addArrangedSubview(hero)
        stack.addArrangedSubview(titleCard)
        stack.addArrangedSubview(sectionCard(title: "가게 소개", body: "10년 경력 전문 핸들러가 24시간 케어하는 프리미엄 펫호텔이에요. CCTV 공유로 안심하고 맡겨주세요."))
        stack.addArrangedSubview(sectionCard(title: "주의사항", body: "• 광견병 접종 증명서 필수\n• 공격성 있는 경우 사전 상담\n• 사료는 직접 준비"))
        stack.addArrangedSubview(reserve)
    }

    private func sectionCard(title: String, body: String) -> UIView {
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#EBD9BF").cgColor

        let t = UILabel()
        t.text = title
        t.font = .systemFont(ofSize: 14, weight: .bold)
        t.textColor = UIColor(hex: "#5B3A1F")

        let b = UILabel()
        b.text = body
        b.numberOfLines = 0
        b.font = .systemFont(ofSize: 12)
        b.textColor = UIColor(hex: "#7A5635")

        let v = UIStackView(arrangedSubviews: [t, b])
        v.axis = .vertical
        v.spacing = 8
        v.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(v)

        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            v.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            v.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            v.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        return card
    }

    private func smallTag(_ text: String, _ hex: String) -> UIView {
        let l = UILabel()
        l.text = "  \(text)  "
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = UIColor(hex: "#5B3A1F")
        l.backgroundColor = UIColor(hex: hex)
        l.layer.cornerRadius = 10
        l.clipsToBounds = true
        return l
    }

    @objc private func openReservation() {
        navigationController?.pushViewController(ReservationViewController(store: store), animated: true)
    }
}

private extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
