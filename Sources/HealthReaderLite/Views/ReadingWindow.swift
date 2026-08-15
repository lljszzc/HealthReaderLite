import AppKit
import SwiftUI

// MARK: - 阅读窗口控制器（Dock 图标随窗口出现/消失）

final class ReadingWindowController: NSWindowController {
    private let store: AppStore
    private let itemID: String
    private let onClosed: (ReadingWindowController) -> Void

    init(item: FeedItem, feed: Feed, store: AppStore,
         onClosed: @escaping (ReadingWindowController) -> Void) {
        self.store = store
        self.itemID = item.id
        self.onClosed = onClosed

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(960, screen.width * 0.72)
        let height = min(720, screen.height * 0.78)
        let rect = NSRect(
            x: screen.midX - width / 2,
            y: screen.midY - height / 2 + 20,
            width: width,
            height: height
        )

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = feed.title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 660, height: 500)
        window.backgroundColor = .windowBackgroundColor
        window.tabbingMode = .disallowed

        super.init(window: window)
        window.delegate = self

        let root = ReadingView(
            store: store,
            itemID: item.id,
            onClose: { [weak self] in
                self?.window?.performClose(nil)
            }
        )
        window.contentViewController = NSHostingController(rootView: root)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window else { return }
        if store.settings.autoMarkRead {
            store.markRead(itemID, true)
        }
        // 阅读窗口像常规 app 一样弹出：Dock 出现应用图标
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Log.t("打开阅读窗口：\(window.title)，activationPolicy=\(NSApp.activationPolicy().rawValue)")
    }

    func focus() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

extension ReadingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClosed(self)
    }
}

// MARK: - Reeder 风格阅读视图

struct ReadingView: View {
    @ObservedObject var store: AppStore
    let itemID: String
    var onClose: () -> Void

    @State private var articleBlocks: [HTMLBlock] = []
    @State private var bodyReady = false

    private var item: FeedItem? {
        store.items.first { $0.id == itemID }
    }

    private var isStarred: Bool {
        item?.starred ?? false
    }

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("文章已不存在")
                    Button("关闭", action: onClose)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .environment(\.openURL, openAction)
        .onExitCommand {
            onClose()
        }
    }

    private var openAction: OpenURLAction {
        OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        }
    }

    // MARK: - 内容

    private func content(_ item: FeedItem) -> some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sourceRow(item)

                    Text(item.title)
                        .font(.system(size: 30, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    if let thumb = item.thumbnailURL, let url = URL(string: thumb) {
                        heroImage(url)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    bodyBlock(item)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.top, 6)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.visible)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar(item)
        }
        .task(id: itemID) {
            articleBlocks = []
            bodyReady = false
            guard let item = store.items.first(where: { $0.id == itemID }) else { return }
            let html = item.contentHTML
            let summary = item.summary
            let link = item.link
            // 解析/分词在后台进行，避免阻塞滚动
            let blocks = await Task.detached(priority: .userInitiated) {
                if let html, !html.isEmpty {
                    return HTML.blocks(from: html, baseURL: link)
                } else {
                    return HTML.paragraphs(from: summary).map { HTMLBlock.paragraph($0) }
                }
            }.value
            articleBlocks = blocks
            bodyReady = true
        }
    }

    private func sourceRow(_ item: FeedItem) -> some View {
        HStack(spacing: 6) {
            if let feed = store.feed(item.feedID) {
                FaviconView(feed: feed, size: 17)
            }
            Text(store.feed(item.feedID)?.title ?? "订阅")
                .font(.system(size: 12, weight: .semibold))
            if let author = item.author, !author.isEmpty {
                Text("· \(author)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Dates.relative(item.published))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func heroImage(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.secondary.opacity(0.06)
                    .frame(height: 160)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 26))
                    }
            }
        }
        .frame(maxHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func bodyBlock(_ item: FeedItem) -> some View {
        if !bodyReady {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else if articleBlocks.isEmpty {
            Text(item.summary.isEmpty ? "（该订阅源未提供正文内容，可在浏览器中打开查看）" : item.summary)
                .font(.system(size: 16.5))
                .lineSpacing(8)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(articleBlocks.enumerated()), id: \.offset) { index, block in
                    blockView(block, coverURL: item.thumbnailURL)
                }
                // 文末呼吸空间
                Color.clear.frame(height: 10)
            }
        }
    }

    /// 统一排版规范：正文 16.5pt / 行距 8 / 段距 13；标题与引用层级分明
    @ViewBuilder
    private func blockView(_ block: HTMLBlock, coverURL: String?) -> some View {
        switch block {
        case .paragraph(let md):
            markdownText(md)
                .font(.system(size: 16.5))
                .lineSpacing(8)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 13)

        case .heading(let level, let md):
            markdownText(md)
                .font(.system(size: level <= 1 ? 20 : level == 2 ? 18.5 : 17, weight: .semibold))
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(.top, level <= 1 ? 12 : 8)
                .padding(.bottom, 8)

        case .image(let urlString):
            let normalized = HTML.decodeEntities(urlString)
            let coverNormalized = coverURL.map { HTML.decodeEntities($0) }
            // 与封面图重复的正文首图不再重复展示
            if normalized == coverNormalized {
                EmptyView()
            } else if let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        Color.secondary.opacity(0.05)
                            .frame(height: 120)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                                    .font(.system(size: 24))
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.10), lineWidth: 0.5)
                )
                .padding(.vertical, 6)
            }

        case .quote(let md):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 3)
                markdownText(md)
                    .font(.system(size: 15))
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
            .padding(.bottom, 10)

        case .listItem(let md):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                markdownText(md)
                    .font(.system(size: 16))
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .padding(.bottom, 5)
        }
    }

    private func markdownText(_ md: String) -> Text {
        if let attr = try? AttributedString(markdown: md) {
            return Text(attr)
        }
        return Text(md)
    }

    private func topBar(_ item: FeedItem) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text("HealthReaderLite")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.toggleStar(itemID)
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isStarred ? "取消收藏" : "收藏")

            Button {
                if let url = URL(string: item.link) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "safari")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("在浏览器中打开")

            Divider()
                .frame(height: 14)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("关闭阅读窗口（应用从 Dock 消失）")
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }
}