import AppKit
import Combine
import SwiftUI

// MARK: - 应用主代理

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let version = "1.0.0"

    let store = AppStore()
    private var status: StatusController!
    private var reminder: ReminderEngine!

    /// 打开的阅读窗口（key = 文章 id）
    private var readingWindows: [String: ReadingWindowController] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var progressTimer: Timer?
    private var napActivity: NSObjectProtocol?
    private var launched = false

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.t("applicationDidFinishLaunching")
        launched = true

        // 防止 App Nap 暂停定时器（自动更新/久坐提醒需要准时触发）
        napActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "RSS 自动更新与久坐提醒"
        )

        store.load()

        reminder = ReminderEngine(store: store)
        status = StatusController(store: store, reminder: reminder) { [weak self] item in
            self?.openReadingWindow(item)
        }
        status.install()
        reminder.status = status

        installMainMenu()
        observeChanges()
        armRefreshTimer()
        reminder.arm()

        // 启动后延迟 2 秒自动刷新一次
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.launched else { return }
            await self.store.refreshAll()
        }

        // 调试模式（自动化验证）
        if DebugMode.reminderTest {
            reminder.armForTesting(seconds: 4)
        }
        if DebugMode.demoNews {
            Task { [weak self] in
                // 等待首次刷新产出文章（最多 20 秒）
                var waited = 0
                while true {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    waited += 1
                    guard let self else { return }
                    if !self.store.items.isEmpty || waited > 20 { break }
                }
                guard let self else { return }
                guard let first = self.store.items.first else { return }
                self.openReadingWindow(first)
                // 调试：8 秒后自动关闭，验证 Dock 图标随之消失
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if let controller = self.readingWindows[first.id] {
                    Log.t("调试模式：自动关闭阅读窗口")
                    controller.window?.performClose(nil)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
        Log.t("应用退出")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // 常驻 menubar
    }

    // MARK: - 主菜单（保证 Cmd+Q 等可用）

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于 HealthReaderLite",
                                   action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "显示消息窗口",
                                   action: #selector(showPopoverCommand), keyEquivalent: "1"))
        appMenu.addItem(NSMenuItem(title: "刷新全部订阅",
                                   action: #selector(refreshAllCommand), keyEquivalent: "r"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 HealthReaderLite",
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func refreshAllCommand() {
        Task { await store.refreshAll() }
    }

    @objc private func showPopoverCommand() {
        status.showPopover()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "HealthReaderLite \(Self.version)"
        alert.informativeText = "极轻量 menubar RSS 阅读器\n订阅 · 自动更新 · 文件夹管理 · 久坐提醒"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    // MARK: - 状态订阅（定时器重排 / 状态栏图标）

    private func observeChanges() {
        // 初始化状态栏图标（叶子 + 进度环）
        status.updateIcon(progress: reminder.progress)

        // 久坐进度环：每分钟刷新一次（间隔设置以分钟计）
        let progressTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.status?.updateIcon(progress: self.reminder.progress)
            }
        }
        RunLoop.main.add(progressTimer, forMode: .common)
        self.progressTimer = progressTimer

        // 设置变化 → 重排自动更新与久坐提醒，并即时刷新图标（环开关/间隔变更）
        store.$settings
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.armRefreshTimer()
                self.reminder.arm()
                self.status?.updateIcon(progress: self.reminder.progress)
            }
            .store(in: &cancellables)
    }

    private func armRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let minutes = max(5, store.settings.refreshMinutes)
        let t = Timer(timeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.store.refreshAll() }
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
        Log.t("自动更新已编排：每 \(minutes) 分钟")
    }

    // MARK: - 阅读窗口（Dock 图标动态出现/消失）

    func openReadingWindow(_ item: FeedItem) {
        // 同一文章只保留一个窗口
        if let existing = readingWindows[item.id] {
            existing.focus()
            return
        }
        guard let feed = store.feed(item.feedID) else { return }
        let controller = ReadingWindowController(item: item, feed: feed, store: store) { [weak self] c in
            self?.closeReadingWindow(c)
        }
        readingWindows[item.id] = controller
        controller.show()
    }

    func closeReadingWindow(_ controller: ReadingWindowController) {
        // 先移除引用
        for (key, value) in readingWindows where value === controller {
            readingWindows.removeValue(forKey: key)
        }
        // 没有其他窗口时，从 Dock 消失（回到纯 menubar 状态）
        if readingWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
            Log.t("阅读窗口已关闭，回到纯 menubar 模式（activationPolicy=\(NSApp.activationPolicy().rawValue)）")
        }
    }
}