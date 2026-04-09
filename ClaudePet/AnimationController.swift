import AppKit
import Combine
import SwiftUI

/// 펫의 애니메이션 상태 머신과 인터랙션 이펙트를 담당하는 ObservableObject.
///
/// ContentView 에서 `@StateObject` 로 보유하며, 뷰는 published 프로퍼티만 읽고
/// 사용자 이벤트(탭·포스터치·우클릭·흔들기)는 핸들러 메서드를 호출해 위임합니다.
///
/// ### 윈도우 접근
/// 이동(Walk) 시 실제 창 위치를 조작해야 하므로 `windowProvider` 클로저를 주입합니다.
/// AppDelegate 가 창을 생성한 직후 이 프로퍼티를 설정해 주어야 합니다.
@MainActor
final class AnimationController: ObservableObject {

    // MARK: - Published (뷰가 구독하는 상태)

    @Published private(set) var animationState: PetAnimationState = .idleDefault
    @Published private(set) var currentFrame:   Int = 0
    @Published private(set) var walkDirection:  CGFloat = 0
    @Published private(set) var isInTransition: Bool = false

    /// 살짝 누름 스케일 이펙트
    @Published var pressScale:   CGFloat = 1.0
    /// 세게 누름 좌우 흔들기 오프셋
    @Published var shakeOffset:  CGFloat = 0
    /// 하트 이펙트
    @Published var heartOpacity: Double  = 0
    @Published var heartYOffset: CGFloat = 0
    @Published var heartScale:   CGFloat = 0.85

    // MARK: - 외부 주입

    /// 스프라이트 창 참조를 반환하는 클로저.
    /// AppDelegate 에서 창 생성 후 바로 설정합니다.
    var windowProvider: (() -> NSWindow?)?

    // MARK: - Private

    private var currentRepeat: Int = 0
    private var heartEffectID: Int = 0

    private var workItem:              DispatchWorkItem?
    private var touchWalkTimeoutItem:  DispatchWorkItem?
    private var walkTimer:             Timer?
    private var walkDistanceRemaining: CGFloat = 0
    private var preferredWalkDirection: CGFloat?

    // 자율 이동
    private var autonomousWalkTimer:   Timer?
    private var lastAutonomousWalkTime: Date?

    // 마우스 추적
    private var mouseFollowTimer:      Timer?
    private var mouseFollowMonitor:    Any?
    private var isMouseFollowActive:   Bool = false
    private var mouseFollowResumeItem: DispatchWorkItem?

    // MARK: - Computed

    private var frameMs:    [Double] { animationState.frameDurationsMs }
    private var frameCount: Int      { frameMs.count }

    // MARK: - 애니메이션 엔진

    /// 상태를 전환하고 첫 프레임부터 재생 시작
    func switchAnimation(to state: PetAnimationState) {
        workItem?.cancel()
        touchWalkTimeoutItem?.cancel()
        walkTimer?.invalidate()
        walkTimer = nil
        autonomousWalkTimer?.invalidate()
        autonomousWalkTimer = nil

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
        let delaySec      = frameMs[currentFrame % frameMs.count] / 1000.0
        let capturedState = animationState

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.animationState == capturedState else { return }

            let nextFrame  = self.currentFrame + 1
            let transition = self.animationState.transition

            if nextFrame >= self.frameCount {
                // ── 사이클 1회 완료 ─────────────────────────────────
                if transition.isTransition {
                    let newRepeat = self.currentRepeat + 1
                    if newRepeat >= transition.repeatCount {
                        self.switchAnimation(to: transition.nextState)
                    } else {
                        self.currentRepeat = newRepeat
                        self.currentFrame  = 0
                        self.scheduleNextFrame()
                    }
                } else {
                    // 지속 재생 — 무한 루프
                    self.currentFrame = 0
                    self.scheduleNextFrame()
                }
            } else {
                self.currentFrame = nextFrame
                self.scheduleNextFrame()
            }
        }

        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySec, execute: item)
    }

    // MARK: - 인터랙션 핸들러

    /// 살짝 누름(일반 클릭) → Idle_Smile + 스케일·하트 이펙트
    func handleTap() {
        guard !isInTransition, animationState.isPrimaryInteractionState else { return }
        triggerHaptic()
        applyPressScale()
        triggerHeartEffect()
        showDialogue(for: .smile)
        switchAnimation(to: .idleSmile)
    }

    /// 우클릭(두 손가락 클릭) → 메뉴 HUD 토글
    func handleRightClick() {
        triggerHaptic()
        NotificationCenter.default.post(name: .claudePetToggleMenu, object: nil)
    }

    /// 세게 누름(Force Click) → Idle_Touch + 좌우 흔들기
    func handleForcePress(isLeftHalf: Bool) {
        // 배고픈 상태에서는 꾹누름 반응 없음
        guard animationState != .idleHungry else { return }
        preferredWalkDirection = isLeftHalf ? 1.0 : -1.0
        triggerStrongHaptics()
        showDialogue(for: .touch)
        switchAnimation(to: .idleTouch)
        scheduleTouchWalkTimeout()
        // 스프라이트 전환 이후 틱에서 흔들기 시작
        DispatchQueue.main.async { [weak self] in self?.triggerShakeAnimation() }
    }

    /// 마우스 흔들기 감지 → Idle_Touch
    func handleShake() {
        // idleTouchWalk 중에는 walk 타이머가 복귀를 직접 제어하므로 무시
        guard animationState != .idleTouchWalk else { return }
        guard !isInTransition, animationState == .idleDefault else { return }
        switchAnimation(to: .idleTouch)
    }

    /// 가속도계 충격 감지 → Idle_Touch
    func handleAccelerometerHit() {
        guard !isInTransition, animationState.isPrimaryInteractionState else { return }
        triggerHaptic()
        switchAnimation(to: .idleTouch)
        scheduleTouchWalkTimeout()
    }

    // MARK: - Working 상태 진입/종료

    /// 작업 앱 포그라운드 전환 시 호출.
    /// 실제로 Working 상태로 진입했으면 true, 조건 불충족으로 무시됐으면 false 반환.
    @discardableResult
    func handleWorkAppActivated(resetBelowCount: @escaping () -> Void) -> Bool {
        guard !isInTransition, animationState == .idleDefault else { return false }
        resetBelowCount()
        showDialogue(for: .workingStart)
        switchAnimation(to: .idleWorkingPrepare)
        return true
    }

    /// 다른 앱이 포그라운드로 전환 시 호출
    func handleWorkAppDeactivated() {
        guard animationState.isWorkingState else { return }
        showDialogue(for: .workingEnd)
        isInTransition = false
        switchAnimation(to: .idleDefault)
    }

    /// CPU 임계값 초과 → Working 진입 시도
    func handleCPUHighLoad() {
        guard animationState == .idleDefault, !isInTransition else { return }
        switchAnimation(to: .idleWorkingPrepare)
    }

    /// Claude 앱 종료 시 Working 상태 강제 복귀
    func handleClaudeTerminated() {
        guard animationState.isWorkingState else { return }
        isInTransition = false
        switchAnimation(to: .idleDefault)
    }

    /// isInTransition 플래그를 외부에서 초기화할 때 사용
    func clearTransitionFlag() {
        isInTransition = false
    }

    // MARK: - 배고픔 상태 진입/복귀

    /// 배고픔 수치가 임계값 이하로 떨어졌을 때 호출.
    /// idleDefault / idleWalk 상태에서만 idleHungry 로 전환합니다.
    func handleHungerBecameLow() {
        guard !isInTransition else { return }
        guard animationState == .idleDefault || animationState == .idleWalk else { return }
        showDialogue(for: .hungry)
        switchAnimation(to: .idleHungry)
    }

    /// 밥을 먹어 배고픔이 임계값 초과로 회복됐을 때 호출.
    func handleHungerRestored() {
        guard animationState == .idleHungry else { return }
        switchAnimation(to: .idleDefault)
    }

    /// 배고픔 상태에서 밥을 받았을 때 호출 — 대사 표시용.
    func handleFed() {
        showDialogue(for: .fed)
    }

    // MARK: - 대사

    func showDialogue(for trigger: DialogueTrigger, duration: Double? = nil) {
        guard let line = DialogueCatalog.randomLine(for: trigger) else { return }
        DialogueManager.shared.show(line, duration: duration ?? PetConfig.dialogueDisplaySec)
    }

    // MARK: - Touch_Walk 이동

    private func startWalkMovement() {
        guard let window = windowProvider?() else { return }

        let screen   = NSScreen.main ?? NSScreen.screens[0]
        let currentX = window.frame.origin.x
        let minX: CGFloat = 0
        let maxX: CGFloat = screen.frame.width - window.frame.width

        let requested = preferredWalkDirection
        preferredWalkDirection = nil

        guard let direction = resolveWalkDirection(
            requested:   requested,
            canGoRight:  currentX < maxX - 1,
            canGoLeft:   currentX > minX + 1
        ) else {
            // 이동 불가 → 즉시 Default 복귀
            DispatchQueue.main.async { [weak self] in
                guard let self, self.animationState == .idleTouchWalk else { return }
                self.isInTransition = false
                self.switchAnimation(to: .idleDefault)
            }
            return
        }

        walkDirection          = direction
        walkDistanceRemaining  = PetConfig.walkTotalDistance

        let tickInterval:   Double   = 1.0 / 60.0
        let pixelsPerTick:  CGFloat  = PetConfig.walkSpeed * CGFloat(tickInterval)

        walkTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.animationState == .idleTouchWalk else { timer.invalidate(); return }
            guard let window = self.windowProvider?() else { timer.invalidate(); return }

            let screen   = NSScreen.main ?? NSScreen.screens[0]
            let currentX = window.frame.origin.x
            let newX     = currentX + (self.walkDirection * pixelsPerTick)
            let minX: CGFloat = 0
            let maxX: CGFloat = screen.frame.width - window.frame.width
            let clampedX = max(minX, min(maxX, newX))
            let hitEdge  = abs(clampedX - newX) > 0.1

            window.setFrameOrigin(CGPoint(x: clampedX, y: window.frame.origin.y))
            self.walkDistanceRemaining -= pixelsPerTick

            if self.walkDistanceRemaining <= 0 || hitEdge {
                timer.invalidate()
                self.walkTimer = nil
                DispatchQueue.main.async {
                    guard self.animationState == .idleTouchWalk else { return }
                    self.isInTransition = false
                    self.switchAnimation(to: .idleDefault)
                }
            }
        }
    }

    /// 요청 방향과 가능 방향을 종합해 실제 이동 방향을 결정합니다.
    /// 이동이 불가능하면 nil 을 반환합니다.
    private func resolveWalkDirection(
        requested:  CGFloat?,
        canGoRight: Bool,
        canGoLeft:  Bool
    ) -> CGFloat? {
        if let r = requested {
            if r > 0, canGoRight { return  1.0 }
            if r < 0, canGoLeft  { return -1.0 }
            if canGoRight        { return  1.0 }
            if canGoLeft         { return -1.0 }
            return nil
        }
        // 방향 힌트 없음
        if canGoRight && canGoLeft { return Bool.random() ? 1.0 : -1.0 }
        if canGoRight              { return  1.0 }
        if canGoLeft               { return -1.0 }
        return nil
    }

    func scheduleTouchWalkTimeout() {
        let touchDuration = PetAnimationState.idleTouch.frameDurationsMs.reduce(0, +) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + touchDuration) { [weak self] in
            self?.resetTouchWalkTimeout()
        }
    }

    private func resetTouchWalkTimeout() {
        touchWalkTimeoutItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.animationState == .idleTouchWalk else { return }
            self.isInTransition = false
            self.switchAnimation(to: .idleDefault)
        }
        touchWalkTimeoutItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PetConfig.touchWalkTimeoutSec,
            execute: item
        )
    }

    // MARK: - 햅틱 피드백

    /// 살짝 누름용 — 약한 햅틱 2회
    private func triggerHaptic() {
        let p = NSHapticFeedbackManager.defaultPerformer
        p.perform(.levelChange, performanceTime: .now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            p.perform(.levelChange, performanceTime: .now)
        }
    }

    /// 세게 누름용 — 강한 햅틱 4회 (60ms 간격)
    private func triggerStrongHaptics() {
        let p = NSHapticFeedbackManager.defaultPerformer
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                p.perform(.generic, performanceTime: .now)
            }
        }
    }

    // MARK: - 비주얼 이펙트

    /// 눌린 느낌 스케일 애니메이션
    private func applyPressScale() {
        withAnimation(.easeIn(duration: 0.07)) { pressScale = 0.88 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
                self?.pressScale = 1.0
            }
        }
    }

    /// 하트 떠오르기 이펙트
    private func triggerHeartEffect() {
        heartEffectID += 1
        let id = heartEffectID

        heartOpacity = 0
        heartYOffset = 10
        heartScale   = 0.8

        withAnimation(.easeOut(duration: 0.16)) {
            heartOpacity = 1; heartYOffset = -6; heartScale = 1.0
        }
        withAnimation(.easeOut(duration: 2.4)) { heartYOffset = -54 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.heartEffectID == id else { return }
            withAnimation(.easeIn(duration: 0.9)) {
                self.heartOpacity = 0; self.heartScale = 1.08
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.heartEffectID == id else { return }
            self.heartYOffset = 0; self.heartScale = 0.85
        }
    }

    /// 좌우 흔들기 애니메이션 (5회 진동 후 스프링 복귀)
    private func triggerShakeAnimation() {
        let amount: CGFloat = 6
        let d:      Double  = 0.03
        // 배열로 관리해 반복 코드 제거
        let offsets: [(CGFloat, Bool)] = [
            (-amount, false),
            ( amount, false),
            (-amount, false),
            ( amount, false),
            (      0, true ),   // 마지막은 스프링 복귀
        ]
        shakeOffset = amount   // 첫 이동은 즉시 (touch 스프라이트와 같은 프레임)
        for (i, (offset, isLast)) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + d * Double(i + 1)) { [weak self] in
                if isLast {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
                        self?.shakeOffset = offset
                    }
                } else {
                    withAnimation(.easeInOut(duration: d)) {
                        self?.shakeOffset = offset
                    }
                }
            }
        }
    }

    // MARK: - 자율 이동 (Autonomous Walk)

    /// 랜덤 타이머에서 호출 — idle 상태일 때 랜덤 방향으로 자율 이동 시작
    func startAutonomousWalk() {
        guard !isInTransition, animationState == .idleDefault else { return }

        // 쿨다운 확인
        if let last = lastAutonomousWalkTime,
           Date().timeIntervalSince(last) < PetConfig.autonomousWalkCooldownSec {
            return
        }

        lastAutonomousWalkTime = Date()
        preferredWalkDirection = Bool.random() ? 1.0 : -1.0
        switchAnimation(to: .idleWalk)
        startAutonomousWalkMovement()
    }

    private func startAutonomousWalkMovement() {
        guard let window = windowProvider?() else { return }

        let screen   = NSScreen.main ?? NSScreen.screens[0]
        let currentX = window.frame.origin.x
        let minX: CGFloat = 0
        let maxX: CGFloat = screen.frame.width - window.frame.width

        guard let direction = resolveWalkDirection(
            requested:  preferredWalkDirection,
            canGoRight: currentX < maxX - 1,
            canGoLeft:  currentX > minX + 1
        ) else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.animationState == .idleWalk else { return }
                self.isInTransition = false
                self.switchAnimation(to: .idleDefault)
            }
            return
        }
        preferredWalkDirection = nil
        walkDirection = direction

        let tickInterval:  Double   = 1.0 / 60.0
        let pixelsPerTick: CGFloat  = PetConfig.autonomousWalkSpeed * CGFloat(tickInterval)
        var distanceMoved: CGFloat  = 0

        autonomousWalkTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.animationState == .idleWalk else { timer.invalidate(); return }
            guard let window = self.windowProvider?() else { timer.invalidate(); return }

            let screen   = NSScreen.main ?? NSScreen.screens[0]
            let currentX = window.frame.origin.x
            let newX     = currentX + (self.walkDirection * pixelsPerTick)
            let minX: CGFloat = 0
            let maxX: CGFloat = screen.frame.width - window.frame.width
            let clampedX = max(minX, min(maxX, newX))
            let hitEdge  = abs(clampedX - newX) > 0.1

            window.setFrameOrigin(CGPoint(x: clampedX, y: window.frame.origin.y))
            distanceMoved += pixelsPerTick

            if distanceMoved >= PetConfig.autonomousWalkDistance || hitEdge {
                timer.invalidate()
                self.autonomousWalkTimer = nil
                DispatchQueue.main.async {
                    guard self.animationState == .idleWalk else { return }
                    self.isInTransition = false
                    self.switchAnimation(to: .idleDefault)
                }
            }
        }
    }

    // MARK: - 마우스 추적 (Mouse Follow)

    /// ContentView.onAppear 에서 호출 — Dock 영역 마우스 추적 감시 시작
    func startMouseFollowDetection() {
        // 30fps 타이머로 마우스 위치 → 펫 이동
        mouseFollowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tickMouseFollow()
        }

        // 마우스 이동 이벤트로 Dock 진입 감지
        mouseFollowMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.checkMouseFollowEntry()
        }
    }

    /// 마우스가 감지 영역에 진입했는지 확인 → idleWalk 진입
    private func checkMouseFollowEntry() {
        guard !isInTransition, animationState == .idleDefault else { return }
        guard !isMouseFollowActive else { return }  // 이미 추적 중 (일시정지 포함)
        guard isMouseInDockZone() else { return }

        isMouseFollowActive = true
        walkDirection = 0
        switchAnimation(to: .idleWalk)
    }

    /// 30fps 마다 호출 — 마우스 방향으로 조금씩 이동, 중간에 랜덤 일시정지
    private func tickMouseFollow() {
        // 마우스 추적 활성 중이지만 Working 등 다른 상태로 빠진 경우 → 추적 해제
        if isMouseFollowActive {
            let isCompatible = animationState == .idleWalk || animationState == .idleDefault
            if !isCompatible {
                isMouseFollowActive = false
                mouseFollowResumeItem?.cancel()
                mouseFollowResumeItem = nil
                return
            }
        }

        // 추적 활성이 아니면 아무것도 안 함 (타이머는 계속 돌되 checkMouseFollowEntry 가 진입 담당)
        guard isMouseFollowActive else { return }

        // 일시정지 중(idleDefault)이면 resume item 이 처리하므로 대기
        if animationState == .idleDefault { return }

        guard animationState == .idleWalk else { return }
        guard autonomousWalkTimer == nil else { return }  // 자율 이동 우선
        guard let window = windowProvider?() else { return }

        // ── 랜덤 일시정지 ─────────────────────────────────────────
        let pauseChancePerTick = PetConfig.mouseFollowPauseChancePerSec / 30.0
        if Double.random(in: 0..<1) < pauseChancePerTick {
            isInTransition = false
            switchAnimation(to: .idleDefault)

            let pauseSec = Double.random(
                in: PetConfig.mouseFollowPauseMinSec...PetConfig.mouseFollowPauseMaxSec
            )
            mouseFollowResumeItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.isMouseFollowActive else { return }
                guard self.animationState == .idleDefault, !self.isInTransition else { return }
                self.switchAnimation(to: .idleWalk)
            }
            mouseFollowResumeItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + pauseSec, execute: item)
            return
        }

        // ── 마우스 방향으로 이동 ───────────────────────────────────
        let mousePos   = NSEvent.mouseLocation
        let screen     = NSScreen.main ?? NSScreen.screens[0]
        let petCenterX = window.frame.origin.x + window.frame.width / 2.0
        let distance   = mousePos.x - petCenterX

        if abs(distance) < PetConfig.mouseFollowMinDistancePx { return }

        let direction: CGFloat = distance > 0 ? 1.0 : -1.0
        walkDirection = direction

        let pixelsPerTick: CGFloat = PetConfig.mouseFollowSpeed / 30.0
        let moveAmount = min(pixelsPerTick, abs(distance)) * direction

        let minX: CGFloat = 0
        let maxX: CGFloat = screen.frame.width - window.frame.width
        let newX = max(minX, min(maxX, window.frame.origin.x + moveAmount))
        window.setFrameOrigin(CGPoint(x: newX, y: window.frame.origin.y))
    }

    /// 마우스가 감지 영역에 있는지 확인
    private func isMouseInDockZone() -> Bool {
        let mousePos = NSEvent.mouseLocation
        let screen   = NSScreen.main ?? NSScreen.screens[0]
        let dockTopY = screen.frame.origin.y + screen.frame.height * (1.0 - PetConfig.dockZoneRatio)
        return mousePos.y >= dockTopY
    }

    func stopMouseFollowDetection() {
        isMouseFollowActive = false
        mouseFollowResumeItem?.cancel()
        mouseFollowResumeItem = nil
        mouseFollowTimer?.invalidate()
        mouseFollowTimer = nil
        if let m = mouseFollowMonitor { NSEvent.removeMonitor(m) }
        mouseFollowMonitor = nil
    }

    // MARK: - 정리

    func cleanup() {
        workItem?.cancel()
        touchWalkTimeoutItem?.cancel()
        walkTimer?.invalidate()
        walkTimer = nil
        autonomousWalkTimer?.invalidate()
        autonomousWalkTimer = nil
        mouseFollowResumeItem?.cancel()
        mouseFollowResumeItem = nil
        stopMouseFollowDetection()
    }
}

// MARK: - 알림 이름

extension Notification.Name {
    /// 우클릭 시 메뉴 HUD를 열고 닫는 알림
    static let claudePetToggleMenu = Notification.Name("ClaudePet.ToggleMenu")
    /// 밥주기 성공 시 ContentView 에 대사 출력을 요청하는 알림
    static let claudePetFed        = Notification.Name("ClaudePet.Fed")
}
