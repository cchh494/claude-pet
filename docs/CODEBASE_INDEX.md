# Codebase Index

## 프로젝트 개요

이 저장소는 SwiftUI와 AppKit을 함께 사용하는 macOS 데스크톱 펫 앱입니다. 앱은 일반 윈도우 대신 borderless floating overlay window를 띄우고, 스프라이트 시트 기반 애니메이션과 입력 이벤트를 결합해 Claude 캐릭터를 화면 위에 표시합니다.

## 최상위 구조

### `/Users/main/Documents/claude-pet/ClaudePet`

- 앱의 실제 소스 코드와 에셋이 들어 있습니다.
- 주요 런타임 로직은 대부분 `ContentView.swift`에 집중되어 있습니다.

### `/Users/main/Documents/claude-pet/ClaudePet.xcodeproj`

- Xcode 프로젝트 설정 파일입니다.
- 타깃, 빌드 설정, 권한 설명 문자열, 배포 타깃 등이 포함됩니다.

### `/Users/main/Documents/claude-pet/Asset`

- 원본 또는 보조 스프라이트 자산이 보관된 것으로 보입니다.
- 현재 앱 런타임은 주로 `ClaudePet/Assets.xcassets`를 사용합니다.

### `/Users/main/Documents/claude-pet/docs`

- 코드베이스 분석 문서와 코드리뷰 문서를 저장하는 폴더입니다.

### `/Users/main/Documents/claude-pet/md`

- 코드 작성 전에 먼저 읽는 운영 문서를 저장하는 폴더입니다.

## 핵심 파일 인덱스

### `/Users/main/Documents/claude-pet/ClaudePet/ClaudePetApp.swift`

역할:
- 앱 진입점
- borderless overlay window 생성
- 초기 위치와 크기 결정

핵심 포인트:
- `AppDelegate`가 앱 시작 시 `NSWindow`를 직접 생성합니다.
- 스프라이트 크기는 `baseSpriteSize * spriteScale`로 계산합니다.
- `ContentView()`를 `NSHostingView`로 감싸 창 콘텐츠로 주입합니다.

### `/Users/main/Documents/claude-pet/ClaudePet/ContentView.swift`

역할:
- 상태 머신 중심 파일
- 애니메이션 프레임 재생
- 클릭, Force Click, 우클릭 처리
- 마우스 흔들기 감지
- CPU 기반 작업 상태 감지
- 창 이동과 복귀 제어
- 워크스페이스 앱 활성화/종료 감지

핵심 상태:
- `animationState`
- `currentFrame`
- `currentRepeat`
- `isInTransition`
- `isClaudeRunning`
- `isWorkAppActive`
- `aboveThresholdCount`
- `belowThresholdCount`

주요 기능 블록:
- `switchAnimation`, `scheduleNextFrame`: 애니메이션 엔진
- `handleTap`, `handleForcePress`, `handleRightClick`: 사용자 입력 처리
- `startRandomTimer`: 랜덤 인터럽트 상태 전환
- `startMouseShakeDetection`, `handleShake`: 마우스 흔들기 기반 상호작용
- `startWalkMovement`: `idleTouchWalk` 상태의 실제 창 이동
- `setupWorkspaceObserver`: 실행/종료/활성화 앱 추적
- `startCPUMonitor`, `getClaudeTotalNanos`: CPU 기반 작업 감지
- `cleanup`: 타이머, 옵저버, 감지기 정리

### `/Users/main/Documents/claude-pet/ClaudePet/PetAnimation.swift`

역할:
- 애니메이션 상태 enum 정의
- 상태별 에셋 이름, 프레임 길이, 전이 규칙 정의

설계 특징:
- 애니메이션 데이터가 코드에 하드코딩되어 있습니다.
- 상태 머신의 전이 규칙이 이 파일에 모여 있어 변경 영향 범위를 예측하기 쉽습니다.

### `/Users/main/Documents/claude-pet/ClaudePet/AccelerometerDetector.swift`

역할:
- IOKit HID 기반 충격 감지기
- Apple Silicon 내장 센서에서 리포트를 받아 임계값 초과 시 콜백 실행

현재 상태:
- 구현은 존재하지만 `ContentView.onAppear`에서 비활성화되어 있어 런타임 기본 경로에는 포함되지 않습니다.

### `/Users/main/Documents/claude-pet/README.md`

역할:
- 프로젝트에 대한 짧은 소개만 포함

상태:
- 개발자 온보딩에 필요한 실행 방법, 구조 설명, 권한 요구사항은 부족합니다.

## 런타임 흐름

1. 앱 시작 시 `ClaudePetApp`이 `AppDelegate`를 통해 overlay window를 생성합니다.
2. window root view로 `ContentView`가 로드됩니다.
3. `onAppear`에서 기본 idle 상태, 랜덤 타이머, 마우스 흔들기 감지, 워크스페이스 옵저버, CPU 모니터가 시작됩니다.
4. 입력 이벤트 또는 시스템 상태 변화에 따라 `animationState`가 바뀌고 `scheduleNextFrame()`이 다음 프레임을 예약합니다.
5. `idleTouchWalk`에서는 실제 `NSWindow` 위치를 이동시키며 종료 시 다시 `idleDefault`로 복귀합니다.
6. 앱 종료 또는 뷰 해제 시 각종 타이머와 옵저버를 정리합니다.

## 상태 전이 개요

- `idleDefault` -> `idleSmile`, `idleBoring`, `idleJumping`
- `idleDefault` -> `idleTouch` -> `idleTouchWalk` -> `idleDefault`
- `idleDefault` -> `idleWorkingPrepare` -> `idleWorking`
- `idleWorking` -> `idleDefault`
- 일부 입력은 `isInTransition`과 `isPrimaryInteractionState` 조건에 의해 차단됩니다.

## 의존 기술

- SwiftUI
- AppKit
- NSWorkspace notifications
- NSHapticFeedbackManager
- Darwin `proc_pidinfo`
- IOKit HID

## 코드 구조상 주의점

- 핵심 동작이 `ContentView.swift` 하나에 많이 몰려 있어 기능 추가 시 결합도가 빠르게 높아질 수 있습니다.
- 타이머와 비동기 콜백 기반 상태 변경이 많아서 상태 전환 경쟁 조건을 항상 의식해야 합니다.
- 시스템 이벤트 감지는 macOS 버전, 권한, 하드웨어 환경에 따라 실제 동작 편차가 있을 수 있습니다.
