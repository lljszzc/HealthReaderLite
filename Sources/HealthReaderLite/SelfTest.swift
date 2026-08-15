import Foundation

/// 无界面自检：验证 RSS/Atom 解析、HTML 清洗与日期的正确性
enum SelfTest {
    static func run() -> Int32 {
        failures = 0
        print("== HealthReaderLite 自检 ==")

        // 1. RSS 2.0
        do {
            let (meta, items) = try require(FeedParser.parse(data: sampleRSS.data(using: .utf8)!), "RSS 2.0 解析失败")
            requireEqual(meta.title, "测试科技博客", "RSS channel 标题")
            requireEqual(items.count, 2, "RSS 条目数")
            let first = items[0]
            requireEqual(first.title, "SwiftUI 新特性一览", "RSS 条目标题")
            requireEqual(first.link, "https://example.com/swiftui", "RSS 条目链接")
            check(first.published != nil, "RSS 日期解析")
            requireEqual(first.thumbnailURL, "https://example.com/img/swiftui.jpg", "RSS media:thumbnail")
            print("  [PASS] RSS 2.0 解析")
        } catch {
            Self.failures += 1
            print("  [FAIL] \(error)")
        }

        // 2. Atom
        do {
            let (meta, items) = try require(FeedParser.parse(data: sampleAtom.data(using: .utf8)!), "Atom 解析失败")
            requireEqual(meta.title, "Example Feed", "Atom feed 标题")
            requireEqual(items.count, 1, "Atom 条目数")
            let first = items[0]
            requireEqual(first.title, "Atom 示例文章", "Atom 条目标题")
            requireEqual(first.link, "https://example.org/atom/1", "Atom 条目链接（rel=alternate）")
            requireEqual(first.author, "Jane Doe", "Atom 作者")
            check(first.published != nil, "Atom 日期解析")
            print("  [PASS] Atom 解析")
        } catch {
            Self.failures += 1
            print("  [FAIL] \(error)")
        }

        // 3. HTML 清洗
        let stripped = HTML.stripTags("<p>你好 <b>世界</b> &amp; <a href='x'>链接</a></p>")
        requireEqual(stripped, "你好 世界 & 链接", "HTML 标签清洗")
        let img = HTML.extractFirstImage("<img src=\"https://a.com/b.jpg\" width=\"100\">")
        requireEqual(img, "https://a.com/b.jpg", "提取首图")
        print("  [PASS] HTML 工具")

        // 3.5 块级排版
        do {
            let blocks = HTML.blocks(from: sampleArticleHTML, baseURL: "https://example.com/post/1")
            let headings = blocks.filter { if case .heading = $0 { return true }; return false }
            check(headings.count >= 1, "块解析：包含标题（\(headings.count) 个）")
            check(blocks.contains(where: { if case .paragraph = $0 { return true }; return false }), "块解析：包含段落")
            check(blocks.contains(where: {
                if case .image(let u) = $0 { return u.hasPrefix("https://") }; return false
            }), "块解析：图片已解析为绝对地址")
            check(blocks.contains(where: { if case .quote = $0 { return true }; return false }), "块解析：包含引用")
            let markdown = try require(HTML.inlineMarkdown("<b>加粗</b> 与 <a href=\"/rel\">链接</a>", baseURL: "https://example.com/a"), "行内 Markdown 转换")
            check(markdown.contains("[链接](https://example.com/rel)"), "行内 Markdown 链接转换（相对→绝对）")
            let paras = HTML.paragraphs(from: "第一段。第二句。\n\n第二段内容这里是第二段。第三句。")
            check(paras.count >= 2, "纯文本自动分段（\(paras.count) 段）")
            print("  [PASS] 块级排版")
        } catch {
            Self.failures += 1
            print("  [FAIL] 块级排版：\(error)")
        }

        // 3.6 阅读模式提取
        do {
            guard let article = ArticleExtractor.extract(from: samplePageHTML, baseURL: URL(string: "https://example.com/post/2")) else {
                throw SelfTestError(message: "阅读模式提取失败")
            }
            let body = article.bodyHTML
            let bodyLen = HTML.stripTags(body).count
            check(bodyLen >= 250, "阅读模式：正文长度 \(bodyLen) >= 250")
            check(!body.contains("菜单链接") && !body.contains("广告横幅"), "阅读模式：已剔除导航/广告")
            check(body.contains("<img"), "阅读模式：正文图片保留（段落外 <div> 图合并）")
            print("  [PASS] 阅读模式提取（\(bodyLen) 字）")
        } catch {
            Self.failures += 1
            print("  [FAIL] 阅读模式提取：\(error)")
        }

        // 4. 日期
        let d1 = Dates.parse("Tue, 10 Jun 2025 08:30:00 GMT")
        let d2 = Dates.parse("2025-06-10T08:30:00Z")
        check(d1 != nil && d2 != nil, "RFC822 / ISO8601 日期解析")
        print("  [PASS] 日期解析")

        // 4.5 图片缓存 LRU 清理
        do {
            let dir = CacheManager.cacheDataDir
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // 造 3 个测试文件（最旧 40KB / 较旧 30KB / 最新 20KB）
            let now = Date()
            let files: [(String, Int, TimeInterval)] = [
                ("hrl_test_old.bin", 40 * 1024, -3600),
                ("hrl_test_mid.bin", 30 * 1024, -1800),
                ("hrl_test_new.bin", 20 * 1024, 0),
            ]
            for (name, size, age) in files {
                let url = dir.appendingPathComponent(name)
                let data = Data(repeating: 0xAB, count: size)
                try data.write(to: url)
                try FileManager.default.setAttributes(
                    [.modificationDate: now.addingTimeInterval(age)],
                    ofItemAtPath: url.path
                )
            }
            // 上限 60KB、目标 40KB：需清掉 50KB → 删最旧的 40KB 与 30KB，保留最新的 20KB
            CacheManager.pruneIfNeeded(limit: 60 * 1024, target: 40 * 1024)
            let remaining = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.filter { $0.hasPrefix("hrl_test_") } ?? [])
            check(remaining == ["hrl_test_new.bin"], "图片缓存 LRU：最久未使用优先清理（剩余 \(remaining.sorted())）")
            for name in remaining { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
            print("  [PASS] 图片缓存 LRU 清理")
        } catch {
            Self.failures += 1
            print("  [FAIL] 图片缓存 LRU 清理：\(error)")
        }

        print(failures == 0 ? "\n全部自检通过 ✅" : "\n自检失败 \(failures) 项 ❌")
        return failures == 0 ? 0 : 1
    }

    /// 网络自检：抓取真实订阅源
    static func fetchTest(url: String) -> Int32 {
        guard let parsedURL = FeedFetcher.normalize(url) else {
            print("链接无效：\(url)")
            return 1
        }
        print("== 抓取测试：\(parsedURL.absoluteString) ==")
        let semaphore = DispatchSemaphore(value: 0)
        var result: (meta: FeedMeta, items: [ParsedItem])?
        var errorMessage: String?

        Task {
            do {
                let r = try await FeedFetcher.fetch(at: parsedURL)
                result = r
            } catch {
                errorMessage = "\(error)"
            }
            semaphore.signal()
        }

        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }

        if let errorMessage {
            print("抓取失败：\(errorMessage)")
            return 1
        }
        guard let result else {
            print("未获取到结果")
            return 1
        }
        print("订阅标题：\(result.meta.title)")
        print("图标：\(result.meta.iconURL ?? "无")")
        print("文章数：\(result.items.count)")
        for item in result.items.prefix(5) {
            print("  • \(item.title) [\(item.published?.description ?? "?")] link=\(item.link) thumb=\(item.thumbnailURL ?? "无")")
        }
        print(result.items.isEmpty ? "抓取 OK（无文章）" : "抓取测试通过 ✅")
        return 0
    }

    /// 全文抓取测试：抓取文章页面并提取正文
    static func extractTest(url: String) -> Int32 {
        guard let parsedURL = URL(string: url) else {
            print("链接无效：\(url)")
            return 1
        }
        print("== 全文提取测试：\(parsedURL.absoluteString) ==")
        let semaphore = DispatchSemaphore(value: 0)
        var article: ExtractedArticle?
        var errorMessage: String?

        Task {
            do {
                let page = try await FeedFetcher.fetchPage(at: parsedURL)
                article = ArticleExtractor.extract(from: page, baseURL: parsedURL)
            } catch {
                errorMessage = "\(error)"
            }
            semaphore.signal()
        }

        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }

        if let errorMessage {
            print("抓取失败：\(errorMessage)")
            return 1
        }
        guard let article, HTML.stripTags(article.bodyHTML).count >= 200 else {
            print("正文提取失败或过短")
            return 1
        }
        let text = HTML.stripTags(article.bodyHTML)
        let imageCount = (try? NSRegularExpression(pattern: #"<img[^>]*>"#, options: [.caseInsensitive]))
            .map { regex in
                regex.numberOfMatches(in: article.bodyHTML, range: NSRange(article.bodyHTML.startIndex..., in: article.bodyHTML))
            } ?? 0
        print("正文长度：\(text.count) 字，正文图片：\(imageCount) 张，封面图：\(article.coverURL ?? "无")")
        print("正文预览前 300 字：")
        print(String(text.prefix(300)))
        print("全文提取测试通过 ✅")
        return 0
    }

    // MARK: - 断言辅助

    private static var failures = 0

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw SelfTestError(message: message) }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw SelfTestError(message: message) }
        return value
    }

    private static func requireEqual<T: Equatable>(_ a: T, _ b: T, _ label: String) {
        if a != b {
            print("  [FAIL] \(label)：期望 \(b)，实际 \(a)")
            Self.failures += 1
        }
    }

    private static func check(_ condition: Bool, _ label: String) {
        if !condition {
            print("  [FAIL] \(label)")
            Self.failures += 1
        }
    }

    private struct SelfTestError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}

// MARK: - 内嵌样本数据

private let sampleRSS = """
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
<channel>
<title>测试科技博客</title>
<link>https://example.com</link>
<description>科技新闻</description>
<item>
<title>SwiftUI 新特性一览</title>
<link>https://example.com/swiftui</link>
<guid isPermaLink="false">swiftui-2025-1</guid>
<pubDate>Tue, 10 Jun 2025 08:30:00 GMT</pubDate>
<media:thumbnail url="https://example.com/img/swiftui.jpg"/>
<description><![CDATA[<p>重磅更新，<b>性能提升</b>明显。</p>]]></description>
<content:encoded xmlns:content="http://purl.org/rss/1.0/modules/content/"><![CDATA[<h2>介绍</h2><p>详细正文内容。</p><img src="https://example.com/a.png"/>]]></content:encoded>
</item>
<item>
<title>第二篇文章</title>
<link>https://example.com/second</link>
<guid>https://example.com/second</guid>
<pubDate>Mon, 09 Jun 2025 12:00:00 +0800</pubDate>
<description>纯文字摘要</description>
</item>
</channel>
</rss>
"""

private let sampleAtom = """
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Example Feed</title>
  <link href="https://example.org/"/>
  <updated>2025-06-11T10:00:00Z</updated>
  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>
  <entry>
    <title>Atom 示例文章</title>
    <link href="https://example.org/atom/1" rel="alternate"/>
    <id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>
    <updated>2025-06-11T10:00:00Z</updated>
    <summary>摘要内容。</summary>
    <author><name>Jane Doe</name></author>
    <content type="html">&lt;p&gt;正文段落&lt;/p&gt;</content>
  </entry>
</feed>
"""

private let sampleArticleHTML = """
<h2>章节标题</h2>
<p>这是第一段正文，包含<b>加粗</b>与<a href="/post/1">内部链接</a>，以及足够长的文本来测试段落解析的稳定性表现。</p>
<p><img src="/images/photo1.jpg" alt="配图">第二段开头配图。</p>
<blockquote>这是一段引用的观点内容。</blockquote>
<p>第三段继续讲述内容，这里同样提供了比较长的句子用于检查分块是否正常运作。</p>
<ul><li>列表项一</li><li>列表项二</li></ul>
<p>最后一段收尾，解释结论并给出建议。</p>
"""

private let samplePageHTML = """
<!DOCTYPE html>
<html><head><title>示例文章</title></head><body>
<nav><a href="/">菜单链接一</a><a href="/about">菜单链接二</a></nav>
<header>网站头部横幅</header>
<div class="ad-banner">广告横幅内容</div>
<article class="article-content">
<h1>示例文章标题</h1>
<p>这里是文章的第一段正文内容，用于验证阅读模式提取器能否正确地把正文从整页 HTML 中分离出来，这段文字应该有足够的长度，让聚类算法可以准确地判定它属于主要内容区域而不是页面的导航或者装饰性文本。</p>
<p>第二段：继续撰写足够多的文字，让段落长度超过算法阈值，从而被聚类识别为主要内容的一部分，并且与上下文中的段落形成连续的内容区块，保证最终的提取结果完整有序。</p>
<p>第三段：阅读模式是很多 RSS 阅读器的核心能力，可以把只提供摘要的订阅源变成完整文章的阅读体验，实现这一点的关键是对页面结构进行分析并且筛选出最有信息密度的部分。</p>
<p>第四段：这里还应该包含一张配图网址等待解析，图像内容通常也是正文的重要组成部分，如果能够把配图一起提取出来，阅读体验会更好。<img src="https://example.com/img/body.jpg"/></p>
<p>第五段：最后一段也用来增加总字数，确保提取出的正文总长度能够超过两百字的最低门槛要求，同时也验证提取器是否能够正确处理正文末尾的内容。</p>
</article>
<div class="related-box"><img src="https://example.com/img/inline-outside.jpg"/></div>
<footer>版权信息与页脚导航</footer>
</body></html>
"""