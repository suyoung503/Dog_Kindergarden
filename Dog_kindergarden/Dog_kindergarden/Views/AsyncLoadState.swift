import SwiftUI

/// 서버 목록 화면이 공통으로 사용하는 조회 상태.
/// `loaded`는 결과가 비어 있는 정상 응답까지 포함하고, 실패 시 화면의 기존 데이터는 별도로 유지한다.
enum AsyncLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// 최초 조회 중 기존 데이터가 없을 때 사용하는 공통 로딩 화면.
struct AsyncLoadingStateView: View {
    var message = "불러오는 중이에요"

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(Color.brandOrange)
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.brandBrownMid)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}

/// 조회 실패를 빈 목록으로 오인하지 않도록 오류와 재시도 동작을 함께 표시한다.
struct AsyncLoadFailureView: View {
    let message: String
    var compact = false
    let retry: () -> Void

    var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            if !compact {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.brandOrange)
            }
            Text(message)
                .font(.system(size: compact ? 11 : 14, weight: .semibold))
                .foregroundStyle(Color.brandBrown)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("다시 시도")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.brandOrange)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 10 : 0)
        .padding(.horizontal, 16)
        .background(compact ? Color.white : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay {
            if compact {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(Color.brandBeigeBorder, lineWidth: 1)
            }
        }
        .padding(.horizontal, compact ? 20 : 0)
        .padding(.top, compact ? 8 : 100)
    }
}

/// 갱신 중 기존 목록을 가리지 않고 중복 탭을 유도하지 않는 작은 상태 표시.
struct AsyncRefreshIndicator: View {
    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.brandOrange)
            Text("최신 정보를 불러오는 중이에요")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.brandBrownMid)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}
