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
    private enum Layout {
        static let spriteScale: CGFloat = 3.0
        static let baseSpriteSize: CGFloat = 32.0
        static let bottomMargin: CGFloat = -10.0
        static let topEffectHeadroomRatio: CGFloat = 1.3
    }

    var overlayWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        // ✏️ 창 크기 — 스프라이트 1프레임(32px) 기준, 원하는 배율로 조절
        let spriteSize = Layout.baseSpriteSize * Layout.spriteScale
        let effectHeadroom = spriteSize * Layout.topEffectHeadroomRatio
        let size = CGSize(width: spriteSize, height: spriteSize + effectHeadroom)

        // ✏️ Y 위치 조절 (화면 하단에서 올라오는 거리, px)
        let origin = CGPoint(
            x: screen.visibleFrame.maxX - size.width,
            y: Layout.bottomMargin
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
    }
}
