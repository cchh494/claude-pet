import SwiftUI
import AppKit
import Darwin

struct ContentView: View {

    // MARK: - 애니메이션 컨트롤러

    @StateObject private var controller = AnimationController()

    // MARK: - 타이핑 카운터 (앱 종료 후에도 유지)

    @AppStorage("typingCount") private var typingCount: Int = 0

    // MARK: - 모니터링 상태 (@State 는 라이프사이클 전용)

    @State private var randomTimer:       Timer?
    @State private var mouseMonitor:      Any?
    @State private var keyboardMonitor:   Any?
    @State private var workspaceObserver: Any?
    @State private var terminateObserver: Any?
    @State private var activateObserver:  Any?
    @State private var workingDialogueTimer: Timer?
    @State private var cpuTimer:          Timer?
    @State private var accelDetector:     AccelerometerDetector?

    // CPU 모니터 내부 상태
    @State private var isClaudeRunning:      Bool   = false
    @State private var isWorkAppActive:      Bool   = false
    @State private var lastCPUNanos:         Double = 0
    @State private var aboveThresholdCount:  Int    = 0
    @State private var belowThresholdCount:  Int    = 0

    // 마우스 흔들기 추적
    @State private var mouseLog: [(time: Date, x: CGFloat)] = []

    // MARK: - View Body

    var body: some View {
        GeometryReader { geo in
            let displaySize = geo.size.width
            let frameCount  = controller.animationState.frameDurationsMs.count

            ZStack(alignment: .bottom) {
                Color.clear

                // ── 스프라이트 ─────────────────────────────────────────────
                Image(controller.animationState.assetName)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: displaySize * CGFloat(frameCount), height: displaySize)
                    .offset(x: -displaySize * CGFloat(controller.currentFrame))
                    .frame(width: displaySize, height: displaySize, alignment: .leading)
                    .clipped()
                    // Walk 중 오른쪽 이동 시 좌우 반전 (기본: 왼쪽 바라봄)
                    .scaleEffect(
                        x: ((controller.animationState == .idleTouchWalk ||
                             controller.animationState == .idleWalk)
                            && controller.walkDirection > 0) ? -1 : 1,
                        y: 1
                    )
                    .scaleEffect(controller.pressScale)
                    .offset(x: controller.shakeOffset)

                // ── 하트 이펙트 ────────────────────────────────────────────
                Image("Emoji_Heart")
                    .resizable()
                    .interpolation(.none)
                    .frame(width: displaySize * 0.24, height: displaySize * 0.24)
                    .offset(y: -(displaySize * 0.46) + controller.heartYOffset)
                    .scaleEffect(controller.heartScale)
                    .opacity(controller.heartOpacity)
                    .allowsHitTesting(false)

                // ── 인터랙션 오버레이 ───────────────────────────────────────
                // 살짝 누름(일반 클릭)   → Idle_Smile
                // 세게 누름(Force Click) → Idle_Touch
                // 우클릭(두 손가락 클릭) → Idle_Jumping
                InteractionOverlay(
                    activeHeight: displaySize,
                    onLightPress: { _ in controller.handleTap() },
                    onForcePress: { isLeftHalf in controller.handleForcePress(isLeftHalf: isLeftHalf) },
                    onRightClick: { controller.handleRightClick() }
                )
            }
        }
        .onAppear {
            // 창 참조를 AnimationController 에 주입 (Walk 이동에 필요)
            controller.windowProvider = {
                NSApplication.shared.windows.first {
                    $0.styleMask.contains(.borderless) && $0.level == .floating
                }
            }
            controller.switchAnimation(to: .idleDefault)
            startRandomTimer()
            startMouseShakeDetection()
            startKeyboardMonitor()
            setupWorkspaceObserver()
            startCPUMonitor()
            controller.startMouseFollowDetection()
            // startAccelerometerDetection()  // [비활성화됨] AccelerometerDetector.swift 참조
        }
        .onDisappear {
            cleanup()
        }
    }

    // MARK: - 랜덤 인터럽트 타이머

    private func startRandomTimer() {
        randomTimer?.invalidate()
        randomTimer = Timer.scheduledTimer(
            withTimeInterval: PetConfig.randomInterruptIntervalSec,
            repeats: true
        ) { _ in
            guard !controller.isInTransition,
                  controller.animationState == .idleDefault else { return }

            let roll = Double.random(in: 0..<1)
            let smileEnd   = PetConfig.smileProbability
            let boringEnd  = smileEnd  + PetConfig.boringProbability
            let jumpEnd    = boringEnd + PetConfig.jumpingProbability
            let walkEnd    = jumpEnd   + PetConfig.autonomousWalkProbability

            if roll < smileEnd {
                controller.showDialogue(for: .smile)
                controller.switchAnimation(to: .idleSmile)
            } else if roll < boringEnd {
                controller.showDialogue(for: .boring)
                controller.switchAnimation(to: .idleBoring)
            } else if roll < jumpEnd {
                controller.showDialogue(for: .jumping)
                controller.switchAnimation(to: .idleJumping)
            } else if roll < walkEnd {
                controller.startAutonomousWalk()
            } else if Bool.random() {
                controller.showDialogue(for: .idle)
            }
        }
    }

    // MARK: - 타이핑 카운터 키보드 감지

    private func startKeyboardMonitor() {
        // 전역 키 입력 감지 — 어느 앱에서 타이핑해도 카운트됩니다.
        // ※ 시스템 환경설정 > 개인 정보 보호 > 손쉬운 사용 권한 필요
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in
            DispatchQueue.main.async {
                typingCount += 1
            }
        }
    }

    // MARK: - 마우스 흔들기 감지

    private func startMouseShakeDetection() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
            let pos = NSEvent.mouseLocation
            let now = Date()

            // 시간 윈도우 밖 데이터 제거
            mouseLog = mouseLog.filter {
                now.timeIntervalSince($0.time) <= PetConfig.shakeTimeWindowSec
            }
            mouseLog.append((time: now, x: pos.x))

            guard mouseLog.count >= 3 else { return }

            var changes = 0
            for i in 1 ..< mouseLog.count - 1 {
                let dx1 = mouseLog[i].x     - mouseLog[i - 1].x
                let dx2 = mouseLog[i + 1].x - mouseLog[i].x
                if dx1 * dx2 < 0 && abs(dx1) >= PetConfig.shakeMinMovePx {
                    changes += 1
                }
            }

            if changes >= PetConfig.shakeDirectionChanges {
                mouseLog.removeAll()
                DispatchQueue.main.async { controller.handleShake() }
            }
        }
    }

    // MARK: - Claude 앱 실행/종료 감지

    private func setupWorkspaceObserver() {
        let nc = NSWorkspace.shared.notificationCenter

        workspaceObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication,
                  AppIdentifier.isClaude(app) else { return }
            handleClaudeLaunched()
        }

        terminateObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication,
                  AppIdentifier.isClaude(app) else { return }
            handleClaudeTerminated()
        }

        activateObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else { return }

            if AppIdentifier.isWorkApp(app) {
                handleWorkAppActivated()
            } else {
                handleWorkAppDeactivated()
            }
        }

        // 시작 시 Claude 가 이미 실행 중이면 플래그만 설정
        if NSWorkspace.shared.runningApplications.contains(where: AppIdentifier.isClaude) {
            handleClaudeLaunched()
        }
    }

    private func handleClaudeLaunched() {
        isClaudeRunning = true
        lastCPUNanos    = 0
    }

    private func handleClaudeTerminated() {
        isClaudeRunning     = false
        isWorkAppActive     = false
        aboveThresholdCount = 0
        belowThresholdCount = 0
        lastCPUNanos        = 0
        stopWorkingDialogueTimer()
        controller.handleClaudeTerminated()
    }

    private func handleWorkAppActivated() {
        isWorkAppActive = true
        // 실제로 Working 상태로 진입한 경우에만 대사 타이머 시작
        if controller.handleWorkAppActivated(resetBelowCount: { belowThresholdCount = 0 }) {
            startWorkingDialogueTimer()
        }
    }

    private func handleWorkAppDeactivated() {
        isWorkAppActive = false
        stopWorkingDialogueTimer()
        controller.handleWorkAppDeactivated()
    }

    // MARK: - Working 대사 타이머

    private func startWorkingDialogueTimer() {
        workingDialogueTimer?.invalidate()
        workingDialogueTimer = Timer.scheduledTimer(
            withTimeInterval: PetConfig.workingDialogueIntervalSec,
            repeats: true
        ) { _ in
            guard controller.animationState == .idleWorking else { return }
            controller.showDialogue(for: .working)
        }
    }

    private func stopWorkingDialogueTimer() {
        workingDialogueTimer?.invalidate()
        workingDialogueTimer = nil
    }

    // MARK: - CPU 기반 작업 감지

    private func startCPUMonitor() {
        cpuTimer?.invalidate()
        cpuTimer = Timer.scheduledTimer(
            withTimeInterval: PetConfig.cpuPollIntervalSec,
            repeats: true
        ) { _ in
            guard isClaudeRunning else { lastCPUNanos = 0; return }
            guard let currentNanos = claudeTotalNanos() else { lastCPUNanos = 0; return }

            let prev = lastCPUNanos
            lastCPUNanos = currentNanos
            guard prev > 0 else { return }   // 첫 샘플은 기준값만 저장

            let deltaNanos = currentNanos - prev
            let cpuPercent = deltaNanos / (PetConfig.cpuPollIntervalSec * 1_000_000_000) * 100

            DispatchQueue.main.async {
                if cpuPercent > PetConfig.cpuWorkingPercent {
                    aboveThresholdCount += 1
                    belowThresholdCount  = 0
                    if aboveThresholdCount >= PetConfig.workingConfirmCount {
                        controller.handleCPUHighLoad()
                    }

                } else if cpuPercent < PetConfig.cpuIdlePercent {
                    // WorkingPrepare 재생 중에는 카운터 누적 안 함
                    guard controller.animationState != .idleWorkingPrepare else { return }
                    belowThresholdCount += 1
                    aboveThresholdCount  = 0
                    if belowThresholdCount >= PetConfig.idleConfirmCount,
                       controller.animationState == .idleWorking,
                       !isWorkAppActive {
                        controller.clearTransitionFlag()
                        controller.switchAnimation(to: .idleDefault)
                        stopWorkingDialogueTimer()
                    }
                }
                // 중간 구간은 카운터 유지 (히스테리시스)
            }
        }
    }

    /// Claude 프로세스의 누적 CPU 시간을 나노초로 반환합니다.
    /// proc_pidinfo + mach_timebase_info 사용 — 별도 권한 불필요.
    private func claudeTotalNanos() -> Double? {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: AppIdentifier.isClaude) else { return nil }

        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        guard proc_pidinfo(app.processIdentifier, PROC_PIDTASKINFO, 0, &info, size)
              == size else { return nil }

        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let totalMach = info.pti_total_user + info.pti_total_system
        return Double(totalMach) * Double(tb.numer) / Double(tb.denom)
    }

    // MARK: - 충격 감지 (IOKit HID 가속도계 — 현재 비활성화)

    private func startAccelerometerDetection() {
        let detector = AccelerometerDetector()
        detector.impactThreshold = PetConfig.accelImpactThreshold
        detector.cooldownSec     = PetConfig.accelCooldownSec
        detector.onImpact        = { controller.handleAccelerometerHit() }
        detector.start()
        accelDetector = detector
    }

    // MARK: - 정리

    private func cleanup() {
        controller.cleanup()
        randomTimer?.invalidate()
        cpuTimer?.invalidate()
        workingDialogueTimer?.invalidate()
        accelDetector?.stop()
        accelDetector = nil
        DialogueManager.shared.hide()
        if let m = mouseMonitor    { NSEvent.removeMonitor(m) }
        if let k = keyboardMonitor { NSEvent.removeMonitor(k) }
        let nc = NSWorkspace.shared.notificationCenter
        [workspaceObserver, terminateObserver, activateObserver]
            .compactMap { $0 }
            .forEach { nc.removeObserver($0) }
    }
}

// MARK: - InteractionOverlay

/// Force Touch 트랙패드의 압력을 감지하는 투명 오버레이입니다.
///
/// - mouseUp (force click 없음) → onLightPress  (살짝 누름 — Idle_Smile)
/// - pressureChange stage 2    → onForcePress  (세게 누름 — Idle_Touch)
///
/// Force Click 시 mouseDown → pressureChange(stage2) → mouseUp 순으로 이벤트가 오므로
/// mouseUp 시점에 forceTriggered 플래그를 확인해 Smile/Touch 를 구분합니다.
struct InteractionOverlay: NSViewRepresentable {
    var activeHeight: CGFloat
    var onLightPress: (Bool) -> Void
    var onForcePress: (Bool) -> Void
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> PressView {
        let v = PressView()
        v.activeHeight = activeHeight
        v.onLightPress = onLightPress
        v.onForcePress = onForcePress
        v.onRightClick = onRightClick
        return v
    }

    func updateNSView(_ nsView: PressView, context: Context) {
        nsView.activeHeight = activeHeight
        nsView.onLightPress = onLightPress
        nsView.onForcePress = onForcePress
        nsView.onRightClick = onRightClick
    }
}

// MARK: - PressView

final class PressView: NSView {
    var activeHeight: CGFloat = 0
    var onLightPress: ((Bool) -> Void)?
    var onForcePress: ((Bool) -> Void)?
    var onRightClick: (() -> Void)?

    private var forceTriggered = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        forceTriggered = false
    }

    override func mouseUp(with event: NSEvent) {
        guard !forceTriggered else { return }
        let loc       = convert(event.locationInWindow, from: nil)
        let isBottom  = loc.y <= activeHeight
        guard isBottom else { return }
        let isLeftHalf = loc.x < bounds.width / 2
        onLightPress?(isLeftHalf)
    }

    override func pressureChange(with event: NSEvent) {
        guard event.stage == 2, !forceTriggered else { return }
        forceTriggered = true
        let loc        = convert(event.locationInWindow, from: nil)
        let isLeftHalf = loc.x < bounds.width / 2
        onForcePress?(isLeftHalf)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        point.y <= activeHeight ? self : nil
    }
}
