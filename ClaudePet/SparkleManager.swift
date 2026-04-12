import Sparkle

/// Sparkle 자동 업데이트를 관리하는 싱글톤.
/// AppDelegate 초기화 시 setup() 을 한 번 호출하세요.
final class SparkleManager: NSObject {
    static let shared = SparkleManager()

    private var updaterController: SPUStandardUpdaterController?

    private override init() {}

    /// AppDelegate.applicationDidFinishLaunching 에서 호출합니다.
    func setup() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// 업데이트 확인 버튼에서 호출합니다.
    /// Sparkle 이 자체 UI 다이얼로그를 표시합니다.
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate
extension SparkleManager: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        return "https://cchh494.github.io/claude-pet/appcast.xml"
    }
}
