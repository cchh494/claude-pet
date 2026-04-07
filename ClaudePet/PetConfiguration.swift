import CoreGraphics

/// 앱 전역 설정 상수를 한 곳에서 관리합니다.
/// 값을 조정하려면 이 파일만 수정하면 됩니다.
enum PetConfig {

    // MARK: - 랜덤 인터럽트
    static let randomInterruptIntervalSec: Double = 6.0   // 체크 주기 (초)
    static let smileProbability:           Double = 0.30  // Idle_Smile 진입 확률
    static let boringProbability:          Double = 0.20  // Idle_Boring 진입 확률
    static let jumpingProbability:         Double = 0.15  // Idle_Jumping 진입 확률

    // MARK: - 마우스 흔들기 감지
    static let shakeDirectionChanges: Int     = 5         // 흔들기 인식 최소 방향 전환 횟수
    static let shakeTimeWindowSec:    Double  = 1.0       // 감지 시간 윈도우 (초)
    static let shakeMinMovePx:        CGFloat = 20.0      // 방향 전환 최소 이동 거리 (px)
    static let touchWalkTimeoutSec:   Double  = 2.5       // 흔들기 종료 판정 시간 (초)

    // MARK: - Touch_Walk 이동
    static let walkSpeed:         CGFloat = 400.0         // 이동 속도 (px/초)
    static let walkTotalDistance: CGFloat = 100.0         // 최대 이동 거리 (px)

    // MARK: - 충격 감지 (IOKit HID 가속도계)
    static let accelImpactThreshold: Double = 2.0         // 임계값 (g), 낮추면 더 민감
    static let accelCooldownSec:     Double = 0.8         // 연속 트리거 방지 쿨다운 (초)

    // MARK: - CPU 기반 작업 감지
    static let cpuPollIntervalSec:  Double = 1.0          // 샘플링 주기 (초)
    static let cpuWorkingPercent:   Double = 15.0         // Working 진입 CPU% 임계값
    static let cpuIdlePercent:      Double = 5.0          // Idle 복귀 CPU% 임계값
    static let workingConfirmCount: Int    = 2            // Working 확정 연속 횟수
    static let idleConfirmCount:    Int    = 3            // Idle 복귀 연속 횟수

    // MARK: - 자율 이동 (Autonomous Walk)
    static let autonomousWalkProbability: Double  = 0.0    // 랜덤 타이머에서 자율 이동 진입 확률 (0 = 비활성화)
    static let autonomousWalkSpeed:       CGFloat = 80.0   // 이동 속도 (px/초)
    static let autonomousWalkDistance:    CGFloat = 120.0  // 최대 이동 거리 (px)
    static let autonomousWalkCooldownSec: Double  = 10.0   // 자율 이동 후 재진입 금지 시간 (초)

    // MARK: - 마우스 추적 (Mouse Follow)
    static let dockZoneRatio:             Double  = 1.0    // 화면 하단 몇 %를 Dock 영역으로 볼 것인가 (1.0 = 화면 전체)
    static let mouseFollowSpeed:          CGFloat = 60.0   // 기본 추적 속도 (px/초)
    static let mouseFollowMinDistancePx:  CGFloat = 12.0   // 이 거리 미만이면 멈춤 (px)
    static let mouseFollowPauseChancePerSec: Double = 1.35 // 초당 멈출 확률 (평균 ~3초마다 1회 일시정지)
    static let mouseFollowPauseMinSec:    Double  = 3.0    // 일시정지 최소 시간 (초)
    static let mouseFollowPauseMaxSec:    Double  = 10.0    // 일시정지 최대 시간 (초)

    // MARK: - 대사
    static let dialogueDisplaySec:        Double = 3.5    // 대사 표시 지속 시간 (초)
    static let workingDialogueIntervalSec: Double = 12.0  // Working 중 대사 출력 주기 (초)
}
