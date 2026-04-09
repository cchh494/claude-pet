import Foundation
import Combine

/// 펫의 배고픔 수치를 관리하는 싱글턴.
///
/// - 수치는 0 ~ PetConfig.hungerMax (기본 100) 범위
/// - 매 PetConfig.hungerDecayIntervalSec (기본 300초 = 5분) 마다 1씩 감소
/// - PetConfig.hungerThreshold (기본 20) 이하이면 isHungry == true
/// - feed() 호출 시 TypingCounter.feedTypingCost 를 소비하고
///   hungerRestore 만큼 수치를 회복합니다
///
/// 수치는 UserDefaults 에 저장되어 앱 재실행 후에도 유지됩니다.
final class HungerManager: ObservableObject {

    // MARK: - 싱글턴

    static let shared = HungerManager()

    // MARK: - 알림 이름 (별도 NSHostingView 에서도 안정적으로 갱신하기 위해 사용)

    static let didChange = Notification.Name("HungerManagerDidChange")

    // MARK: - Published

    /// 현재 배고픔 수치 (0 ~ hungerMax)
    @Published private(set) var hunger: Double

    /// 배고픔 경보 플래그 — hungerThreshold 이하이면 true
    @Published private(set) var isHungry: Bool

    // MARK: - Private

    private static let storageKey = "petHunger"

    /// 타이머 1틱 간격 (초) — 1초마다 (1 / decayIntervalSec) 씩 감소
    private let tickInterval: Double = 1.0
    private var decayTimer: Timer?

    // MARK: - Init

    private init() {
        let saved = UserDefaults.standard.object(forKey: Self.storageKey) as? Double
        let initial = saved ?? PetConfig.hungerMax
        self.hunger  = initial
        self.isHungry = initial <= PetConfig.hungerThreshold
    }

    // MARK: - 공개 API

    /// 배고픔 감소 타이머를 시작합니다.
    /// ContentView.onAppear 에서 호출합니다.
    func startHungerTimer() {
        decayTimer?.invalidate()
        let decayPerTick = tickInterval / PetConfig.hungerDecayIntervalSec
        decayTimer = Timer.scheduledTimer(
            withTimeInterval: tickInterval,
            repeats: true
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.applyDecay(amount: decayPerTick) }
        }
    }

    /// 배고픔 감소 타이머를 정지합니다.
    /// ContentView.onDisappear(cleanup) 에서 호출합니다.
    func stopHungerTimer() {
        decayTimer?.invalidate()
        decayTimer = nil
    }

    /// 밥주기를 시도합니다.
    ///
    /// 성공 조건:
    ///   1. TypingCounter.shared.count >= PetConfig.feedTypingCost
    ///   2. 현재 배고픔 수치가 최대값 미만
    ///
    /// - Returns: 실제로 밥을 줬으면 true, 조건 불충족이면 false
    @discardableResult
    func feed() -> Bool {
        guard TypingCounter.shared.count >= PetConfig.feedTypingCost else { return false }
        guard hunger < PetConfig.hungerMax else { return false }

        TypingCounter.shared.consume(PetConfig.feedTypingCost)

        let prevIsHungry = isHungry
        hunger   = min(PetConfig.hungerMax, hunger + PetConfig.feedHungerRestore)
        isHungry = hunger <= PetConfig.hungerThreshold
        UserDefaults.standard.set(hunger, forKey: Self.storageKey)

        // 상태 변화 여부와 무관하게 항상 알림 발송 (UI 즉시 갱신)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        return true
    }

    // MARK: - [DEBUG] 디버그 전용 — 출시 전 삭제 예정

    /// 배고픔 수치를 강제로 amount 만큼 차감합니다.
    /// [DEBUG] 디버그 버튼용 — 실제 게임 로직에 사용하지 마세요.
    func debugDecreaseHunger(by amount: Double) {
        let prevIsHungry = isHungry
        hunger   = max(0, hunger - amount)
        isHungry = hunger <= PetConfig.hungerThreshold
        UserDefaults.standard.set(hunger, forKey: Self.storageKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    // MARK: - Private

    private func applyDecay(amount: Double) {
        let prevIsHungry = isHungry
        hunger   = max(0, hunger - amount)
        isHungry = hunger <= PetConfig.hungerThreshold
        UserDefaults.standard.set(hunger, forKey: Self.storageKey)

        // isHungry 상태가 바뀐 경우에만 알림 발송 (과도한 알림 방지)
        if isHungry != prevIsHungry {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }
}
