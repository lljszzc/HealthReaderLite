import AppKit
import SwiftUI

/// menubar 小窗口根视图：久坐提醒横幅 + 头部 + 侧栏 + 新闻列表 + 底部状态
struct PopoverRoot: View {
    @ObservedObject var store: AppStore
    @ObservedObject var reminder: ReminderEngine
    let onOpenItem: (FeedItem) -> Void

    @State private var scope: NewsScope = .all
    @State private var showAddFeed = false
    @State private var showSettings = false
    @State private var expandedFolders: Set<UUID> = []

    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var confirmTarget: ConfirmTarget?

    enum RenameTarget: Identifiable {
        case feed(UUID)
        case folder(UUID)
        var id: String {
            switch self { case .feed(let u): return "feed-\(u)"; case .folder(let u): return "folder-\(u)" }
        }
    }

    enum ConfirmTarget: Identifiable {
        case feed(UUID)
        case folder(UUID)
        var id: String {
            switch self { case .feed(let u): return "feed-\(u)"; case .folder(let u): return "folder-\(u)" }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if reminder.pending {
                ReminderBanner(reminder: reminder, store: store) {
                    scope = .all
                    reminder.dismiss()
                }
            }

            header

            Divider()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 176)
                Divider()
                newsList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            footer
        }
        .frame(width: 440, height: 660)
        .sheet(isPresented: $showAddFeed) {
            AddFeedSheet(store: store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(store: store)
        }
        .alert("重命名", isPresented: renameAlertBinding) {
            TextField("名称", text: $renameText)
            Button("确定") { applyRename() }.keyboardShortcut(.defaultAction)
            Button("取消", role: .cancel) {}
        } message: {
            Text("输入新的名称")
        }
        .alert("确认删除", isPresented: confirmBinding) {
            Button("删除", role: .destructive) { applyDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
            Text("HealthReaderLite")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if store.refreshing {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("刷新全部订阅")
            .disabled(store.refreshing)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("设置")

            Button {
                showAddFeed = true
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .help("添加订阅")

            Divider()
                .frame(height: 14)

            // 久坐提醒快捷开关（即时生效，设置页同样可调）
            HStack(spacing: 5) {
                Image(systemName: store.settings.reminderEnabled
                      ? "figure.stand"
                      : "figure.stand.line.dotted.figure.stand")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.settings.reminderEnabled ? Color.green : Color.secondary)
                Toggle("", isOn: Binding(
                    get: { store.settings.reminderEnabled },
                    set: { store.setReminderEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .help(store.settings.reminderEnabled ? "久坐提醒已开启，点击关闭" : "久坐提醒已关闭，点击开启")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - 侧栏

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sidebarSectionLabel("智能列表")
                smartRow("全部文章", icon: "tray.full", scope: .all, count: store.items.count)
                smartRow("未读", icon: "envelope.badge", scope: .unread, count: store.unreadCount)
                smartRow("已收藏", icon: "star", scope: .starred, count: nil)

                sidebarSectionLabel("订阅")
                ForEach(store.folders) { folder in
                    folderBlock(folder)
                }
                let ungrouped = store.feeds.filter { $0.folderID == nil }
                if !ungrouped.isEmpty {
                    sidebarSectionLabel("未分组")
                    ForEach(ungrouped) { feed in
                        feedRow(feed)
                    }
                }
                if store.feeds.isEmpty {
                    Text("还没有订阅\n点击右上角 + 添加")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }
            }
            .padding(8)
        }
        .scrollIndicators(.hidden)
    }

    private func sidebarSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    private func smartRow(_ title: String, icon: String, scope target: NewsScope, count: Int?) -> some View {
        Button {
            scope = target
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive(target) ? Color.accentColor.opacity(0.16) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func folderBlock(_ folder: Folder) -> some View {
        DisclosureGroup(isExpanded: expandedBinding(folder.id)) {
            ForEach(store.feeds.filter { $0.folderID == folder.id }) { feed in
                feedRow(feed)
                    .padding(.leading, 14)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(folder.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                let unread = store.unreadCount(forFolder: folder.id)
                if unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive(.folder(folder.id)) ? Color.accentColor.opacity(0.16) : .clear)
            )
            .onTapGesture {
                scope = .folder(folder.id)
            }
            .contextMenu {
                Button("查看该文件夹") { scope = .folder(folder.id) }
                Button("重命名…") {
                    renameTarget = .folder(folder.id)
                    renameText = folder.name
                }
                Button("新建订阅到此文件夹") {
                    showAddFeed = true
                }
                Divider()
                Button("删除文件夹", role: .destructive) {
                    confirmTarget = .folder(folder.id)
                }
            }
        }
    }

    private func feedRow(_ feed: Feed) -> some View {
        Button {
            scope = .feed(feed.id)
        } label: {
            HStack(spacing: 6) {
                FaviconView(feed: feed, size: 16)
                Text(feed.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 4)
                let unread = store.unreadCount(forFeed: feed.id)
                if unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive(.feed(feed.id)) ? Color.accentColor.opacity(0.16) : .clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("立即更新") { Task { await store.refresh(feed) } }
            Button("查看订阅") { scope = .feed(feed.id) }
            Toggle(isOn: Binding(
                get: { feed.fetchFullText },
                set: { newValue in store.setFeedFetchFullText(feed.id, newValue) }
            )) {
                Label("自动抓取全文", systemImage: "text.alignleft")
            }
            Menu("移动到文件夹") {
                Button("未分组") { store.moveFeed(feed.id, toFolder: nil) }
                ForEach(store.folders) { folder in
                    Button(folder.name) { store.moveFeed(feed.id, toFolder: folder.id) }
                }
            }
            Button("重命名…") {
                renameTarget = .feed(feed.id)
                renameText = feed.title
            }
            Divider()
            Button("删除订阅", role: .destructive) {
                confirmTarget = .feed(feed.id)
            }
        }
    }

    private func expandedBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedFolders.contains(id) },
            set: { expanded in
                if expanded { expandedFolders.insert(id) } else { expandedFolders.remove(id) }
            }
        )
    }

    private func isActive(_ target: NewsScope) -> Bool {
        scope == target
    }

    // MARK: - 新闻列表

    private var newsList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(scopeTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(filtered.count) 篇")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                if !filtered.isEmpty && filtered.contains(where: { !$0.read }) {
                    Button("全部标为已读") {
                        store.markAllRead(in: scope)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "newspaper")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("暂无内容")
                        .font(.system(size: 12, weight: .medium))
                    Text("点击右上角 + 添加订阅\n或等待自动更新")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { item in
                    NewsRow(item: item, store: store) {
                        onOpenItem(item)
                    }
                    .contextMenu { itemMenu(item) }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowBackground(Color.clear)
                }
                .id(scope) // 切换范围时回到顶部
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: FeedItem) -> some View {
        Button(item.starred ? "取消收藏" : "收藏") { store.toggleStar(item.id) }
        Button(item.read ? "标为未读" : "标为已读") { store.markRead(item.id, !item.read) }
        if !item.link.isEmpty {
            Button("在浏览器打开") {
                if let url = URL(string: item.link) { NSWorkspace.shared.open(url) }
            }
        }
    }

    private var filtered: [FeedItem] {
        store.items(in: scope)
    }

    private var scopeTitle: String {
        switch scope {
        case .all: return "全部文章"
        case .unread: return "未读"
        case .starred: return "已收藏"
        case .feed(let id): return store.feed(id)?.title ?? "订阅"
        case .folder(let id): return store.folders.first { $0.id == id }?.name ?? "文件夹"
        }
    }

    // MARK: - 底部状态栏

    private var footer: some View {
        HStack(spacing: 6) {
            if let last = store.lastRefresh {
                Text("更新于 \(timeText(last))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text("尚未更新")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            if let failed = store.feeds.first(where: { $0.lastError != nil }) {
                Text("· \(failed.title) 更新失败")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer()
            Button("退出") { NSApp.terminate(nil) }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - 弹窗动作

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var confirmBinding: Binding<Bool> {
        Binding(
            get: { confirmTarget != nil },
            set: { if !$0 { confirmTarget = nil } }
        )
    }

    private var confirmMessage: String {
        switch confirmTarget {
        case .feed: return "删除后该订阅及其文章将被移除。"
        case .folder: return "文件夹将被删除，其中的订阅会移到“未分组”。"
        case nil: return ""
        }
    }

    private func applyRename() {
        switch renameTarget {
        case .feed(let id): store.renameFeed(id, to: renameText)
        case .folder(let id): store.renameFolder(id, to: renameText)
        case nil: break
        }
        renameTarget = nil
    }

    private func applyDelete() {
        switch confirmTarget {
        case .feed(let id):
            store.removeFeed(id)
            if scope == .feed(id) { scope = .all }
        case .folder(let id):
            store.removeFolder(id)
            if scope == .folder(id) { scope = .all }
        case nil: break
        }
        confirmTarget = nil
    }
}

// MARK: - 久坐提醒横幅

struct ReminderBanner: View {
    @ObservedObject var reminder: ReminderEngine
    @ObservedObject var store: AppStore
    var onViewNews: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.stand")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("该起身放松一下啦")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("已连续久坐约 \(store.settings.reminderMinutes) 分钟\n站起来，看看最新资讯吧")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
            }
            Spacer()
            Button {
                onViewNews()
            } label: {
                Text("看看新闻")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.white.opacity(0.28))
            Button("稍后") {
                reminder.snooze(minutes: 10)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.85))
            .help("10 分钟后再提醒")
            Button {
                reminder.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("知道了")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.52, blue: 0.95),
                            Color(red: 0.20, green: 0.70, blue: 0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}

// MARK: - 订阅图标（favicon）

struct FaviconView: View {
    let feed: Feed
    var size: CGFloat = 16

    var body: some View {
        if let icon = ImageFetcher.iconURL(for: feed), let url = URL(string: icon) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.16))
            Text(String(feed.title.prefix(1)).uppercased())
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
    }
}