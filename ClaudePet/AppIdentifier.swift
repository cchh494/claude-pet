import AppKit

/// NSRunningApplication 의 종류를 판별하는 정적 헬퍼 모음.
/// ContentView 의 private 메서드로 흩어져 있던 로직을 한 곳에 모았습니다.
enum AppIdentifier {

    /// Claude 앱인지 여부 (자기 자신 ClaudePet 은 제외)
    static func isClaude(_ app: NSRunningApplication) -> Bool {
        let bundleMatch = app.bundleIdentifier?.lowercased().contains("claude") == true
        let nameMatch   = app.localizedName?.lowercased().contains("claude") == true
        let isSelf      = app.processIdentifier == ProcessInfo.processInfo.processIdentifier
        return (bundleMatch || nameMatch) && !isSelf
    }

    /// 개발 도구 앱인지 여부 — VS Code · Terminal · iTerm2
    static func isDevTool(_ app: NSRunningApplication) -> Bool {
        let bundleId = app.bundleIdentifier?.lowercased() ?? ""
        let name     = app.localizedName?.lowercased() ?? ""
        let isVSCode   = bundleId.contains("com.microsoft.vscode")
                      || name == "visual studio code"
                      || name == "code"
        let isTerminal = bundleId == "com.apple.terminal" || name == "terminal"
        let isITerm    = bundleId == "com.googlecode.iterm2" || name == "iterm2"
        return isVSCode || isTerminal || isITerm
    }

    /// Claude 또는 개발 도구 앱인지 여부 (작업 앱 전체)
    static func isWorkApp(_ app: NSRunningApplication) -> Bool {
        isClaude(app) || isDevTool(app)
    }
}
