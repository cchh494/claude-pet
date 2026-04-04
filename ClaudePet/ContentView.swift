import SwiftUI
import AppKit
import Darwin

struct ContentView: View {
    // MARK: ─────────────────────────────────────────────────────────────
    //  랜덤 인터럽트 설정
    // ─────────────────────────────────────────────────────────────────
    private let randomInterruptIntervalSec: Double = 6.0    // ← 랜덤 인터럽트 체크 주기 (초)
    private let smileProbability:   Double = 0.30           // ← Idle_Smile 진입 확률 (0.0~1.0)
    private let boringProbability:  Double = 0.20           // ← Idle_Boring 진입 확률 (0.0~1.0)
    private let jumpingProbability: Double = 0.15           // ← Idle_Jumping 진입 확률 (0.0~1.0)

    // MARK: ─────────────────────────────────────────────────────────────
    //  마우스 흔들기 감지 설정
    // ─────────────────────────────────────────────────────────────────
    private let shakeDirectionChanges: Int    = 5           // ← 흔들기 인식 최소 방향 전환 횟수
    private let shakeTimeWindowSec:    Double = 1.0         // ← 흔들기 감지 시간 윈도우 (초)
    private let shakeMinMovePx:        CGFloat = 20.0       // ← 방향 전환 최소 이동 거리 (px)
    private let touchWalkTimeoutSec:   Double = 2.5         // ← 흔들기 종료 판정 시간 (초)

    // MARK: ─────────────────────────────────────────────────────────────
    //  Touch_Walk 이동 설정
    // ─────────────────────────────────────────────────────────────────
    private let walkSpeed:         CGFloat = 400.0   // ← 이동 속도 (px/초)
    private let walkTotalDistance: CGFloat = 100.0  // ← 최대 이동 거리 (px)

    // MARK: ─────────────────────────────────────────────────────────────
    //  충격 감지 설정 (IOKit HID 가속도계 — Bosch BMI286)
    //  taigrr/spank 와 동일한 프로토콜: Usage Page 0x0020 / Usage 0x0073
    //  정지 시 벡터 크기 ≈ 1g, 충격 시 2g 이상 → accelImpactThreshold 초과 시 트리거
    // ─────────────────────────────────────────────────────────────────
    private let accelImpactThreshold: Double = 2.0   // ← 충격 임계값 (g), 낮추면 더 민감
    private let accelCooldownSec:     Double = 0.8   // ← 연속 트리거 방지 쿨다운 (초)

    // MARK: ─────────────────────────────────────────────────────────────
    //  CPU 기반 작업 감지 설정
    //  Claude 프로세스의 CPU 사용량을 주기적으로 샘플링해
    //  토큰 생성 중 여부를 자동 판별합니다.
    // ─────────────────────────────────────────────────────────────────
    private let cpuPollIntervalSec: Double  = 1.0   // ← 샘플링 주기 (초)
    private let cpuWorkingPercent:  Double  = 15.0  // ← Working 진입 CPU% 임계값
    private let cpuIdlePercent:     Double  = 5.0   // ← Idle 복귀 CPU% 임계값
    private let workingConfirmCount: Int    = 2     // ← Working 확정 연속 횟수
    private let idleConfirmCount:    Int    = 3     // ← Idle 복귀 연속 횟수

    // MARK: - @State
    @State private var animationState: PetAnimationState = .idleDefault
    @State private var currentFrame: Int = 0
    @State private var currentRepeat: Int = 0           // 전환 재생 반복 누적

    @State private var workItem: DispatchWorkItem?
    @State private var randomTimer: Timer?
    @State private var touchWalkTimeoutItem: DispatchWorkItem?
    @State private var mouseMonitor: Any?
    @State private var workspaceObserver: Any?
    @State private var terminateObserver: Any?
    @State private var activateObserver: Any?
    @State private var isWorkAppActive: Bool = false  // 작업 앱이 포그라운드인지 여부

    // Touch_Walk 이동 추적용
    @State private var walkTimer: Timer?
    @State private var walkDirection: CGFloat = 0        // +1 오른쪽, -1 왼쪽
    @State private var walkDistanceRemaining: CGFloat = 0
    @State private var preferredWalkDirection: CGFloat?

    // 마우스 흔들기 추적용
    @State private var mouseLog: [(time: Date, x: CGFloat)] = []

    // 전환 재생 중 여부 (랜덤 인터럽트 차단용)
    @State private var isInTransition: Bool = false

    // 충격 감지 (IOKit HID 가속도계)
    @State private var accelDetector: AccelerometerDetector?

    // CPU 모니터 관련
    @State private var cpuTimer: Timer?
    @State private var isClaudeRunning: Bool = false    // Claude 앱 실행 중 여부
    @State private var lastCPUNanos: Double = 0         // 이전 샘플의 누적 CPU 나노초
    @State private var aboveThresholdCount: Int = 0     // Working 임계값 초과 연속 횟수
    @State private var belowThresholdCount: Int = 0     // Idle 임계값 미만 연속 횟수

    // 인터랙션 애니메이션
    @State private var pressScale: CGFloat = 1.0        // 살짝 누름 스케일 효과
    @State private var shakeOffset: CGFloat = 0         // 세게 누름 좌우 흔들기 오프셋
    @State private var heartOpacity: Double = 0
    @State private var heartYOffset: CGFloat = 0
    @State private var heartScale: CGFloat = 0.85
    @State private var heartEffectID: Int = 0

    // (더블탭 감지 제거됨 — 우클릭으로 Jumping 이동)

    // MARK: - 상태별 이미지명·프레임ms 매핑
    private var imageName: String { animationState.assetName }
    private var frameMs: [Double] { animationState.frameDurationsMs }

    private var frameCount: Int { frameMs.count }

    // MARK: - View Body
    var body: some View {
        GeometryReader { geo in
            // 창 너비를 기준으로 스프라이트 크기를 유지하고, 위쪽은 이펙트용 여백으로 사용
            let displaySize = geo.size.width

            ZStack(alignment: .bottom) {
                Color.clear

                Image(imageName)
                    .resizable()
                    .interpolation(.none)   // Nearest 보간 — 픽셀 선명하게 유지
                    .frame(width: displaySize * CGFloat(frameCount), height: displaySize)
                    .offset(x: -displaySize * CGFloat(currentFrame))
                    .frame(width: displaySize, height: displaySize, alignment: .leading)
                    .clipped()
                    // Touch_Walk 중 오른쪽 이동 시 스프라이트 좌우 반전 (기본값: 왼쪽 바라봄)
                    .scaleEffect(
                        x: (animationState == .idleTouchWalk && walkDirection > 0) ? -1 : 1,
                        y: 1
                    )
                    .scaleEffect(pressScale)          // 살짝 누름 — 눌린 느낌 스케일
                    .offset(x: shakeOffset)           // 세게 누름 — 좌우 흔들기

                Image("Emoji_Heart")
                    .resizable()
                    .interpolation(.none)
                    .frame(width: displaySize * 0.24, height: displaySize * 0.24)
                    .offset(y: -(displaySize * 0.46) + heartYOffset)
                    .scaleEffect(heartScale)
                    .opacity(heartOpacity)
                    .allowsHitTesting(false)

                // Force Touch 감지 오버레이
                // 살짝 누름(일반 클릭)        → Idle_Smile
                // 세게 누름(Force Click)      → Idle_Touch
                // 우클릭(두 손가락 클릭)       → Idle_Jumping
                InteractionOverlay(
                    activeHeight: displaySize,
                    onLightPress: { _ in handleTap() },
                    onForcePress: { isLeftHalf in handleForcePress(isLeftHalf: isLeftHalf) },
                    onRightClick: { handleRightClick() }
                )
            }
        }
        .onAppear {
            switchAnimation(to: .idleDefault)
            startRandomTimer()
            startMouseShakeDetection()
            setupWorkspaceObserver()
            startCPUMonitor()
            // startAccelerometerDetection()  // [비활성화됨] AccelerometerDetector.swift 참조
        }
        .onDisappear {
            cleanup()
        }
    }

    // MARK: - 애니메이션 엔진

    /// 상태를 전환하고 첫 프레임부터 재생 시작
    private func switchAnimation(to state: PetAnimationState) {
        workItem?.cancel()
        touchWalkTimeoutItem?.cancel()
        walkTimer?.invalidate()
        walkTimer = nil

        animationState = state
        currentFrame   = 0
        currentRepeat  = 0

        isInTransition = state.transition.isTransition

        if state == .idleTouchWalk {
            startWalkMovement()
        }

        scheduleNextFrame()
    }

    /// 현재 프레임 표시 후 다음 프레임을 예약
    private func scheduleNextFrame() {
        let delayMs = frameMs[currentFrame % frameMs.count]
        let delaySec = delayMs / 1000.0     // ms → 초 변환

        let capturedState = animationState

        let item = DispatchWorkItem {
            // 상태가 바뀐 경우 무시 (이전 workItem이 늦게 실행된 경우)
            guard animationState == capturedState else { return }

            let nextFrame = currentFrame + 1
            let transition = animationState.transition

            if nextFrame >= frameCount {
                // ── 사이클 1회 완료 ──────────────────────────────────
                if transition.isTransition {
                    let newRepeat = currentRepeat + 1
                    if newRepeat >= transition.repeatCount {
                        // 지정 횟수 재생 완료 → 다음 상태로 전환
                        switchAnimation(to: transition.nextState)
                    } else {
                        // 아직 더 반복해야 함
                        currentRepeat = newRepeat
                        currentFrame  = 0
                        scheduleNextFrame()
                    }
                } else {
                    // 지속 재생 — 무한 루프
                    currentFrame = 0
                    scheduleNextFrame()
                }
            } else {
                // ── 다음 프레임으로 이동 ──────────────────────────────
                currentFrame = nextFrame
                scheduleNextFrame()
            }
        }

        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySec, execute: item)
    }

    // MARK: - 터치 처리

    /// 살짝 누름 (일반 클릭) → Idle_Smile + 눌린 스케일 애니메이션
    private func handleTap() {
        guard !isInTransition else { return }
        guard animationState.isPrimaryInteractionState else { return }

        triggerHaptic()
        applyPressScale()
        triggerHeartEffect()
        switchAnimation(to: .idleSmile)
    }

    /// 우클릭 (두 손가락 클릭) → Idle_Jumping
    /// Smile 재생 중에는 transition 을 무시하고 즉시 실행
    private func handleRightClick() {
        // Smile 재생 중이면 transition 체크 없이 즉시 Jumping 실행
        if animationState == .idleSmile {
            triggerHaptic()
            applyPressScale()
            switchAnimation(to: .idleJumping)
            return
        }
        guard !isInTransition else { return }
        guard animationState.isPrimaryInteractionState else { return }
        triggerHaptic()
        applyPressScale()
        switchAnimation(to: .idleJumping)
    }

    private func applyPressScale() {
        // 아주 살짝 축소 후 복귀 — 눌린 느낌
        withAnimation(.easeIn(duration: 0.07)) {
            pressScale = 0.88
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
                pressScale = 1.0
            }
        }
    }

    private func triggerHeartEffect() {
        heartEffectID += 1
        let effectID = heartEffectID

        heartOpacity = 0
        heartYOffset = 10
        heartScale = 0.8

        withAnimation(.easeOut(duration: 0.16)) {
            heartOpacity = 1
            heartYOffset = -6
            heartScale = 1.0
        }

        withAnimation(.easeOut(duration: 2.4)) {
            heartYOffset = -54
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard heartEffectID == effectID else { return }
            withAnimation(.easeIn(duration: 0.9)) {
                heartOpacity = 0
                heartScale = 1.08
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard heartEffectID == effectID else { return }
            heartYOffset = 0
            heartScale = 0.85
        }
    }

    /// 세게 누름 (Force Click) → 조건 없이 즉시 Idle_Touch 실행 + 좌우 흔들기 + 강한 햅틱 4회
    private func handleForcePress(isLeftHalf: Bool) {
        preferredWalkDirection = isLeftHalf ? 1.0 : -1.0
        triggerStrongHaptics()
        // 스프라이트 전환을 현재 틱에 먼저 커밋
        switchAnimation(to: .idleTouch)
        scheduleTouchWalkTimeout()
        // 다음 RunLoop 틱에서 흔들기 시작 → Idle_Touch 스프라이트에 정확히 붙음
        DispatchQueue.main.async {
            triggerShakeAnimation()
        }
    }

    // MARK: - 랜덤 인터럽트 타이머
    private func startRandomTimer() {
        randomTimer?.invalidate()
        randomTimer = Timer.scheduledTimer(
            withTimeInterval: randomInterruptIntervalSec,
            repeats: true
        ) { _ in
            guard !isInTransition, animationState == .idleDefault else { return }

            let roll = Double.random(in: 0..<1)
            if roll < smileProbability {
                switchAnimation(to: .idleSmile)
            } else if roll < smileProbability + boringProbability {
                switchAnimation(to: .idleBoring)
            } else if roll < smileProbability + boringProbability + jumpingProbability {
                switchAnimation(to: .idleJumping)
            }
            // 확률에 해당하지 않으면 아무것도 안 함
        }
    }

    // MARK: - 마우스 흔들기 감지 (macOS — 가속도계 대체)
    private func startMouseShakeDetection() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
            let pos   = NSEvent.mouseLocation
            let now   = Date()

            // 시간 윈도우 밖 데이터 제거
            mouseLog = mouseLog.filter {
                now.timeIntervalSince($0.time) <= shakeTimeWindowSec
            }
            mouseLog.append((time: now, x: pos.x))

            guard mouseLog.count >= 3 else { return }

            // 방향 전환 횟수 카운트
            var changes = 0
            for i in 1 ..< mouseLog.count - 1 {
                let dx1 = mouseLog[i].x   - mouseLog[i - 1].x
                let dx2 = mouseLog[i + 1].x - mouseLog[i].x
                let dist = abs(dx1)
                if dx1 * dx2 < 0 && dist >= shakeMinMovePx {
                    changes += 1
                }
            }

            if changes >= shakeDirectionChanges {
                mouseLog.removeAll()
                DispatchQueue.main.async {
                    handleShake()
                }
            }
        }
    }

    private func handleShake() {
        // idleTouchWalk 중에는 walk 타이머가 복귀를 직접 제어하므로 무시
        if animationState == .idleTouchWalk { return }
        guard !isInTransition, animationState == .idleDefault else { return }
        switchAnimation(to: .idleTouch)
        // Touch → Touch_Walk 전환은 PetAnimationState.transition 규칙으로 자동 처리됨
    }

    // MARK: - Touch_Walk 이동

    /// idleTouchWalk 진입 시 호출 — 마지막 Force Click 위치를 우선 반영해 이동
    private func startWalkMovement() {
        // 현재 창 위치 기준으로 이동 가능한 방향 결정
        guard let window = overlayWindow else { return }

        let screen     = NSScreen.main ?? NSScreen.screens[0]
        let currentX   = window.frame.origin.x
        let minX: CGFloat = 0
        let maxX: CGFloat = screen.frame.width - window.frame.width

        let canGoRight = currentX < maxX - 1
        let canGoLeft  = currentX > minX + 1

        let requestedDirection = preferredWalkDirection
        preferredWalkDirection = nil

        if let requestedDirection {
            if requestedDirection > 0, canGoRight {
                walkDirection = 1.0
            } else if requestedDirection < 0, canGoLeft {
                walkDirection = -1.0
            } else if canGoRight {
                walkDirection = 1.0
            } else if canGoLeft {
                walkDirection = -1.0
            } else {
                DispatchQueue.main.async {
                    guard animationState == .idleTouchWalk else { return }
                    isInTransition = false
                    switchAnimation(to: .idleDefault)
                }
                return
            }
        } else if canGoRight && canGoLeft {
            // 방향 힌트가 없으면 기존처럼 랜덤
            walkDirection = Bool.random() ? 1.0 : -1.0
        } else if canGoRight {
            walkDirection = 1.0
        } else if canGoLeft {
            walkDirection = -1.0
        } else {
            // 어느 쪽도 이동 불가 → 바로 Default 복귀
            DispatchQueue.main.async {
                guard animationState == .idleTouchWalk else { return }
                isInTransition = false
                switchAnimation(to: .idleDefault)
            }
            return
        }

        walkDistanceRemaining = walkTotalDistance

        let tickInterval: Double  = 1.0 / 60.0               // 60fps
        let pixelsPerTick: CGFloat = walkSpeed * CGFloat(tickInterval)

        walkTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { timer in
            guard animationState == .idleTouchWalk else {
                timer.invalidate()
                return
            }

            guard let window = overlayWindow else {
                timer.invalidate()
                return
            }

            let screen       = NSScreen.main ?? NSScreen.screens[0]
            let currentX     = window.frame.origin.x
            let newX         = currentX + (walkDirection * pixelsPerTick)

            // 화면 경계 클램프
            let minX: CGFloat = 0
            let maxX: CGFloat = screen.frame.width - window.frame.width
            let clampedX      = max(minX, min(maxX, newX))
            let hitEdge       = abs(clampedX - newX) > 0.1

            window.setFrameOrigin(CGPoint(x: clampedX, y: window.frame.origin.y))
            walkDistanceRemaining -= pixelsPerTick

            // 이동 완료 조건: 거리 소진 또는 화면 끝 도달
            if walkDistanceRemaining <= 0 || hitEdge {
                timer.invalidate()
                walkTimer = nil
                DispatchQueue.main.async {
                    guard animationState == .idleTouchWalk else { return }
                    isInTransition = false
                    switchAnimation(to: .idleDefault)
                }
            }
        }
    }

    /// Touch_Walk 무한 루프 중 흔들기가 멈추면 Idle_Default로 복귀
    private func scheduleTouchWalkTimeout() {
        // idleTouch 전환 재생이 끝나야 Touch_Walk가 시작되므로 여유 시간 추가
        let touchDuration = PetAnimationState.idleTouch.frameDurationsMs.reduce(0, +) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + touchDuration) {
            resetTouchWalkTimeout()
        }
    }

    private func resetTouchWalkTimeout() {
        touchWalkTimeoutItem?.cancel()
        let item = DispatchWorkItem {
            guard animationState == .idleTouchWalk else { return }
            isInTransition = false
            switchAnimation(to: .idleDefault)
        }
        touchWalkTimeoutItem = item
        // ← 흔들기 종료 후 이 시간(초) 뒤에 Idle_Default로 복귀
        DispatchQueue.main.asyncAfter(
            deadline: .now() + touchWalkTimeoutSec,
            execute: item
        )
    }

    // MARK: - Claude 앱 실행/종료 감지
    // Claude 앱의 실행 여부를 isClaudeRunning 플래그로 추적합니다.
    // 실제 Working 전환은 CPU 모니터가 담당합니다.
    private func setupWorkspaceObserver() {
        let nc = NSWorkspace.shared.notificationCenter

        // 앱 실행 알림 — Claude가 새로 켜졌을 때
        workspaceObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else { return }

            if isClaudeApp(app) {
                handleClaudeLaunched()
            }
        }

        // 앱 종료 알림 — Claude가 꺼졌을 때
        terminateObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else { return }

            if isClaudeApp(app) {
                handleClaudeTerminated()
            }
        }

        // 앱 포그라운드 전환 알림 — Claude / VSCode / Terminal 창이 활성화됐을 때
        activateObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else { return }

            if isClaudeApp(app) || isDevToolApp(app) {
                handleWorkAppActivated()
            } else {
                // 다른 앱이 포그라운드로 → 작업 앱이 백그라운드로 전환됨
                handleWorkAppDeactivated()
            }
        }

        // 앱 시작 시 이미 Claude가 실행 중이면 플래그만 설정
        let alreadyRunning = NSWorkspace.shared.runningApplications
            .contains(where: { isClaudeApp($0) })
        if alreadyRunning {
            handleClaudeLaunched()
        }
    }

    // Claude 앱 여부 판별
    private func isClaudeApp(_ app: NSRunningApplication) -> Bool {
        let bundleMatch = app.bundleIdentifier?.lowercased().contains("claude") == true
        let nameMatch   = app.localizedName?.lowercased().contains("claude") == true
        // ClaudePet 자기 자신은 제외
        let isSelf      = app.processIdentifier == ProcessInfo.processInfo.processIdentifier
        return (bundleMatch || nameMatch) && !isSelf
    }

    /// 개발 도구 앱 여부 판별 — VS Code · Terminal · iTerm2
    private func isDevToolApp(_ app: NSRunningApplication) -> Bool {
        let bundleId = app.bundleIdentifier?.lowercased() ?? ""
        let name     = app.localizedName?.lowercased() ?? ""
        let isVSCode    = bundleId.contains("com.microsoft.vscode") || name == "visual studio code" || name == "code"
        let isTerminal  = bundleId == "com.apple.terminal" || name == "terminal"
        let isITerm     = bundleId == "com.googlecode.iterm2"  || name == "iterm2"
        return isVSCode || isTerminal || isITerm
    }

    private func handleClaudeLaunched() {
        // CPU 모니터가 Working 전환을 담당하므로 여기선 플래그만 설정
        isClaudeRunning = true
        lastCPUNanos    = 0     // 새 세션 기준값 초기화
    }

    /// Claude / VSCode / Terminal 이 포그라운드(활성화)로 전환됐을 때 호출
    /// Idle_Default 상태에서만 Idle_Working_Prepare 재생 → 자동으로 Idle_Working 으로 넘어감
    private func handleWorkAppActivated() {
        isWorkAppActive = true
        guard !isInTransition, animationState == .idleDefault else { return }
        // 누적된 Idle 복귀 카운터를 초기화
        // (장시간 Idle_Default 상태에서 쌓인 belowThresholdCount가
        //  WorkingPrepare 직후 CPU 폴에서 즉시 인터럽트하는 것을 방지)
        belowThresholdCount = 0
        switchAnimation(to: .idleWorkingPrepare)
    }

    /// 다른 앱이 포그라운드로 전환됐을 때 호출 — 작업 앱이 백그라운드로 이동
    private func handleWorkAppDeactivated() {
        isWorkAppActive = false
        guard animationState.isWorkingState else { return }
        isInTransition = false
        switchAnimation(to: .idleDefault)
    }

    private func handleClaudeTerminated() {
        isClaudeRunning      = false
        isWorkAppActive      = false
        aboveThresholdCount  = 0
        belowThresholdCount  = 0
        lastCPUNanos         = 0
        // Working 중이면 즉시 Idle_Default로 복귀
        guard animationState.isWorkingState else { return }
        isInTransition = false
        switchAnimation(to: .idleDefault)
    }

    // MARK: - CPU 기반 작업 감지
    // Claude 프로세스의 CPU 사용률을 1초 간격으로 샘플링합니다.
    // 임계값을 연속으로 초과하면 WorkingPrepare → Working 진입,
    // 임계값 미만이 연속으로 지속되면 Idle_Default로 복귀합니다.
    private func startCPUMonitor() {
        cpuTimer?.invalidate()
        cpuTimer = Timer.scheduledTimer(withTimeInterval: cpuPollIntervalSec, repeats: true) { _ in
            guard isClaudeRunning else {
                lastCPUNanos = 0
                return
            }

            guard let currentNanos = getClaudeTotalNanos() else {
                lastCPUNanos = 0
                return
            }

            let prev = lastCPUNanos
            lastCPUNanos = currentNanos

            guard prev > 0 else { return }   // 첫 샘플은 기준값만 저장

            // 1초간 소비된 CPU 나노초 → 퍼센트 변환
            let deltaNanos  = currentNanos - prev
            let cpuPercent  = deltaNanos / (cpuPollIntervalSec * 1_000_000_000.0) * 100.0

            DispatchQueue.main.async {
                if cpuPercent > cpuWorkingPercent {
                    // ── 임계값 초과 → Working 진입 카운터 증가 ──────
                    aboveThresholdCount += 1
                    belowThresholdCount  = 0
                    if aboveThresholdCount >= workingConfirmCount {
                        if animationState == .idleDefault && !isInTransition {
                            switchAnimation(to: .idleWorkingPrepare)
                        }
                    }
                } else if cpuPercent < cpuIdlePercent {
                    // ── 임계값 미만 → Idle 복귀 카운터 증가 ─────────
                    // WorkingPrepare 재생 중에는 카운터를 누적하지 않음
                    // (짧은 전환 애니메이션이 CPU 폴에 의해 끊기는 것을 방지)
                    guard animationState != .idleWorkingPrepare else { return }
                    belowThresholdCount += 1
                    aboveThresholdCount  = 0
                    if belowThresholdCount >= idleConfirmCount {
                        // 작업 앱이 포그라운드인 동안에는 CPU와 무관하게 Working 유지
                        if animationState == .idleWorking && !isWorkAppActive {
                            isInTransition = false
                            switchAnimation(to: .idleDefault)
                        }
                    }
                }
                // 중간 구간은 카운터 유지 (히스테리시스)
            }
        }
    }

    /// Claude 프로세스의 누적 CPU 시간을 나노초로 반환합니다.
    /// proc_pidinfo + mach_timebase_info 를 사용하며 별도 권한 불필요.
    private func getClaudeTotalNanos() -> Double? {
        let apps = NSWorkspace.shared.runningApplications.filter { isClaudeApp($0) }
        guard let app = apps.first else { return nil }

        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let ret  = proc_pidinfo(app.processIdentifier, PROC_PIDTASKINFO, 0, &info, size)
        guard ret == Int32(MemoryLayout<proc_taskinfo>.stride) else { return nil }

        // Mach 절대 시간 단위 → 나노초 변환
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let totalMach = info.pti_total_user + info.pti_total_system
        return Double(totalMach) * Double(tb.numer) / Double(tb.denom)
    }

    // MARK: - 충격 감지 (IOKit HID 가속도계)
    /// Apple Silicon 내장 BMI286 가속도계를 IOKit HID 로 직접 읽습니다.
    /// 디바이스 매칭은 런루프 기반 비동기로 동작하며,
    /// 충격이 감지되면 handleAccelerometerHit() 를 호출합니다.
    private func startAccelerometerDetection() {
        let detector = AccelerometerDetector()
        detector.impactThreshold = accelImpactThreshold
        detector.cooldownSec     = accelCooldownSec
        detector.onImpact        = { handleAccelerometerHit() }
        detector.start()
        accelDetector = detector
    }

    /// 충격 감지 시 호출 — Idle_Touch 트리거
    private func handleAccelerometerHit() {
        guard !isInTransition else { return }
        guard animationState.isPrimaryInteractionState else { return }

        triggerHaptic()
        switchAnimation(to: .idleTouch)
        scheduleTouchWalkTimeout()
    }

    // MARK: - 햅틱 피드백

    /// 살짝 누름용 — 2회 약한 햅틱
    private func triggerHaptic() {
        let p = NSHapticFeedbackManager.defaultPerformer
        p.perform(.levelChange, performanceTime: .now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            p.perform(.levelChange, performanceTime: .now)
        }
    }

    /// 세게 누름용 — 강한 햅틱 4회, 짧은 주기(60ms)
    private func triggerStrongHaptics() {
        let p = NSHapticFeedbackManager.defaultPerformer
        let interval: Double = 0.06
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) {
                p.perform(.generic, performanceTime: .now)
            }
        }
    }

    /// 세게 누름용 — 좌우 흔들기 애니메이션 (5회 진동 후 복귀)
    private func triggerShakeAnimation() {
        let amount: CGFloat = 6
        let d: Double = 0.03
        // 첫 이동은 animation 없이 즉시 점프 →
        // touch 스프라이트 교체와 완전히 같은 프레임에서 흔들림 시작
        shakeOffset = amount
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 1) {
            withAnimation(.easeInOut(duration: d)) { shakeOffset = -amount }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 2) {
            withAnimation(.easeInOut(duration: d)) { shakeOffset =  amount }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 3) {
            withAnimation(.easeInOut(duration: d)) { shakeOffset = -amount }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 4) {
            withAnimation(.easeInOut(duration: d)) { shakeOffset =  amount }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 5) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) { shakeOffset = 0 }
        }
    }

    // MARK: - 정리
    private func cleanup() {
        workItem?.cancel()
        touchWalkTimeoutItem?.cancel()
        walkTimer?.invalidate()
        walkTimer = nil
        randomTimer?.invalidate()
        cpuTimer?.invalidate()
        accelDetector?.stop()
        accelDetector = nil
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        let nc = NSWorkspace.shared.notificationCenter
        if let o = workspaceObserver { nc.removeObserver(o) }
        if let o = terminateObserver { nc.removeObserver(o) }
        if let o = activateObserver  { nc.removeObserver(o) }
    }

    private var overlayWindow: NSWindow? {
        NSApplication.shared.windows.first(
            where: { $0.styleMask.contains(.borderless) && $0.level == .floating }
        )
    }
}

// MARK: - InteractionOverlay

/// Force Touch 트랙패드의 압력을 감지하는 투명 오버레이입니다.
///
/// - mouseUp (force click 없음) → onLightPress  (살짝 누름 — Idle_Smile)
/// - pressureChange stage 2    → onForcePress  (세게 누름 — Idle_Touch)
///
/// Force Click 시에는 mouseDown → pressureChange(stage2) → mouseUp 순으로 이벤트가 오므로
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

    // MARK: -

    final class PressView: NSView {
        var activeHeight: CGFloat = 0
        var onLightPress: ((Bool) -> Void)?
        var onForcePress: ((Bool) -> Void)?
        var onRightClick: (() -> Void)?

        /// Force Click 발생 여부 — mouseDown 마다 초기화
        private var forceTriggered = false
        private var pressStartedOnLeftHalf = true

        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard isPointInInteractiveArea(point) else { return nil }
            return super.hitTest(point)
        }

        /// 눌림 시작 — 아직 Smile/Touch 를 결정하지 않음
        override func mouseDown(with event: NSEvent) {
            forceTriggered = false
            pressStartedOnLeftHalf = isLeftHalf(for: event)
        }

        /// 압력 변화 — stage 2 (Force Click) 도달 시 Touch 즉시 트리거
        override func pressureChange(with event: NSEvent) {
            guard event.stage == 2, !forceTriggered else { return }
            forceTriggered = true
            onForcePress?(pressStartedOnLeftHalf)
        }

        /// 손 뗌 — Force Click 없었으면 Smile 트리거
        override func mouseUp(with event: NSEvent) {
            if !forceTriggered {
                onLightPress?(pressStartedOnLeftHalf)
            }
            forceTriggered = false
        }

        /// 우클릭 (두 손가락 클릭) — Jumping 트리거
        override func rightMouseUp(with event: NSEvent) {
            onRightClick?()
        }

        private func isLeftHalf(for event: NSEvent) -> Bool {
            let localPoint = convert(event.locationInWindow, from: nil)
            return localPoint.x < bounds.width / 2
        }

        private func isPointInInteractiveArea(_ point: NSPoint) -> Bool {
            let interactiveMaxY = min(bounds.height, activeHeight)
            return point.y <= interactiveMaxY
        }
    }
}
