import SwiftUI
import AppKit
import ApplicationServices

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

        // 카운터 패널이 스프라이트 바로 아래에 위치하므로 스프라이트 창을 counterHeight 만큼 위로 올림
        let origin = CGPoint(
            x: screen.visibleFrame.maxX - size.width,
            y: Layout.counterHeight                                              // 카운터 패널(0~counterHeight) 바로 위
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

        // ─── 타이핑 카운터 패널 (대사 패널과 동일한 독립 레이어 구조) ─────
        //
        // • 스프라이트 창 바로 아래(y: 0 ~ counterHeight)에 위치
        // • ignoresMouseEvents = true → 클릭이 완전히 통과됩니다
        // • addChildWindow           → 창 이동 시 스프라이트와 함께 이동
        let counterRect = NSRect(
            x: origin.x,
            y: 0,                                                                // 화면 최하단
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
        counter.level              = .floating
        counter.ignoresMouseEvents = true
        counter.collectionBehavior = [.canJoinAllSpaces, .stationary]
        counter.contentView        = NSHostingView(rootView: CounterWindowContent())

        overlayWindow.addChildWindow(counter, ordered: .above)
    }
}

// MARK: - 타이핑 카운터 패널 콘텐츠

struct CounterWindowContent: View {
    @AppStorage("typingCount") private var typingCount: Int = 0

    var body: some View {
        Text(typingCount.formatted(.number))
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
