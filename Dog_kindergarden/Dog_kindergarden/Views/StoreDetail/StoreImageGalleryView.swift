import SwiftUI

struct StoreImageGalleryView: View {
    let imageURLs: [String]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, raw in
                    AsyncImage(url: URL(string: raw)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.55))
                        default:
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(index)
                    .accessibilityLabel("가게 이미지 \(index + 1)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                HStack {
                    Text("\(selectedIndex + 1) / \(imageURLs.count)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("이미지 닫기")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
        }
        .onAppear {
            if !imageURLs.indices.contains(selectedIndex) { selectedIndex = 0 }
        }
    }
}
