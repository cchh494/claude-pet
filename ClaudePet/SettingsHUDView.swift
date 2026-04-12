import SwiftUI

// MARK: - 설정 HUD 메인 뷰

/// 메뉴 HUD 의 설정(기어) 버튼을 누르면 열리는 별도 패널.
struct SettingsHUDView: View {

    var onClose: () -> Void

    // 배율 — 패널 재생성 시 SettingsManager 에서 최신값을 읽습니다.
    private let s: CGFloat = SettingsManager.shared.uiScale

    @State private var hideDockIcon: Bool = SettingsManager.shared.hideDockIcon
    @State private var scaleIndex:   Int  = SettingsManager.shared.scaleIndex

    private let scaleOptions: [(label: String, index: Int)] = [
        ("0.5배", 0),
        ("1배",   1),
        ("2배",   2),
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── 헤더 ─────────────────────────────────────────────────────
            HStack(spacing: 6 * s) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10 * s, weight: .semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                Text("설정")
                    .font(.system(size: 11 * s, weight: .semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
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
            .padding(.horizontal, 12 * s)
            .padding(.top,        10 * s)
            .padding(.bottom,      8 * s)

            Divider()
                .padding(.horizontal, 10 * s)

            // ── 독 아이콘 숨김 토글 ──────────────────────────────────────
            SettingsToggleRow(
                icon:       "dock.rectangle",
                iconColor:  Color(red: 0.30, green: 0.60, blue: 1.00),
                title:      "독 비활성화",
                scale:      s,
                isOn:       $hideDockIcon
            )
            .onChange(of: hideDockIcon) { _, newValue in
                SettingsManager.shared.hideDockIcon = newValue
            }
            .padding(.horizontal, 8 * s)
            .padding(.top,        4 * s)
            .padding(.bottom,     2 * s)

            Divider()
                .padding(.horizontal, 10 * s)
                .padding(.top,         4 * s)

            // ── 앱 크기 배율 ────────────────────────────────────────────
            VStack(spacing: 7 * s) {
                HStack(spacing: 6 * s) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7 * s)
                            .fill(Color(red: 0.50, green: 0.80, blue: 0.40).opacity(0.22))
                            .frame(width: 28 * s, height: 28 * s)
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11 * s, weight: .medium))
                            .foregroundColor(Color(red: 0.50, green: 0.80, blue: 0.40))
                    }
                    Text("앱 크기")
                        .font(.system(size: 12 * s, weight: .medium))
                        .foregroundColor(Color(nsColor: .labelColor))
                    Spacer()
                    Text(SettingsManager.shared.scaleLabel)
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .padding(.horizontal, 7 * s)
                        .padding(.vertical,   3 * s)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                        )
                }
                .padding(.horizontal, 14 * s)

                // 세그먼트 선택 버튼
                HStack(spacing: 5 * s) {
                    ForEach(scaleOptions, id: \.index) { option in
                        ScaleSegmentButton(
                            label:      option.label,
                            isSelected: scaleIndex == option.index,
                            scale:      s,
                            action: {
                                scaleIndex = option.index
                                SettingsManager.shared.scaleIndex = option.index
                            }
                        )
                    }
                }
                .padding(.horizontal, 10 * s)
            }
            .padding(.top,    8 * s)
            .padding(.bottom, 8 * s)

            Divider()
                .padding(.horizontal, 10 * s)

            // ── 업데이트 확인 (Sparkle) ──────────────────────────────────
            UpdateCheckRow(scale: s) {
                SparkleManager.shared.checkForUpdates()
            }
            .padding(.horizontal, 8 * s)
            .padding(.top,        4 * s)
            .padding(.bottom,     8 * s)
        }
        .frame(width: 188 * s)
        .background(
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.20))
                .overlay(
                    Rectangle()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
        )
        .clipShape(Rectangle())
        .onReceive(NotificationCenter.default.publisher(for: SettingsManager.didChange)) { _ in
            hideDockIcon = SettingsManager.shared.hideDockIcon
            scaleIndex   = SettingsManager.shared.scaleIndex
        }
    }
}

// MARK: - 업데이트 확인 행 (Sparkle)

struct UpdateCheckRow: View {
    let scale:   CGFloat
    let onCheck: () -> Void

    @State private var isHovered = false

    private var s: CGFloat { scale }

    var body: some View {
        HStack(spacing: 9 * s) {
            ZStack {
                RoundedRectangle(cornerRadius: 7 * s)
                    .fill(Color(red: 0.40, green: 0.60, blue: 1.00).opacity(0.22))
                    .frame(width: 28 * s, height: 28 * s)
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 13 * s, weight: .medium))
                    .foregroundColor(Color(red: 0.40, green: 0.60, blue: 1.00))
            }

            VStack(alignment: .leading, spacing: 2 * s) {
                Text("업데이트 확인")
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundColor(Color(nsColor: .labelColor))
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")")
                    .font(.system(size: 9.5 * s, weight: .regular))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }

            Spacer()

            Button(action: onCheck) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9 * s, weight: .semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 7 * s)
        .padding(.vertical,   8 * s)
        .background(
            RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                .fill(isHovered
                    ? Color(nsColor: .controlAccentColor).opacity(0.10)
                    : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8 * s))
        .onHover { isHovered = $0 }
        .onTapGesture { onCheck() }
    }
}

// MARK: - 토글 행

struct SettingsToggleRow: View {
    let icon:      String
    let iconColor: Color
    let title:     String
    let scale:     CGFloat
    @Binding var isOn: Bool

    init(icon: String,
         iconColor: Color,
         title: String,
         scale: CGFloat = 1.0,
         isOn: Binding<Bool>) {
        self.icon      = icon
        self.iconColor = iconColor
        self.title     = title
        self.scale     = scale
        self._isOn     = isOn
    }

    private var s: CGFloat { scale }

    var body: some View {
        HStack(spacing: 9 * s) {
            ZStack {
                RoundedRectangle(cornerRadius: 7 * s)
                    .fill(iconColor.opacity(0.22))
                    .frame(width: 28 * s, height: 28 * s)
                Image(systemName: icon)
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundColor(iconColor)
            }

            Text(title)
                .font(.system(size: 12 * s, weight: .medium))
                .foregroundColor(Color(nsColor: .labelColor))

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.20, green: 0.78, blue: 0.35)))
                .labelsHidden()
                .fixedSize()
                .scaleEffect(0.65 * s)
                .frame(width: 38 * 0.65 * s, height: 22 * 0.65 * s)
        }
        .padding(.horizontal, 7 * s)
        .padding(.vertical,   7 * s)
    }
}

// MARK: - 크기 세그먼트 버튼

struct ScaleSegmentButton: View {
    let label:      String
    let isSelected: Bool
    let scale:      CGFloat
    let action:     () -> Void

    init(label: String,
         isSelected: Bool,
         scale: CGFloat = 1.0,
         action: @escaping () -> Void) {
        self.label      = label
        self.isSelected = isSelected
        self.scale      = scale
        self.action     = action
    }

    @State private var isHovered = false

    private var s: CGFloat { scale }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11 * s, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : Color(nsColor: .labelColor))
                .frame(maxWidth: .infinity)
                .frame(height: 26 * s)
                .background(
                    RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                        .fill(isSelected
                            ? Color(nsColor: .controlAccentColor)
                            : (isHovered
                                ? Color(nsColor: .quaternaryLabelColor).opacity(0.60)
                                : Color(nsColor: .quaternaryLabelColor).opacity(0.30)))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
    }
}
