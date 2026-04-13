import SwiftUI

// MARK: - 메뉴 HUD 메인 뷰

/// 우클릭으로 열리는 드롭다운 HUD 메뉴.
struct MenuHUDView: View {

    var onClose: () -> Void
    var onFeed:  (() -> Void)?   // 밥주기 콜백 (ClaudePetApp 에서 주입)

    // 배율 — 패널 재생성 시 SettingsManager 에서 최신값을 읽습니다.
    private let s: CGFloat = SettingsManager.shared.uiScale

    // 별도 NSHostingView 에 있으므로 @ObservedObject 대신
    // @State + NotificationCenter 방식으로 안정적으로 갱신합니다.
    @State private var hunger:      Double = HungerManager.shared.hunger
    @State private var isHungry:    Bool   = HungerManager.shared.isHungry
    @State private var typingCount: Int    = TypingCounter.shared.count

    // 호감도
    @State private var affinityLevel:      Int    = AffinityManager.shared.level
    @State private var affinityCurrentExp: Int    = AffinityManager.shared.currentExp
    @State private var affinityRequiredExp: Int   = AffinityManager.shared.requiredExp
    @State private var affinityProgress:   Double = AffinityManager.shared.levelProgress


    // MARK: - 계산된 값

    private var hungerPercent: Double {
        max(0, min(1, hunger / PetConfig.hungerMax))
    }

    private var canFeed: Bool {
        typingCount >= PetConfig.feedTypingCost &&
        hunger + PetConfig.feedHungerRestore <= PetConfig.hungerMax
    }

    private var feedStatusText: String {
        if hunger + PetConfig.feedHungerRestore > PetConfig.hungerMax { return "배부름" }
        if typingCount < PetConfig.feedTypingCost {
            return "타이핑 \(PetConfig.feedTypingCost - typingCount)개 필요"
        }
        return "타이핑 \(PetConfig.feedTypingCost)개"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── 닫기 버튼 ────────────────────────────────────────────────────
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9 * s, weight: .bold))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 18 * s, height: 18 * s)
                        .background(
                            Circle().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 10 * s)
            .padding(.top,         8  * s)
            .padding(.bottom,      2  * s)

            // ── 호감도 게이지 ────────────────────────────────────────────────
            VStack(spacing: 5 * s) {
                HStack(alignment: .firstTextBaseline, spacing: 4 * s) {
                    Text("호감도")
                        .font(.system(size: 10 * s, weight: .medium))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    Text("Lv.\(affinityLevel)")
                        .font(.system(size: 10 * s, weight: .bold))
                        .foregroundColor(affinityLevelColor)
                    Spacer()
                    if affinityLevel >= PetConfig.affinityMaxLevel {
                        Text("MAX")
                            .font(.system(size: 10 * s, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.80, blue: 0.20))
                    } else {
                        Text("\(affinityCurrentExp) / \(affinityRequiredExp)")
                            .font(.system(size: 10 * s, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                }

                // 호감도 바
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3 * s)
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: 5 * s)
                        RoundedRectangle(cornerRadius: 3 * s)
                            .fill(Color(red: 1.00, green: 0.38, blue: 0.52))
                            .frame(
                                width: geo.size.width * min(1.0, max(0.0, affinityProgress)),
                                height: 5 * s
                            )
                            .animation(.easeOut(duration: 0.4), value: affinityProgress)
                    }
                }
                .frame(height: 5 * s)
            }
            .padding(.horizontal, 12 * s)
            .padding(.top,         9  * s)
            .padding(.bottom,      7  * s)

            // ── 구분선 ───────────────────────────────────────────────────────
            Divider()
                .padding(.horizontal, 10 * s)

            // ── 배고픔 수치 표시 ─────────────────────────────────────────────
            VStack(spacing: 5 * s) {
                HStack {
                    Text("배고픔")
                        .font(.system(size: 10 * s, weight: .medium))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    InlineFeedButton(
                        canFeed:    canFeed,
                        tooltip:    feedStatusText,
                        scale:      s,
                        action:     { onFeed?() }
                    )
                    Spacer()
                    Text("\(Int(hunger)) / \(Int(PetConfig.hungerMax))")
                        .font(.system(size: 10 * s, weight: .medium, design: .monospaced))
                        .foregroundColor(isHungry
                            ? Color(red: 1.0, green: 0.45, blue: 0.25)
                            : Color(nsColor: .secondaryLabelColor))
                }

                // 배고픔 바
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3 * s)
                            .fill(Color(nsColor: .separatorColor))
                            .frame(height: 5 * s)
                        RoundedRectangle(cornerRadius: 3 * s)
                            .fill(hungerBarColor)
                            .frame(width: geo.size.width * hungerPercent, height: 5 * s)
                            .animation(.easeOut(duration: 0.3), value: hungerPercent)
                    }
                }
                .frame(height: 5 * s)
            }
            .padding(.horizontal, 12 * s)
            .padding(.top,         9  * s)
            .padding(.bottom,      7  * s)

            // ── [DEBUG] 디버그 섹션 — PetConfig.debugEnabled 로 제어 ───────────
            if PetConfig.debugEnabled {
                Divider()
                    .padding(.horizontal, 10 * s)

                VStack(spacing: 4 * s) {
                    // [DEBUG] 섹션 레이블
                    HStack {
                        Image(systemName: "ant.fill")
                            .font(.system(size: 9 * s))
                            .foregroundColor(Color(nsColor: .systemOrange).opacity(0.75))
                        Text("DEBUG")
                            .font(.system(size: 9 * s, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(nsColor: .systemOrange).opacity(0.75))
                        Spacer()
                    }
                    .padding(.horizontal, 12 * s)
                    .padding(.top,         6  * s)

                    // [DEBUG] 포만도 -10 버튼
                    MenuHUDRow(
                        icon:    "minus.circle.fill",
                        iconBg:  Color(red: 0.9, green: 0.3, blue: 0.9),
                        title:   "포만도 -10",
                        status:  "\(Int(hunger))",
                        scale:   s,
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
                        scale:   s,
                        action:  {
                            TypingCounter.shared.debugAdd(100)
                        }
                    )

                    // [DEBUG] 레벨 +1 버튼
                    MenuHUDRow(
                        icon:    "chevron.up.circle.fill",
                        iconBg:  Color(red: 0.4, green: 0.8, blue: 0.4),
                        title:   "레벨 +1",
                        status:  "Lv.\(affinityLevel)",
                        scale:   s,
                        action:  affinityLevel < PetConfig.affinityMaxLevel ? {
                            AffinityManager.shared.debugAddOneLevel()
                        } : nil
                    )

                    // [DEBUG] 레벨 초기화 버튼
                    MenuHUDRow(
                        icon:    "arrow.counterclockwise.circle.fill",
                        iconBg:  Color(red: 1.0, green: 0.4, blue: 0.3),
                        title:   "레벨 초기화",
                        status:  "Lv.\(affinityLevel)",
                        scale:   s,
                        action:  {
                            AffinityManager.shared.debugResetLevel()
                        }
                    )
                    .padding(.bottom, 2 * s)
                }
                .padding(.horizontal, 8 * s)
            }
            // ── [DEBUG] 섹션 끝 ─────────────────────────────────────────────

            // ── 하단 아이콘 바 ───────────────────────────────────────────────
            Divider()
                .padding(.horizontal, 10 * s)

            HStack(spacing: 4 * s) {
                Spacer()
                HUDIconButton(
                    systemName: "arrow.clockwise.circle",
                    tooltip:    "업데이트 확인\n현재 버전: v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")",
                    scale:      s,
                    action: {
                        SparkleManager.shared.checkForUpdates()
                    }
                )
                HUDIconButton(
                    systemName: "gearshape",
                    tooltip:    "설정",
                    scale:      s,
                    action: {
                        NotificationCenter.default.post(name: .claudePetOpenSettings, object: nil)
                    }
                )
            }
            .padding(.horizontal, 8 * s)
            .padding(.vertical,   6 * s)
        }
        .frame(width: 188 * s)
        // blur / material 은 NSVisualEffectView(content view)가 담당하므로
        // 여기서는 색조 오버레이와 테두리선만 추가합니다.
        .background(
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.20))
                .overlay(
                    Rectangle()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
        )
        .clipShape(Rectangle())
        // shadow 는 panel.hasShadow = true 로 시스템이 처리
        // 배고픔 수치 변경 알림 수신 (별도 NSHostingView 에서 안정적 갱신)
        .onReceive(NotificationCenter.default.publisher(for: HungerManager.didChange)) { _ in
            hunger   = HungerManager.shared.hunger
            isHungry = HungerManager.shared.isHungry
        }
        // 타이핑 카운터 변경 알림 수신
        .onReceive(NotificationCenter.default.publisher(for: TypingCounter.didChange)) { _ in
            typingCount = TypingCounter.shared.count
        }
        // 호감도 변경 알림 수신
        .onReceive(NotificationCenter.default.publisher(for: AffinityManager.didChange)) { _ in
            affinityLevel       = AffinityManager.shared.level
            affinityCurrentExp  = AffinityManager.shared.currentExp
            affinityRequiredExp = AffinityManager.shared.requiredExp
            affinityProgress    = AffinityManager.shared.levelProgress
        }
    }

    // MARK: - 호감도 레벨 색상 (레벨 구간별)

    private var affinityLevelColor: Color {
        switch affinityLevel {
        case 1..<10:   return Color(red: 0.70, green: 0.70, blue: 0.75)   // 회색 (초반)
        case 10..<30:  return Color(red: 0.30, green: 0.75, blue: 1.00)   // 하늘색
        case 30..<60:  return Color(red: 0.50, green: 0.90, blue: 0.50)   // 초록
        case 60..<90:  return Color(red: 1.00, green: 0.75, blue: 0.20)   // 골드
        default:       return Color(red: 1.00, green: 0.45, blue: 0.80)   // 핑크 (90+)
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
    let icon:            String?
    let iconBg:          Color
    let customImageName: String?
    let title:           String
    let status:          String
    let scale:           CGFloat   // uiScale
    let action:          (() -> Void)?

    init(icon: String? = nil,
         iconBg: Color = .clear,
         customImageName: String? = nil,
         title: String,
         status: String,
         scale: CGFloat = 1.0,
         action: (() -> Void)?) {
        self.icon            = icon
        self.iconBg          = iconBg
        self.customImageName = customImageName
        self.title           = title
        self.status          = status
        self.scale           = scale
        self.action          = action
    }

    @State private var isHovered = false

    var isEnabled: Bool { action != nil }

    private var s: CGFloat { scale }

    var body: some View {
        HStack(spacing: 9 * s) {
            // 아이콘
            if let imageName = customImageName {
                ZStack {
                    RoundedRectangle(cornerRadius: 7 * s)
                        .fill(iconBg.opacity(isEnabled ? 0.28 : 0.14))
                        .frame(width: 28 * s, height: 28 * s)
                    Image(imageName)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 32 * s, height: 32 * s)
                        .opacity(isEnabled ? 1.0 : 0.4)
                }
            } else if let symbolName = icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 7 * s)
                        .fill(iconBg.opacity(isEnabled ? 0.28 : 0.14))
                        .frame(width: 28 * s, height: 28 * s)
                    Image(systemName: symbolName)
                        .font(.system(size: 12 * s, weight: .medium))
                        .foregroundColor(iconBg.opacity(isEnabled ? 1.0 : 0.45))
                }
            }

            // 레이블
            Text(title)
                .font(.system(size: 13 * s, weight: .medium))
                .foregroundColor(isEnabled ? Color(nsColor: .labelColor) : Color(nsColor: .tertiaryLabelColor))

            Spacer()

            // 상태 배지
            Text(status)
                .font(.system(size: 9.5 * s, weight: .medium))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .padding(.horizontal, 7 * s)
                .padding(.vertical,   3 * s)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                )
        }
        .padding(.horizontal, 7 * s)
        .padding(.vertical,   8 * s)
        .background(
            RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                .fill(isHovered && isEnabled
                    ? Color(nsColor: .controlAccentColor).opacity(0.12)
                    : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture { if isEnabled { action?() } }
    }
}

// MARK: - 하단 아이콘 버튼 (툴팁 포함)

struct HUDIconButton: View {
    let systemName: String
    let tooltip:    String
    let scale:      CGFloat
    var iconColor:  Color? = nil
    var action:     (() -> Void)? = nil

    init(systemName: String,
         tooltip: String,
         scale: CGFloat = 1.0,
         iconColor: Color? = nil,
         action: (() -> Void)? = nil) {
        self.systemName = systemName
        self.tooltip    = tooltip
        self.scale      = scale
        self.iconColor  = iconColor
        self.action     = action
    }

    @State private var isHovered = false

    private var s: CGFloat { scale }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14 * s, weight: .regular))
            .foregroundColor(isHovered
                ? (iconColor ?? Color(nsColor: .labelColor))
                : (iconColor?.opacity(0.75) ?? Color(nsColor: .secondaryLabelColor)))
            .frame(width: 26 * s, height: 26 * s)
            .background(
                RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                    .fill(isHovered
                        ? Color(nsColor: .quaternaryLabelColor).opacity(0.5)
                        : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture { action?() }
            .hoverTooltip(tooltip, isShowing: isHovered, scale: s, yOffset: -28 * s)
    }
}

// MARK: - 배고픔 텍스트 옆 인라인 밥주기 버튼

struct InlineFeedButton: View {
    let canFeed: Bool
    let tooltip: String
    let scale:   CGFloat
    let action:  () -> Void

    init(canFeed: Bool, tooltip: String, scale: CGFloat = 1.0, action: @escaping () -> Void) {
        self.canFeed = canFeed
        self.tooltip = tooltip
        self.scale   = scale
        self.action  = action
    }

    @State private var isHovered = false

    private var s: CGFloat { scale }

    var body: some View {
        Text("밥주기")
            .font(.system(size: 8.5 * s, weight: .medium))
            .foregroundColor(canFeed ? Color.white : Color(white: 0.75))
            .padding(.horizontal, 5 * s)
            .padding(.vertical,   2 * s)
            .background(
                Capsule()
                    .fill(canFeed
                        ? Color(red: 0.20, green: 0.78, blue: 0.35).opacity(isHovered ? 1.0 : 0.9)
                        : Color(white: 0.55).opacity(0.5))
            )
            .contentShape(Capsule())
            .onHover { isHovered = $0 }
            .onTapGesture { if canFeed { action() } }
            .hoverTooltip(tooltip, isShowing: isHovered, scale: s, yOffset: -26 * s)
    }
}

// MARK: - 툴팁 오버레이 공통 Modifier

private struct HoverTooltipModifier: ViewModifier {
    let text:      String
    let isShowing: Bool
    let scale:     CGFloat
    let yOffset:   CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isShowing {
                Text(text)
                    .font(.system(size: 9 * scale, weight: .medium))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical,   3 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 5 * scale, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5 * scale, style: .continuous)
                                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                    .shadow(color: .black.opacity(0.20), radius: 4 * scale, x: 0, y: 2 * scale)
                    .fixedSize()
                    .offset(y: yOffset)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                    .animation(.easeOut(duration: 0.12), value: isShowing)
                    .allowsHitTesting(false)
            }
        }
    }
}

private extension View {
    func hoverTooltip(_ text: String, isShowing: Bool, scale: CGFloat = 1.0, yOffset: CGFloat = -28) -> some View {
        modifier(HoverTooltipModifier(text: text, isShowing: isShowing, scale: scale, yOffset: yOffset))
    }
}
