import AppKit
import Foundation

// ---- 无界面自检模式（用于自动化验证解析/网络，不进入 GUI） ----
let args = CommandLine.arguments
if args.contains("--selftest") {
    exit(SelfTest.run())
}
if let idx = args.firstIndex(of: "--fetch-test"), args.count > idx + 1 {
    let url = args[idx + 1]
    exit(SelfTest.fetchTest(url: url))
}
if let idx = args.firstIndex(of: "--extract-test"), args.count > idx + 1 {
    let url = args[idx + 1]
    exit(SelfTest.extractTest(url: url))
}
if args.contains("--version") {
    print("HealthReaderLite \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
    exit(0)
}

// 隐藏调试旗标（自动化验证用）
enum DebugMode {
    static var reminderTest = false   // 数秒后触发久坐提醒
    static var demoNews = false       // 打开最新文章阅读窗口
}
if args.contains("--reminder-test") || UserDefaults.standard.bool(forKey: "debugReminderTest") {
    DebugMode.reminderTest = true
    Log.t("调试旗标：reminder-test（数秒后触发久坐提醒）")
}
if args.contains("--demo-news") || UserDefaults.standard.bool(forKey: "debugDemoNews") {
    DebugMode.demoNews = true
    Log.t("调试旗标：demo-news（打开最新文章阅读窗口）")
}
UserDefaults.standard.removeObject(forKey: "debugReminderTest")
UserDefaults.standard.removeObject(forKey: "debugDemoNews")

// ---- 正常 GUI 启动 ----
Log.t("启动 HealthReaderLite (GUI mode)：\(Bundle.main.executablePath ?? "?")")

// 配置共享 URL 缓存（500MB 磁盘上限，超限自动清理最久未用的），让 AsyncImage 图片只下载一次
CacheManager.configure()

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory) // LSUIElement：仅 menubar，不驻留 Dock
app.run()