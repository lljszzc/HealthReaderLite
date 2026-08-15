import Foundation
import Combine

// MARK: - 主数据仓库（内存态 + JSON 持久化）

@MainActor
final class AppStore: ObservableObject {
    @Published var folders: [Folder] = []
    @Published var feeds: [Feed] = []
    @Published var items: [FeedItem] = []           // 全部文章，按时间倒序
    @Published var settings: AppSettings = .defaultSettings
    @Published var refreshing = false
    @Published var lastRefresh: Date?

    // MARK: 持久化

    static let storeDir: URL = Log.appSupportDir
    private static let storeURL = storeDir.appendingPathComponent("store.json")

    private var saveTask: Task<Void, Never>?
    private var loaded = false

    func load() {
        guard !loaded else { return }
        loaded = true
        do {
            try FileManager.default.createDirectory(at: Self.storeDir, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: Self.storeURL.path) else {
                seedDefaultFeedsIfNeeded()
                saveNow()
                return
            }
            let data = try Data(contentsOf: Self.storeURL)
            let box = try JSONDecoder().decode(StoreBox.self, from: data)
            folders = box.folders
            feeds = box.feeds
            items = box.items.sorted { $0.published > $1.published }
            settings = box.settings
            if feeds.isEmpty { seedDefaultFeedsIfNeeded(); saveNow() }
            Log.t("数据加载完成：\(feeds.count) 个订阅，\(items.count) 篇文章")
        } catch {
            Log.error("加载数据失败：\(error)")
            // 备份损坏/不兼容的数据文件，避免被后续保存覆盖
            if FileManager.default.fileExists(atPath: Self.storeURL.path) {
                let backupURL = Self.storeURL.deletingPathExtension().appendingPathExtension("json.bak")
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: Self.storeURL, to: backupURL)
                Log.t("已将原数据备份到 store.json.bak")
            }
            seedDefaultFeedsIfNeeded()
            saveNow()
        }
    }

    func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000) // 600ms 防抖
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            try FileManager.default.createDirectory(at: Self.storeDir, withIntermediateDirectories: true)
            let box = StoreBox(folders: folders, feeds: feeds, items: items, settings: settings)
            let data = try JSONEncoder().encode(box)
            // 原子写入
            let tmp = Self.storeDir.appendingPathComponent("store.json.tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(Self.storeURL, withItemAt: tmp)
        } catch {
            Log.error("保存数据失败：\(error)")
        }
    }

    private struct StoreBox: Codable {
        var folders: [Folder]
        var feeds: [Feed]
        var items: [FeedItem]
        var settings: AppSettings
    }

    // MARK: 首启预置订阅

    private func seedDefaultFeedsIfNeeded() {
        guard feeds.isEmpty else { return }
        let folder = Folder(id: UUID(), name: "默认订阅")
        folders.append(folder)
        let defaults: [(String, String)] = [
            ("Hacker News", "https://hnrss.org/frontpage"),
            ("The Verge", "https://www.theverge.com/rss/index.xml"),
            ("少数派 sspai", "https://sspai.com/feed")
        ]
        for (title, url) in defaults {
            feeds.append(Feed(id: UUID(), folderID: folder.id, url: url, title: title))
        }
        Log.t("已预置默认订阅（\(defaults.count) 个）")
    }

    // MARK: - 派生数据

    var unreadCount: Int { items.lazy.filter { !$0.read }.count }

    func unreadCount(forFeed id: UUID) -> Int {
        items.lazy.filter { $0.feedID == id && !$0.read }.count
    }

    func unreadCount(forFolder id: UUID) -> Int {
        let feedIDs = Set(feeds.filter { $0.folderID == id }.map(\.id))
        return items.lazy.filter { feedIDs.contains($0.feedID) && !$0.read }.count
    }

    func feed(_ id: UUID) -> Feed? { feeds.first { $0.id == id } }

    func items(in scope: NewsScope) -> [FeedItem] {
        switch scope {
        case .all: return items
        case .unread: return items.filter { !$0.read }
        case .starred: return items.filter { $0.starred }
        case .feed(let id): return items.filter { $0.feedID == id }
        case .folder(let fid):
            let ids = Set(feeds.filter { $0.folderID == fid }.map(\.id))
            return items.filter { ids.contains($0.feedID) }
        }
    }

    // MARK: - 订阅 CRUD

    @discardableResult
    func addFeed(urlString: String, folderID: UUID?, title: String? = nil, fetchFullText: Bool = false) async -> Result<Feed, AppError> {
        guard let url = FeedFetcher.normalize(urlString) else { return .failure(AppError.message("链接无效，请检查后重试")) }
        // 防重复
        if feeds.contains(where: { $0.url == url.absoluteString }) {
            return .failure(AppError.message("该订阅已存在"))
        }
        var feed = Feed(id: UUID(), folderID: folderID, url: url.absoluteString,
                        title: title?.isEmpty == false ? title! : "",
                        fetchFullText: fetchFullText)
        feeds.append(feed)
        save()
        do {
            let (meta, parsed) = try await FeedFetcher.fetch(at: url)
            feed.title = title?.isEmpty == false ? title! : (meta.title.isEmpty ? url.host ?? "未命名订阅" : meta.title)
            feed.iconURL = meta.iconURL
            feed.lastRefresh = Date()
            feeds = feeds.map { $0.id == feed.id ? feed : $0 }
            if !parsed.isEmpty { merge(parsed, into: feed) }
            await enrichFullTextIfNeeded(for: feed)
            save()
            Log.t("添加订阅成功：\(feed.title)（\(parsed.count) 篇）")
            return .success(feed)
        } catch {
            feed.title = title?.isEmpty == false ? title! : (url.host ?? "未命名订阅")
            feed.lastError = error.localizedDescription
            feeds = feeds.map { $0.id == feed.id ? feed : $0 }
            save()
            Log.error("添加订阅失败：\(url.absoluteString) - \(error.localizedDescription)")
            return .failure(AppError.message("已保留订阅（\(error.localizedDescription)），稍后可手动更新"))
        }
    }

    func removeFeed(_ id: UUID) {
        feeds.removeAll { $0.id == id }
        items.removeAll { $0.feedID == id }
        save()
    }

    func renameFeed(_ id: UUID, to name: String) {
        guard let idx = feeds.firstIndex(where: { $0.id == id }) else { return }
        feeds[idx].title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? feeds[idx].title : name
        save()
    }

    func moveFeed(_ id: UUID, toFolder folderID: UUID?) {
        guard let idx = feeds.firstIndex(where: { $0.id == id }) else { return }
        feeds[idx].folderID = folderID
        save()
    }

    func addFolder(name: String) -> Folder {
        let folder = Folder(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新文件夹" : name)
        folders.append(folder)
        save()
        return folder
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? folders[idx].name : name
        save()
    }

    func removeFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        feeds = feeds.map {
            $0.folderID == id
                ? Feed(id: $0.id, folderID: nil, url: $0.url, title: $0.title,
                       iconURL: $0.iconURL, lastRefresh: $0.lastRefresh, lastError: $0.lastError,
                       fetchFullText: $0.fetchFullText)
                : $0
        }
        save()
    }

    /// 开启/关闭某订阅的全文抓取
    func setFeedFetchFullText(_ id: UUID, _ value: Bool) {
        guard let idx = feeds.firstIndex(where: { $0.id == id }) else { return }
        feeds[idx].fetchFullText = value
        save()
        Log.t("\(feeds[idx].title) 全文抓取：\(value ? "开启" : "关闭")")
    }

    // MARK: - 文章操作

    func markRead(_ id: String, _ read: Bool = true) {
        guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].read != read else { return }
        items[idx].read = read
        save()
    }

    func markAllRead(in scope: NewsScope) {
        let ids = Set(items(in: scope).map(\.id))
        var changed = false
        for i in items.indices where ids.contains(items[i].id) && !items[i].read {
            items[i].read = true
            changed = true
        }
        if changed { save() }
    }

    func toggleStar(_ id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].starred.toggle()
        save()
    }

    // MARK: - 抓取更新

    /// 刷新全部订阅（分 4 组并发，节省带宽与 CPU）
    func refreshAll() async {
        guard !refreshing, !feeds.isEmpty else { return }
        refreshing = true
        defer { refreshing = false }
        let batch = feeds
        var refreshed = 0
        for chunk in batch.chunked(by: 4) {
            await withTaskGroup(of: Bool.self) { group in
                for feed in chunk {
                    group.addTask { [weak self] in
                        guard let self else { return false }
                        return await self.refresh(feed)
                    }
                }
                for await ok in group where ok { refreshed += 1 }
            }
        }
        lastRefresh = Date()
        save()
        publish()
        // 网络刷新后顺手检查图片缓存水位（超 500MB 自动清理最久未用的）
        CacheManager.pruneIfNeeded()
        Log.t("刷新完成：成功 \(refreshed)/\(batch.count) 个订阅")
    }

    /// 刷新单个订阅，返回是否成功
    @discardableResult
    func refresh(_ feed: Feed) async -> Bool {
        guard let url = URL(string: feed.url) else { return false }
        do {
            let (meta, parsed) = try await FeedFetcher.fetch(at: url)
            var updated = feed
            if updated.title.isEmpty { updated.title = meta.title }
            if updated.iconURL.isNilOrEmpty { updated.iconURL = meta.iconURL }
            updated.lastRefresh = Date()
            updated.lastError = nil
            feeds = feeds.map { $0.id == updated.id ? updated : $0 }
            merge(parsed, into: updated)
            await enrichFullTextIfNeeded(for: updated)
            Log.t("刷新 OK：\(updated.title)（\(parsed.count) 条）")
            return true
        } catch {
            var updated = feed
            updated.lastError = error.localizedDescription
            feeds = feeds.map { $0.id == updated.id ? updated : $0 }
            Log.error("刷新失败：\(feed.url) - \(error.localizedDescription)")
            return false
        }
    }

    /// 把抓取到的文章合并进 items（按 guid/link 去重，单源上限 80 条）
    private func merge(_ parsed: [ParsedItem], into feed: Feed) {
        let existed = Set(items.filter { $0.feedID == feed.id }.map(\.id))
        var newItems: [FeedItem] = []
        for p in parsed {
            let rawID = p.guid.isEmpty ? p.link : p.guid
            guard !rawID.isEmpty else { continue }
            let id = "\(feed.id.uuidString)|\(rawID)"
            guard !existed.contains(id) else { continue }
            // 缩略图 URL 可能是 HTML 实体编码（如 The Verge 的 &#038;）
            let thumbRaw = p.thumbnailURL.map { HTML.decodeEntities($0) } ?? p.thumbnailURL
            newItems.append(FeedItem(
                id: id,
                feedID: feed.id,
                title: p.title,
                link: p.link,
                summary: p.summary,
                contentHTML: p.contentHTML,
                author: p.author,
                published: p.published ?? Date(),
                thumbnailURL: HTML.resolve(thumbRaw, base: feed.url),
                read: false,
                starred: false
            ))
        }
        guard !newItems.isEmpty else { return }
        items.append(contentsOf: newItems)
        items.sort { $0.published > $1.published }
        // 单源上限：保留最新 80 条
        let feedItems = items.filter { $0.feedID == feed.id }.sorted { $0.published > $1.published }
        if feedItems.count > 80 {
            let keep = Set(feedItems.prefix(80).map(\.id))
            items.removeAll { $0.feedID == feed.id && !keep.contains($0.id) }
        }
        // 全局上限 600 条（性能保护）
        if items.count > 600 {
            items = Array(items.prefix(600))
        }
    }

    /// 将未发布的内部状态同步发布（占位，未来可扩展）
    private func publish() {}

    /// 全文增强：对开启了"抓取全文"的订阅，补齐只有摘要的文章（跳过已有正常正文的）
    private func enrichFullTextIfNeeded(for feed: Feed) async {
        guard feed.fetchFullText else { return }
        let candidates = items.filter {
            $0.feedID == feed.id
                && !$0.link.isEmpty
                && (($0.contentHTML ?? "").count < 80)
        }
        guard !candidates.isEmpty else { return }
        Log.t("补抓全文：\(feed.title)（\(candidates.count) 篇）")
        var updated = 0
        var coversBackfilled = 0
        for chunk in candidates.chunked(by: 3) {
            await withTaskGroup(of: (String, ExtractedArticle?).self) { group in
                for candidate in chunk {
                    guard let url = URL(string: candidate.link) else { continue }
                    group.addTask {
                        let article = await FeedFetcher.fetchArticleBody(at: url)
                        return (candidate.id, article)
                    }
                }
                for await (itemID, article) in group {
                    guard let article, !article.bodyHTML.isEmpty,
                          let idx = items.firstIndex(where: { $0.id == itemID }) else { continue }
                    items[idx].contentHTML = article.bodyHTML
                    // 无缩略图的文章回填页面封面图（如 sspai：服务端 HTML 无正文图但有 og:image）
                    if items[idx].thumbnailURL == nil, let cover = article.coverURL, !cover.isEmpty {
                        items[idx].thumbnailURL = cover
                        coversBackfilled += 1
                    }
                    updated += 1
                }
            }
        }
        if updated > 0 {
            save()
            Log.t("全文补抓完成：\(feed.title) 新增 \(updated) 篇正文\(coversBackfilled > 0 ? "（回填封面图 \(coversBackfilled) 张）" : "")")
        }
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        guard let self else { return true }
        return self.isEmpty
    }
}