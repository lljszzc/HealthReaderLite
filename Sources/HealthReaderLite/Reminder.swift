import AppKit
import Foundation

/// 久坐提醒引擎：按用户设置间隔定时触发，弹出 menubar 提醒并提供最新资讯
@MainActor
final class ReminderEngine: ObservableObject {
    @Published var pending = false            // 是否有待展示的提醒横幅
    @Published var lastReminderAt: Date?
    @Published var sessionStartedAt = Date()  // 本次久坐会话开始时间

    weak var store: AppStore?
    weak var status: StatusController?

    private var timer: Timer?

    init(store: AppStore) {
        self.store = store
    }

    /// 距下次起身提醒的进度（0~1，用于状态栏进度环）
    var progress: CGFloat {
        guard let store, store.settings.reminderEnabled else { return 0 }
        let interval = max(5.0, Double(store.settings.reminderMinutes) * 60)
        let elapsed = max(0, Date().timeIntervalSince(sessionStartedAt))
        return CGFloat(min(1, elapsed / interval))
    }

    /// 已编排距离下次提醒的秒数（nil 表示未编排）
    var secondsUntilNext: Int? {
        guard let timer else { return nil }
        return Int(timer.fireDate.timeIntervalSinceNow)
    }

    /// (重新)编排下一次提醒
    func arm() {
        timer?.invalidate()
        timer = nil
        guard let store else { return }
        guard store.settings.reminderEnabled else { return }
        let minutes = max(5, store.settings.reminderMinutes)
        let t = Timer(timeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.t("久坐提醒已编排：\(minutes) 分钟后触发")
    }

    private func fire() {
        guard let store, store.settings.reminderEnabled else {
            arm()
            return
        }
        pending = true
        lastReminderAt = Date()
        if store.settings.reminderSound {
            NSSound(named: "Glass")?.play()
        }
        Log.t("久坐提醒触发！距今已坐约 \(store.settings.reminderMinutes) 分钟")
        // 在 menubar 弹出提醒（含最新资讯入口），进度环同步至满
        status?.showPopover()
        status?.updateIcon(progress: 1)
        arm()
    }

    /// 用户看完提醒（“知道了”/“看看新闻”）
    func dismiss() {
        pending = false
        sessionStartedAt = Date()
        arm()
        status?.updateIcon(progress: progress)
    }

    /// 稍后提醒：先关闭，N 分钟后再触发（进度环从新会话重新计算）
    func snooze(minutes: Int) {
        pending = false
        sessionStartedAt = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        status?.updateIcon(progress: progress)
        Log.t("久坐提醒已推迟 \(minutes) 分钟")
    }

    /// 调试用：N 秒后触发提醒
    func armForTesting(seconds: Double) {
        timer?.invalidate()
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.t("调试模式：\(Int(seconds)) 秒后触发久坐提醒")
    }
}