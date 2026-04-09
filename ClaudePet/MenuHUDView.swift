import SwiftUI

// MARK: - 메뉴 HUD 메인 뷰

/// 우클릭으로 열리는 드롭다운 HUD 메뉴.
struct MenuHUDView: View {

    var onClose: () -> Void
    var onFeed:  (() -> Void)?   // 밥주기 콜백 (ClaudePetApp 에서 주입)

    // 별도 NSHostingView 에 있으므로 @ObservedObject 대신
    // @State + NotificationCenter 방식으로 안정적으로 갱신합니다.
    @State private var hunger:      Double = HungerManager.shared.hunger
    @State private var isHungry:    Bool   = HungerManager.shared.isHungry
    @State private var typingCount: Int    = TypingCounter.shared.count

    // MARK: - 계산된 값

    private var hungerPercent: Double {
        max(0, min(1, hunger / PetConfig.hungerMax))
    }

    private var canFeed: Bool {
        typingCount >= PetConfig.feedTypingCost && hunger < PetConfig.hungerMax
    }

    private var feedStatusText: String {
        if hunger >= PetConfig.hungerMax { return "배부름" }
        if typingCount < PetConfig.feedTypingCost {
            return "타이핑 \(PetConfig.feedTypingCost - typingCount)개 필요"
        }
        return "타이핑 \(PetConfig.feedTypingCost)개"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── 헤더 ────────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.00, green: 0.78, blue: 0.32),
                                Color(red: 0.98, green: 0.48, blue: 0.20)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("클로드")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                // 닫기 버튼 (X)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                        .frame(width: 18, height: 18)
                        .background(
                            Circle().fill(Color(white: 0.25, opacity: 0.6))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, 8)

            // ── 구분선 ───────────────────────────────────────────────────────
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            // ── 배고픔 수치 표시 ─────────────────────────────────────────────
            VStack(spacing: 5) {
                HStack {
                    Text("배고픔")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(white: 0.55))
                    Spacer()
                    Text("\(Int(hunger)) / \(Int(PetConfig.hungerMax))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(isHungry
                            ? Color(red: 1.0, green: 0.45, blue: 0.25)
                            : Color(white: 0.55))
                }

                // 배고픔 바
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(white: 0.18))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(hungerBarColor)
                            .frame(width: geo.size.width * hungerPercent, height: 5)
                            .animation(.easeOut(duration: 0.3), value: hungerPercent)
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 7)

            // ── 구분선 ───────────────────────────────────────────────────────
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            // ── 메뉴 항목 ────────────────────────────────────────────────────
            VStack(spacing: 3) {
                MenuHUDRow(
                    icon:    "fork.knife",
                    iconBg:  Color(red: 1.00, green: 0.65, blue: 0.25),
                    title:   "밥주기",
                    status:  feedStatusText,
                    action:  canFeed ? { onFeed?() } : nil
                )
                MenuHUDRow(
                    icon:    "heart.fill",
                    iconBg:  Color(red: 1.00, green: 0.38, blue: 0.52),
                    title:   "호감도",
                    status:  "준비 중",
                    action:  nil
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)

            // ── [DEBUG] 디버그 섹션 — 출시 전 삭제 예정 ───────────────────────
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            VStack(spacing: 4) {
                // [DEBUG] 섹션 레이블
                HStack {
                    Image(systemName: "ant.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.7))
                    Text("DEBUG")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.7))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                // [DEBUG] 포만도 -10 버튼
                MenuHUDRow(
                    icon:    "minus.circle.fill",
                    iconBg:  Color(red: 0.9, green: 0.3, blue: 0.9),
                    title:   "포만도 -10",
                    status:  "\(Int(hunger))",
                    action:  {
                        HungerManager.shared.debugDecreaseHunger(by: 10)
                    }
                )

                // [DEBUG] 타이핑 카운터 +100 버튼
                MenuHUDRow(
                    icon:    "plus.circle.fill",
                    iconBg:  Color(red: 0.2, green: 0.6, blue: 1.0),
                    title:   "타이핑 +100",
                    status:  "\(typingCount)",
                    action:  {
                        TypingCounter.shared.debugAdd(100)
                    }
                )
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 8)
            // ── [DEBUG] 섹션 끝 ─────────────────────────────────────────────

            // ── 하단 힌트 텍스트 ─────────────────────────────────────────────
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            Text("더 많은 기능이 곧 추가될 예정이에요")
                .font(.system(size: 9.5))
                .foregroundColor(Color(white: 0.38))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
        .frame(width: 188)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.52))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.55), radius: 18, x: 0, y: 5)
        // 배고픔 수치 변경 알림 수신 (별도 NSHostingView 에서 안정적 갱신)
        .onReceive(NotificationCenter.default.publisher(for: HungerManager.didChange)) { _ in
            hunger   = HungerManager.shared.hunger
            isHungry = HungerManager.shared.isHungry
        }
        // 타이핑 카운터 변경 알림 수신
        .onReceive(NotificationCenter.default.publisher(for: TypingCounter.didChange)) { _ in
            typingCount = TypingCounter.shared.count
        }
    }

    // MARK: - 배고픔 바 색상

    private var hungerBarColor: Color {
        if hungerPercent > 0.5 {
            return Color(red: 0.30, green: 0.85, blue: 0.45)   // 초록
        } else if hungerPercent > 0.2 {
            return Color(red: 1.00, green: 0.75, blue: 0.20)   // 노랑
        } else {
            return Color(red: 1.00, green: 0.38, blue: 0.25)   // 빨강
        }
    }
}

// MARK: - 메뉴 행

struct MenuHUDRow: View {
    let icon:   String
    let iconBg: Color
    let title:  String
    let status: String
    let action: (() -> Void)?

    @State private var isHovered = false

    var isEnabled: Bool { action != nil }

    var body: some View {
        HStack(spacing: 9) {
            // 아이콘 배지
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(iconBg.opacity(isEnabled ? 0.28 : 0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconBg.opacity(isEnabled ? 1.0 : 0.45))
            }

            // 레이블
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isEnabled ? .white : Color(white: 0.55))

            Spacer()

            // 상태 배지
            Text(status)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(Color(white: 0.42))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(white: 0.22, opacity: 0.65))
                )
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isHovered && isEnabled ? Color.white.opacity(0.08) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onHover { isHovered = $0 }
        .onTapGesture { if isEnabled { action?() } }
    }
}
