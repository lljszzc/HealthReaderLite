import Foundation

// MARK: - 网络抓取

enum FeedError: LocalizedError {
    case invalidURL
    case invalidFeed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "链接格式无效"
        case .invalidFeed: return "该地址不是有效的 RSS/Atom 源"
        }
    }
}

struct FeedFetcher {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let s = URLSession(configuration: config)
        return s
    }()

    /// 规范化用户输入的 URL
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("feed://") { s = "https://" + s.dropFirst(7) }
        if !s.contains("://") { s = "https://" + s }
        return URL(string: s)
    }

    /// 拉取并解析一个订阅源
    static func fetch(at url: URL) async throws -> (meta: FeedMeta, items: [ParsedItem]) {
        var request = URLRequest(url: url)
        request.setValue("HealthReaderLite/1.0 (macOS RSS Reader)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedError.invalidFeed
        }
        guard let result = FeedParser.parse(data: data) else {
            throw FeedError.invalidFeed
        }
        return result
    }
}

// MARK: - 图片加载（配合 AsyncImage 的 URLCache 磁盘缓存）

enum ImageFetcher {
    /// 生成订阅源在列表中展示的图标地址（优先 feed 自带，其次 DuckDuckGo 图标服务）
    static func iconURL(for feed: Feed) -> String? {
        if let icon = feed.iconURL, !icon.isEmpty { return icon }
        guard let host = URL(string: feed.url)?.host, !host.isEmpty else { return nil }
        return "https://icons.duckduckgo.com/ip3/\(host).ico"
    }
}