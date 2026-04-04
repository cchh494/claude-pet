# Code Review Report

## 리뷰 범위

- `/Users/main/Documents/claude-pet/ClaudePet/ClaudePetApp.swift`
- `/Users/main/Documents/claude-pet/ClaudePet/ContentView.swift`
- `/Users/main/Documents/claude-pet/ClaudePet/PetAnimation.swift`
- `/Users/main/Documents/claude-pet/ClaudePet/AccelerometerDetector.swift`
- `/Users/main/Documents/claude-pet/ClaudePet.xcodeproj/project.pbxproj`

## 주요 findings

### 1. 작업 상태 진입이 실제 Claude 실행 여부와 분리되어 있어 오동작할 수 있음

- 심각도: Medium
- 위치: `ContentView.swift:457-518`

`didActivateApplicationNotification`에서 Claude 외에 VS Code, Terminal, iTerm2 활성화도 모두 `handleWorkAppActivated()`로 연결됩니다. 그런데 이 메서드는 `isClaudeRunning` 여부를 확인하지 않고 바로 `idleWorkingPrepare`로 전환합니다. 그 결과 Claude가 실행 중이지 않아도 개발 도구만 활성화되면 펫이 작업 중 애니메이션으로 바뀔 수 있습니다. 코드 주석상 "실제 Working 전환은 CPU 모니터가 담당"이라고 설명하지만, 현재 구현은 활성 앱만으로도 시각 상태를 먼저 바꾸기 때문에 동작 의미가 섞여 있습니다.

권장 대응:
- `handleWorkAppActivated()`에서 `isClaudeRunning`을 함께 검증합니다.
- 또는 "Claude 작업 중"과 "개발 도구 사용 중" 상태를 별도 enum/정책으로 분리합니다.

### 2. 창 위치와 이동 경계 계산이 단일 디스플레이 좌표계를 가정함

- 심각도: Medium
- 위치: `ClaudePetApp.swift:22-33`, `ContentView.swift:326-381`

초기 창 위치는 `NSScreen.main.visibleFrame.maxX`를 쓰지만 Y 좌표는 `bottomMargin` 고정값만 사용합니다. 이후 `idleTouchWalk` 이동 계산은 `minX = 0`, `maxX = screen.frame.width - window.frame.width`로 고정해 전체 좌표계의 원점을 하나의 화면 좌측 하단으로 가정합니다. 멀티 디스플레이 또는 보조 모니터가 음수 좌표를 가지는 환경에서는 창이 예상치 못한 위치로 튀거나 실제 현재 화면 경계를 벗어나지 못할 가능성이 큽니다.

권장 대응:
- 창이 속한 실제 화면의 `visibleFrame.minX/maxX/minY`를 기준으로 클램프합니다.
- 초기 배치와 이동 로직 모두 동일한 좌표계 규칙을 사용하도록 통일합니다.

### 3. 권한 설명 문자열이 현재 구현과 맞지 않아 사용자 혼란을 유발할 수 있음

- 심각도: Medium
- 위치: `ClaudePet.xcodeproj/project.pbxproj:257-260`, `ClaudePet.xcodeproj/project.pbxproj:288-290`

`NSMicrophoneUsageDescription`에는 "맥북을 때렸을 때 충격을 감지하기 위해 마이크를 사용합니다."라고 적혀 있지만, 실제 충격 감지는 `AccelerometerDetector`의 IOKit HID 접근을 전제로 하고 있으며 현재는 아예 비활성화되어 있습니다. 이 설명은 현재 코드와 불일치하고, 권한 요청이 발생할 경우 사용자 신뢰를 해칠 수 있습니다.

권장 대응:
- 실제 사용하지 않는 권한 설명은 제거합니다.
- 추후 센서 기능을 되살릴 경우에도 실제 접근 방식에 맞는 설명으로 수정합니다.

### 4. README가 실행·권한·구조 정보를 거의 제공하지 않아 유지보수 진입 비용이 높음

- 심각도: Low
- 위치: `README.md:1-2`

현재 README는 한 줄 소개만 포함하고 있어, 새로운 기여자가 앱 실행 방법, 핵심 파일, 권한 이슈, 애니메이션 구조를 파악하기 어렵습니다. 작은 프로젝트일수록 진입 문서가 짧더라도 핵심 운영 정보는 필요합니다.

권장 대응:
- 실행 방법
- 핵심 파일 설명
- 입력 방식과 애니메이션 상태
- 권한 및 하드웨어 의존성

## 구조적 관찰

- 장점: 상태 전이 규칙이 `PetAnimation.swift`에 모여 있어 애니메이션 자체는 추적하기 쉽습니다.
- 장점: `switchAnimation()`과 `scheduleNextFrame()` 중심 구조가 비교적 단순해서 디버깅 진입점이 명확합니다.
- 리스크: 상호작용, 워크스페이스 이벤트, CPU 모니터, 창 이동이 모두 `ContentView.swift`에 집중되어 있어 파일 단위 복잡도가 높습니다.
- 리스크: 타이머와 `DispatchQueue.main.asyncAfter`가 섞여 있어 상태 전이 경쟁 조건이 늘어날 여지가 있습니다.

## 개선 우선순위 제안

1. 작업 상태 진입 조건을 실제 의도에 맞게 정리합니다.
2. 멀티 디스플레이 좌표계 처리를 보강합니다.
3. 권한 설명과 실제 센서 전략을 정합성 있게 맞춥니다.
4. README와 내부 문서를 보강해 유지보수 비용을 낮춥니다.

## 테스트 공백

- 자동화 테스트 타깃이 없습니다.
- 상태 전이와 타이머 중심 로직에 대한 단위 테스트가 없습니다.
- 멀티 디스플레이, Claude 미실행 상태, 권한 거부 상태 같은 실제 환경 시나리오 검증 문서가 없습니다.

## 결론

현재 코드는 작은 데스크톱 펫 프로토타입으로서는 흐름이 명확하고 실험 속도도 빠른 편입니다. 다만 시스템 이벤트와 창 제어를 다루는 특성상, 환경 의존성이 강한 부분을 지금처럼 단일 파일에 계속 누적하면 이후 기능 확장 시 불안정성이 커질 가능성이 있습니다. 다음 작업은 동작 조건 정리와 문서 보강부터 시작하는 것이 가장 효율적입니다.
