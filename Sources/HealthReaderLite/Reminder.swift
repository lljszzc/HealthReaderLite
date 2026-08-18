import AppKit
import Foundation
import UserNotifications

/// 久坐提醒引擎：按用户设置间隔定时触发
/// 呈现渠道：系统通知（全屏/多屏由系统原生处理）；未授权时降级为 popover/声音
@MainActor
final class ReminderEngine: ObservableObject {
    @Published var pending = false            // 是否有待展示的提醒横幅
    @Published var lastReminderAt: Date?
    @Published var sessionStartedAt = Date()  // 本次久坐会话开始时间

    /// 系统通知分类与动作
    static let categoryID = "SEDENTARY_REMINDER"
    static let actionViewNews = "view_news"
    static let actionSnooze = "snooze"
    static let actionDismiss = "dismiss"

    weak var store: AppStore?
    weak var status: StatusController?

    private var timer: Timer?
    private var isSnoozing = false
    /// 系统通知权限状态（启动时刷新）
    private(set) var notificationAuthorized = false

    init(store: AppStore) {
        self.store = store
    }

    // MARK: - 进度

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

    // MARK: - 编排

    /// (重新)编排下一次提醒；fire/启动/用户确认时调用
    func arm(source: String = "常规") {
        timer?.invalidate()
        timer = nil
        guard let store else { return }
        guard store.settings.reminderEnabled else {
            Log.t("久坐提醒：提醒已关闭，取消计时")
            return
        }
        let minutes = max(5, store.settings.reminderMinutes)
        let t = Timer(timeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.t("久坐提醒已编排：\(minutes) 分钟后触发（\(source)）")
    }

    /// 设置变更时调用：不打断进行中的"稍后"计时与待处理提醒
    func handleSettingsChanged() {
        guard !isSnoozing, !pending else {
            Log.t("久坐提醒：设置已更新，进行中的提醒/稍后计时保持不变")
            return
        }
        arm(source: "设置变更")
    }

    // MARK: - 触发

    private func fire() {
        // 防重复触发：60 秒内已触发过则忽略（防双计时器竞态等）
        if let last = lastReminderAt, Date().timeIntervalSince(last) < 60 {
            Log.t("久坐提醒：\(Int(Date().timeIntervalSince(last))) 秒内已触发过，忽略重复触发")
            return
        }
        guard let store, store.settings.reminderEnabled else {
            isSnoozing = false
            arm()
            return
        }
        isSnoozing = false
        pending = true
        lastReminderAt = Date()
        status?.updateIcon(progress: 1)

        if notificationAuthorized {
            sendSystemNotification()
        } else {
            // 降级：菜单栏可见 → popover 弹窗；隐藏 → 仅声音 + 进度环满格
            if status?.isMenuBarVisible == true {
                status?.showPopover()
                if store.settings.reminderSound { NSSound(named: "Glass")?.play() }
                Log.t("久坐提醒触发（通知未授权，已在 menubar 弹出）")
            } else {
                if store.settings.reminderSound { NSSound(named: "Glass")?.play() }
                Log.t("久坐提醒触发（通知未授权且菜单栏隐藏，仅提示音 + 图标满格）")
            }
        }
        arm(source: "触发后重排")
    }

    private func sendSystemNotification() {
        guard let store else { return }
        let content = UNMutableNotificationContent()
        content.title = "该起身活动一下啦 🧘"
        content.body = "已连续久坐约 \(store.settings.reminderMinutes) 分钟，站起来看看最新资讯吧"
        content.sound = store.settings.reminderSound ? .default : nil
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["minutes": store.settings.reminderMinutes]
        let request = UNNotificationRequest(
            identifier: "reminder-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil // 立即投递
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.error("系统通知发送失败：\(error.localizedDescription)") }
        }
        Log.t("久坐提醒触发！已发送系统通知（距今已坐约 \(store.settings.reminderMinutes) 分钟）")
    }

    // MARK: - 用户操作

    /// 用户看完提醒（"知道了"/"看看新闻"）
    func dismiss() {
        pending = false
        isSnoozing = false
        sessionStartedAt = Date()
        arm(source: "用户确认")
        status?.updateIcon(progress: progress)
    }

    /// 稍后提醒：先关闭，N 分钟后再触发（进度环从新会话重新计算）
    func snooze(minutes: Int) {
        pending = false
        isSnoozing = true
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

    /// 通知 action 分发（"看看新闻"/"稍后"/"知道了"）
    func handleNotification(action: String?) {
        switch action {
        case Self.actionViewNews:
            status?.openLatestNews()
            dismiss()
        case Self.actionSnooze:
            snooze(minutes: 10)
        default:
            dismiss()
        }
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

    // MARK: - 通知权限

    static func registerNotificationCategory() {
        let center = UNUserNotificationCenter.current()
        let viewNews = UNNotificationAction(identifier: actionViewNews, title: "看看新闻", options: .foreground)
        let snooze = UNNotificationAction(identifier: actionSnooze, title: "稍后 10 分钟", options: [])
        let dismiss = UNNotificationAction(identifier: actionDismiss, title: "知道了", options: [])
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [viewNews, snooze, dismiss],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// 启动后调用：请求通知权限并缓存授权状态
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            notificationAuthorized = true
            Log.t("系统通知权限：已授权（久坐提醒走系统通知）")
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                notificationAuthorized = granted
                Log.t("系统通知权限：\(granted ? "已授予" : "被拒绝，久坐提醒降级为 menubar 弹窗")")
                if granted { Self.registerNotificationCategory() }
            } catch {
                Log.error("系统通知权限请求失败：\(error.localizedDescription)")
            }
        default:
            notificationAuthorized = false
            Log.t("系统通知权限：不可用（久坐提醒降级为 menubar 弹窗）")
        }
    }
}