import AppKit
import SwiftUI

/// menubar 状态栏控制器：常驻图标 + 点击弹出的小窗口（NSPopover）
@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private let store: AppStore
    private let reminder: ReminderEngine
    private let onOpenItem: (FeedItem) -> Void

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var lastClick = Date(timeIntervalSince1970: 0)

    init(store: AppStore, reminder: ReminderEngine, onOpenItem: @escaping (FeedItem) -> Void) {
        self.store = store
        self.reminder = reminder
        self.onOpenItem = onOpenItem
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item

        item.button?.image = makeStatusImage(ringProgress: nil)
        item.button?.toolTip = "HealthReaderLite · 点击展开"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.contentSize = NSSize(width: 440, height: 660)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let root = PopoverRoot(store: store, reminder: reminder, onOpenItem: onOpenItem)
        let host = NSHostingController(rootView: root)
        popover.contentViewController = host
        popover.contentViewController?.view.window?.makeKey()

        Log.t("menubar 图标已安装")
    }

    // MARK: - 开关

    @objc private func togglePopover() {
        // 双击保护
        let now = Date()
        if now.timeIntervalSince(lastClick) < 0.25 { return }
        lastClick = now
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { return }
        // 点击图标时激活应用，保证菜单可用
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func toggleIfNeeded() {
        togglePopover()
    }

    /// 菜单栏当前是否可见（auto-hide 菜单栏或全屏时不可见）
    var isMenuBarVisible: Bool {
        statusItem.button?.window?.isVisible ?? false
    }

    /// 打开最新一篇资讯的阅读窗口（系统通知"看看新闻"入口）
    func openLatestNews() {
        guard let first = store.items.first else {
            showPopover()
            return
        }
        onOpenItem(first)
    }

    // MARK: - 状态栏图标（叶子 + 可选的久坐进度环）

    /// 更新图标：progress 为 0~1（距下次起身提醒的完成度）；传 nil 或关闭开关时不显示进度环
    func updateIcon(progress: CGFloat) {
        guard let button = statusItem.button else { return }
        let showRing = store.settings.reminderRingEnabled && store.settings.reminderEnabled
        button.image = makeStatusImage(ringProgress: showRing ? progress : nil)
        button.title = ""
    }

    /// 生成状态栏图标：中间叶子（比原生 SF Symbol 稍大更醒目），外圈为久坐进度环
    func makeStatusImage(ringProgress: CGFloat?) -> NSImage {
        let dimension: CGFloat = 22
        let image = NSImage(size: NSSize(width: dimension, height: dimension))
        image.lockFocus()
        defer { image.unlockFocus() }

        let center = NSPoint(x: dimension / 2, y: dimension / 2)

        // 1) 叶子（经典 template 着色：白填充 + destinationIn 保留符号透明通道）
        let leaf = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)
        if let leaf {
            let leafSize = NSSize(width: 15, height: 15)
            let mask = NSImage(size: leafSize)
            mask.lockFocus()
            NSColor.white.set()
            NSRect(origin: .zero, size: leafSize).fill(using: .sourceOver)
            leaf.draw(in: NSRect(origin: .zero, size: leafSize), from: .zero, operation: .destinationIn, fraction: 1.0)
            mask.unlockFocus()
            mask.draw(
                in: NSRect(x: center.x - leafSize.width / 2, y: center.y - leafSize.height / 2,
                           width: leafSize.width, height: leafSize.height)
            )
        }

        // 2) 久坐进度环
        if let progress = ringProgress {
            let radius = dimension / 2 - 2.2
            let lineWidth: CGFloat = 1.7
            let ringRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

            // 底色圆环
            let bg = NSBezierPath(ovalIn: ringRect)
            bg.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(0.16).setStroke()
            bg.stroke()

            // 进度弧（顶部 12 点方向起，顺时针）
            if progress > 0.004, progress < 0.999 {
                let fg = NSBezierPath()
                fg.appendArc(withCenter: center, radius: radius,
                             startAngle: 90, endAngle: 90 - 360 * progress,
                             clockwise: true)
                fg.lineWidth = lineWidth
                fg.lineCapStyle = .round
                NSColor.black.withAlphaComponent(0.92).setStroke()
                fg.stroke()
            }
        }

        image.isTemplate = true
        return image
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        // 保持状态
    }
}