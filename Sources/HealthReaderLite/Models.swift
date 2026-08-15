import Foundation

// MARK: - 数据模型

struct Folder: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
}

struct Feed: Identifiable, Codable, Hashable {
    var id: UUID
    var folderID: UUID?
    var url: String
    var title: String
    var iconURL: String?       // 来自 feed <image>/<icon>
    var lastRefresh: Date?
    var lastError: String?
    /// 是否对该订阅默认抓取全文（针对只提供摘要的站点，如 sspai）
    var fetchFullText: Bool = false

    /// 显式成员初始化器（自定义 init(from:) 后成员初始化器不再自动合成）
    init(id: UUID, folderID: UUID?, url: String, title: String, iconURL: String? = nil,
         lastRefresh: Date? = nil, lastError: String? = nil, fetchFullText: Bool = false) {
        self.id = id
        self.folderID = folderID
        self.url = url
        self.title = title
        self.iconURL = iconURL
        self.lastRefresh = lastRefresh
        self.lastError = lastError
        self.fetchFullText = fetchFullText
    }

    /// 自定义解码：新字段缺失时回退默认值，保证旧版本数据兼容
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decode(String.self, forKey: .title)
        iconURL = try c.decodeIfPresent(String.self, forKey: .iconURL)
        lastRefresh = try c.decodeIfPresent(Date.self, forKey: .lastRefresh)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        fetchFullText = (try? c.decodeIfPresent(Bool.self, forKey: .fetchFullText)) ?? false
    }
}

struct FeedItem: Identifiable, Codable, Hashable {
    var id: String            // "\(feedID)|\(guidOrLink)"，稳定去重
    var feedID: UUID
    var title: String
    var link: String
    var summary: String       // 已清洗的纯文本摘要
    var contentHTML: String?  // 正文 HTML（用于阅读窗口渲染）
    var author: String?
    var published: Date
    var thumbnailURL: String?
    var read: Bool
    var starred: Bool
}

struct AppSettings: Codable, Equatable {
    /// 自动更新间隔（分钟）
    var refreshMinutes: Int = 15
    /// 久坐提醒开关
    var reminderEnabled: Bool = true
    /// 久坐提醒间隔（分钟）
    var reminderMinutes: Int = 60
    /// 提醒时播放提示音
    var reminderSound: Bool = true
    /// 打开文章即标记已读
    var autoMarkRead: Bool = true
    /// menubar 图标显示久坐进度环
    var reminderRingEnabled: Bool = true

    static let defaultSettings = AppSettings()

    init() {}

    /// 自定义解码：字段缺失时回退默认值，兼容旧版本数据
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        refreshMinutes = (try? c.decodeIfPresent(Int.self, forKey: .refreshMinutes)) ?? 15
        reminderEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .reminderEnabled)) ?? true
        reminderMinutes = (try? c.decodeIfPresent(Int.self, forKey: .reminderMinutes)) ?? 60
        reminderSound = (try? c.decodeIfPresent(Bool.self, forKey: .reminderSound)) ?? true
        autoMarkRead = (try? c.decodeIfPresent(Bool.self, forKey: .autoMarkRead)) ?? true
        reminderRingEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .reminderRingEnabled)) ?? true
    }
}

/// 侧栏/列表的新闻范围
enum NewsScope: Hashable {
    case all
    case unread
    case starred
    case feed(UUID)
    case folder(UUID)
}

// MARK: - 解析结果（跨模块共享）

struct FeedMeta {
    var title: String
    var iconURL: String?
}

struct ParsedItem {
    var guid: String
    var title: String
    var link: String
    var summary: String
    var contentHTML: String?
    var author: String?
    var published: Date?
    var thumbnailURL: String?
}

// MARK: - 工具扩展

/// 业务错误（携带中文提示）
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}

extension Array {
    func chunked(by size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var i = 0
        while i < count {
            result.append(Array(self[i..<Swift.min(i + size, count)]))
            i += size
        }
        return result
    }
}

extension URL {
    /// 从 URL 推断 favicon 地址
    var faviconURL: URL? {
        guard let host = host, !host.isEmpty else { return nil }
        let scheme = self.scheme ?? "https"
        return URL(string: "\(scheme)://\(host)/favicon.ico")
    }
}