import Foundation

// MARK: - 지원 언어
// 추후 영어 등 다른 언어를 추가할 때 케이스를 추가하세요.
enum DialogueLanguage: String {
    case korean = "ko"
    // case english = "en"   // 추후 추가 예정
    // case japanese = "ja"  // 추후 추가 예정
}

// MARK: - 대사 트리거 종류
// 각 애니메이션 상태 또는 이벤트에 대응하는 트리거를 정의합니다.
enum DialogueTrigger {
    case idle           // 기본 대기 상태 (랜덤 인터럽트 없이 조용히 있을 때)
    case smile          // 살짝 탭 → Idle_Smile
    case boring         // Idle_Boring 진입
    case jumping        // Idle_Jumping 진입
    case touch          // Force Touch → Idle_Touch
    case workingStart   // 작업 앱 포그라운드 → Idle_Working_Prepare
    case working        // Idle_Working 루프 중 (랜덤 간격으로 출력)
    case workingEnd     // 작업 종료 → Idle_Default 복귀
    case hungry         // 배고픔 수치 20 이하 → Idle_Hungry (힘 없는 느낌)
    case fed            // 밥 받았을 때 반응
}

// MARK: - 대사 카탈로그
// 모든 대사는 이 파일 한 곳에서 관리합니다.
// 언어를 추가하려면 koreanLines 와 동일한 구조의 함수를 만들고
// lines(for:language:) 의 switch 에 케이스를 추가하면 됩니다.
struct DialogueCatalog {

    // MARK: 공개 API

    /// 트리거에 해당하는 전체 대사 목록을 반환합니다.
    static func lines(for trigger: DialogueTrigger,
                      language: DialogueLanguage = .korean) -> [String] {
        switch language {
        case .korean:
            return koreanLines(for: trigger)
        }
    }

    /// 트리거에 해당하는 대사 중 하나를 무작위로 반환합니다.
    /// 대사가 없으면 nil 을 반환합니다.
    static func randomLine(for trigger: DialogueTrigger,
                           language: DialogueLanguage = .korean) -> String? {
        return lines(for: trigger, language: language).randomElement()
    }

    // MARK: 한국어 대사 목록

    private static func koreanLines(for trigger: DialogueTrigger) -> [String] {
        switch trigger {

        case .idle:
            return [
                "심심하다..",
                "뭐 할 일 없나요?",
                "나 여기 있어요!!",
            ]

        case .smile:
            return [
                "헤헤..",
                "아헿헿~",
                "좋아요 좋아요~",
            ]

        case .boring:
            return [
                "으으..",
                "하아암..",
                "지루해..",
            ]

        case .jumping:
            return [
                "신나!",
                "점프!",
                "야호~!",
                "히히~!",
            ]

        case .touch:
            return [
                "!!?",
                "..!!",
                "!!!",
                "?!",
                "!!",
            ]

        case .workingStart:
            return [
                "오, 일 시작하는군요!",
                "저 준비됐어요!",
                "집중 모드 ON!",
            ]

        case .working:
            return [
                "집중 중..",
                "딸깍딸깍딸깍..",
                "일하는 중...",
            ]

        case .workingEnd:
            return [
                "수고하셨어요!!",
                "고생하셨어요!!",
            ]

        case .hungry:
            return [
                "배고파요...",
                "밥... 주세요...",
                "꼬르륵..",
                "힘이... 없어요..",
                "밥이 먹고 싶어요..",
                "조금만.. 주시면 안 되나요..",
                "으으.. 배고파..",
            ]

        case .fed:
            return [
                "냠냠!! 감사해요~!",
                "맛있어요!! 헤헤",
                "고마워요!! 힘 났어요!",
                "냠냠냠~",
                "역시 밥이 최고야!",
            ]
        }
    }
}
