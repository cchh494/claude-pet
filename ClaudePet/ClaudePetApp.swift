import SwiftUI
import AppKit

@main
struct ClaudePetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayWindow: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main!

        // ✏️ 창 크기 — 스프라이트 1프레임(32px) 기준, 원하는 배율로 조절
        let spriteScale: CGFloat = 3.0           // ← 표시 배율 (1.0 = 32px, 2.0 = 64px, 3.0 = 96px …)
        let spriteSize: CGFloat = 32 * spriteScale
        let size = CGSize(width: spriteSize, height: spriteSize)

        // ✏️ Y 위치 조절 (화면 하단에서 올라오는 거리, px)
        let bottomMargin: CGFloat = -10          // ← 음수일수록 캐릭터가 더 아래로

        let origin = CGPoint(
            x: screen.frame.width - size.width,   // 오른쪽 끝
            y: bottomMargin
        )

        overlayWindow = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.hasShadow = false
        overlayWindow.level = .floating
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        overlayWindow.contentView = NSHostingView(rootView: ContentView())
        overlayWindow.makeKeyAndOrderFront(nil)
    }
}
