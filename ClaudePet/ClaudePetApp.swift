import SwiftUI
import AppKit
import ApplicationServices
import Combine

@main
struct ClaudePetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Layout {
        static let spriteScale: CGFloat         = 3.0
        static let baseSpriteSize: CGFloat      = 32.0
        static let bottomMargin: CGFloat        = -10.0   // ← 하단 여백 (음수 = 독 아래로 숨김)
        static let topEffectHeadroomRatio: CGFloat = 1.3
        static let counterHeight: CGFloat       = 32.0   // ← 타이핑 카운터 영역 높이 (px)

        // 대사 전용 패널 설정
        static let dialogueWidth: CGFloat       = 180.0   // ← 대사 박스 최대 너비 (px)
        static let dialogueHeight: CGFloat      = 0.0    // ← 대사 박스 높이 여유분 (px)
        static let dialogueGapAboveSprite: CGFloat = 6.0  // ← 스프라이트 상단과의 간격 (px)
    }

    var overlayWindow: NSWindow?
    var dialoguePanel: NSPanel?
    var counterPanel:  NSPanel?

    // ─── 메뉴 HUD ─────────────────────────────────────────────────────────
    var menuHUDPanel:             NSPanel?
    var menuOutsideClickMonitor:  Any?

    func applicationDidFinishLaunching(_ notification: Notification) {

        // ─── 손쉬운 사용 권한 확인 ────────────────────────────────────────────
        // 권한이 없으면 시스템 설정 > 개인 정보 보호 > 손쉬운 사용 창을 자동으로 열고
        // ClaudePet 항목을 강조해줍니다. (빌드 후 매번 수동 추가 불필요)
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        // ─── 스프라이트 메인 창 ───────────────────────────────────────────
        let spriteSize     = Layout.baseSpriteSize * Layout.spriteScale          // 96 px
        let effectHeadroom = spriteSize * Layout.topEffectHeadroomRatio          // ~124.8 px
        let size           = CGSize(width: spriteSize, height: spriteSize + effectHeadroom)

        // 타이핑 카운터가 스프라이트와 겹쳐지므로 스프라이트를 화면 최하단에서 시작
        let origin = CGPoint(
            x: screen.visibleFrame.maxX - size.width,
            y: 0                                                                 // 화면 최하단 기준
        )

        let overlayWindow = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.overlayWindow = overlayWindow
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.hasShadow = false
        overlayWindow.level = .floating
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        overlayWindow.contentView = NSHostingView(rootView: ContentView())
        overlayWindow.makeKeyAndOrderFront(nil)

        // ─── 대사 전용 플로팅 패널 (독립 레이어) ─────────────────────────
        //
        // • ignoresMouseEvents = true  → 클릭·드래그가 완전히 통과됩니다.
        // • addChildWindow             → 스프라이트 창이 걸어서 이동할 때
        //                               오프셋을 유지하며 자동으로 따라갑니다.
        //
        // 위치 계산:
        //   스프라이트 가시 상단 Y = bottomMargin + spriteSize
        //   패널 Y               = 스프라이트 상단 + dialogueGap
        //   패널 X               = 스프라이트 중심에서 패널 너비의 절반을 뺀 값 (수평 중앙 정렬)
        let spriteVisibleTopY   = origin.y + spriteSize + Layout.dialogueGapAboveSprite
        let dialoguePanelX      = origin.x - (Layout.dialogueWidth - spriteSize) / 2

        let dialogueRect = NSRect(
            x: dialoguePanelX,
            y: spriteVisibleTopY,
            width: Layout.dialogueWidth,
            height: Layout.dialogueHeight
        )

        let panel = NSPanel(
            contentRect: dialogueRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.dialoguePanel = panel
        panel.backgroundColor      = .clear
        panel.isOpaque             = false
        panel.hasShadow            = false
        panel.level                = .floating
        panel.ignoresMouseEvents   = true
        panel.collectionBehavior   = [.canJoinAllSpaces, .stationary]
        panel.contentView          = NSHostingView(rootView: DialogueWindowContent())

        // 스프라이트 창의 자식으로 등록 → 이동 시 자동으로 함께 이동
        overlayWindow.addChildWindow(panel, ordered: .above)

        // ─── 타이핑 카운터 패널 (스프라이트 이미지 위에 겹쳐서 표시) ─────
        //
        // • 스프라이트 창과 동일한 x, y 위치 — 이미지와 겹침
        // • ignoresMouseEvents = true → 클릭이 완전히 통과됩니다
        // • addChildWindow           → 창 이동 시 스프라이트와 함께 이동
        // • level = overlayWindow.level + 1 → 항상 스프라이트보다 앞에 렌더링
        let counterRect = NSRect(
            x: origin.x,
            y: origin.y,                                                         // 스프라이트와 동일 위치 (겹침)
            width: spriteSize,
            height: Layout.counterHeight
        )

        let counter = NSPanel(
            contentRect: counterRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.counterPanel = counter
        counter.backgroundColor    = .clear
        counter.isOpaque           = false
        counter.hasShadow          = false
        counter.level              = NSWindow.Level(rawValue: overlayWindow.level.rawValue + 1) // 스프라이트보다 위
        counter.ignoresMouseEvents = true
        counter.collectionBehavior = [.canJoinAllSpaces, .stationary]
        counter.contentView        = NSHostingView(rootView: CounterWindowContent())

        overlayWindow.addChildWindow(counter, ordered: .above)

        // ─── 메뉴 HUD 알림 등록 ───────────────────────────────────────────
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleMenuHUD),
            name: .claudePetToggleMenu,
            object: nil
        )
    }

    // MARK: - 메뉴 HUD 토글

    @objc private func handleToggleMenuHUD() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let panel = self.menuHUDPanel, panel.isVisible {
                self.hideMenuHUD()
            } else {
                self.showMenuHUD()
            }
        }
    }

    private func showMenuHUD() {
        ensureMenuHUDPanel()
        guard let panel = menuHUDPanel, let petWindow = overlayWindow else { return }

        let spriteSize: CGFloat = Layout.baseSpriteSize * Layout.spriteScale  // 96 px
        let hudWidth:   CGFloat = 188
        let hudHeight:  CGFloat = 268   // 배고픔 바 + [DEBUG] 섹션 포함 높이
        let screen = NSScreen.main ?? NSScreen.screens[0]

        // 펫 스프라이트 바로 위에 위치, 수평 중앙 정렬
        var hudX = petWindow.frame.midX - hudWidth / 2
        let hudY = petWindow.frame.origin.y + spriteSize + 6

        // 화면 경계 클램핑
        hudX = max(screen.frame.minX + 8, min(hudX, screen.frame.maxX - hudWidth - 8))

        panel.setFrame(NSRect(x: hudX, y: hudY, width: hudWidth, height: hudHeight), display: false)
        panel.alphaValue = 0
        panel.orderFront(nil)

        // 페이드 인
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }

        // 외부 클릭 시 닫기 감지
        if menuOutsideClickMonitor == nil {
            menuOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                guard let self,
                      let hudPanel = self.menuHUDPanel, hudPanel.isVisible
                else { return }
                let mousePos   = NSEvent.mouseLocation
                let insideHUD  = NSPointInRect(mousePos, hudPanel.frame)
                let insidePet  = self.overlayWindow.map { NSPointInRect(mousePos, $0.frame) } ?? false
                // 펫 위 클릭은 toggle 이 처리하므로 여기서는 무시
                if !insideHUD && !insidePet {
                    DispatchQueue.main.async { self.hideMenuHUD() }
                }
            }
        }
    }

    private func hideMenuHUD() {
        guard let panel = menuHUDPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        if let m = menuOutsideClickMonitor {
            NSEvent.removeMonitor(m)
            menuOutsideClickMonitor = nil
        }
    }

    /// 최초 호출 시 한 번만 패널을 생성합니다. 이후 show/hide 로만 관리합니다.
    private func ensureMenuHUDPanel() {
        guard menuHUDPanel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 188, height: 268),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.backgroundColor  = .clear
        panel.isOpaque         = false
        panel.hasShadow        = false
        panel.level            = NSWindow.Level(
            rawValue: (overlayWindow?.level.rawValue ?? NSWindow.Level.floating.rawValue) + 2
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentView = NSHostingView(
            rootView: MenuHUDView(
                onClose: { [weak self] in self?.hideMenuHUD() },
                onFeed:  { [weak self] in
                    guard let self else { return }
                    // 밥주기: HungerManager 소비 처리 후 대사 출력
                    let success = HungerManager.shared.feed()
                    if success {
                        // ContentView 의 AnimationController 에 fed 대사 전달
                        NotificationCenter.default.post(
                            name: .claudePetFed, object: nil
                        )
                    }
                }
            )
        )
        menuHUDPanel = panel
    }
}

// MARK: - 타이핑 카운트 공유 모델
//
// @AppStorage 는 별도 NSHostingView 간 변경 감지가 불안정하므로
// ObservableObject 싱글톤으로 두 뷰가 동일한 인스턴스를 직접 관찰합니다.

final class TypingCounter: ObservableObject {
    static let shared = TypingCounter()
    static let didChange = Notification.Name("TypingCounterDidChange")
    private static let key = "typingCount"

    @Published var count: Int = UserDefaults.standard.integer(forKey: key)

    func increment() {
        count += 1
        UserDefaults.standard.set(count, forKey: Self.key)
        // NSHostingView가 별도 창에 있을 때 @ObservedObject 갱신이 불안정하므로
        // NotificationCenter로 명시적 갱신 신호를 보냅니다.
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// 지정한 양만큼 카운터를 차감합니다.
    /// 0 미만으로 내려가지 않습니다.
    func consume(_ amount: Int) {
        count = max(0, count - amount)
        UserDefaults.standard.set(count, forKey: Self.key)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// 지정한 양만큼 카운터를 증가시킵니다.
    /// [DEBUG] 디버그 버튼용 — 실제 게임 로직에 사용하지 마세요.
    func debugAdd(_ amount: Int) {
        count += amount
        UserDefaults.standard.set(count, forKey: Self.key)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private init() {}
}

// MARK: - 타이핑 카운터 패널 콘텐츠

struct CounterWindowContent: View {
    // @ObservedObject 대신 @State + NotificationCenter 사용
    // → 별도 NSHostingView(child panel)에서도 확실하게 UI가 갱신됩니다.
    @State private var count: Int = UserDefaults.standard.integer(forKey: "typingCount")

    var body: some View {
        Text(count.formatted(.number))
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.50))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(NotificationCenter.default.publisher(for: TypingCounter.didChange)) { _ in
                count = TypingCounter.shared.count
            }
    }
}
