import Foundation

/// 全文提取结果
struct ExtractedArticle {
    let bodyHTML: String
    /// 页面封面图（og:image / ld+json image / 横幅图），供无缩略图的文章回填
    let coverURL: String?
}

/// 轻量"阅读模式"正文提取器（零第三方依赖）
/// 策略：先按 <p> 段落聚类（主内容区通常是连续的长段落），并合并正文区域内的
/// 段落外图片（<div> 包裹的配图等）；失败则按内容容器 class/id 兜底。
enum ArticleExtractor {

    /// 从文章页面 HTML 提取正文 + 封面图；失败返回 nil
    static func extract(from pageHTML: String, baseURL: URL?) -> ExtractedArticle? {
        var html = pageHTML
        // 1) 移除非内容区（figure/picture 只剥外壳，保留内部 <img>）
        html = stripElements(html, tags: [
            "script", "style", "noscript", "iframe", "form", "nav",
            "header", "footer", "aside", "svg", "button", "input",
            "select", "textarea"
        ])
        for wrapper in ["figure", "figcaption", "picture"] {
            html = HTML.replaceRegex("</?\(wrapper)[^>]*>", in: html, with: " ")
        }
        // 2) 封面图（og:image 优先）
        let cover = extractCoverURL(from: html)
        // 3) <p> 段落聚类 + 图片合并
        if let byParagraphs = extractByParagraphs(html), textLength(of: byParagraphs) >= 200 {
            return ExtractedArticle(bodyHTML: byParagraphs, coverURL: cover)
        }
        // 4) 容器兜底
        if let byContainer = extractByContainer(html), textLength(of: byContainer) >= 200 {
            return ExtractedArticle(bodyHTML: byContainer, coverURL: cover)
        }
        return nil
    }

    // MARK: - 内部实现

    private static func stripElements(_ html: String, tags: [String]) -> String {
        var out = html
        for tag in tags {
            out = HTML.replaceRegex("<\(tag)[^>]*>.*?</\(tag)>", in: out, with: " ", dotAll: true)
            out = HTML.replaceRegex("<\(tag)[^>]*/>", in: out, with: " ")
        }
        return out
    }

    private struct Paragraph {
        let html: String
        let length: Int
        let start: Int   // UTF-16 offset
        let end: Int
    }

    private static func extractCoverURL(from html: String) -> String? {
        // og:image / twitter:image meta
        let metaPattern = #"(?:og:image|twitter:image)[^>]*content=["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: metaPattern, options: [.caseInsensitive]) {
            let ns = NSRange(html.startIndex..., in: html)
            if let m = regex.firstMatch(in: html, range: ns),
               let r = Range(m.range(at: 1), in: html) {
                return HTML.decodeEntities(String(html[r]))
            }
        }
        // ld+json 的 image 字段
        let jsonPattern = #""image"\s*:\s*"([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: jsonPattern) {
            let ns = NSRange(html.startIndex..., in: html)
            if let m = regex.firstMatch(in: html, range: ns),
               let r = Range(m.range(at: 1), in: html) {
                return HTML.decodeEntities(String(html[r]))
            }
        }
        // 横幅/封面 class img
        let bannerPattern = #"<img[^>]+src=["']([^"']+)["'][^>]*class=["'][^"']*(?:banner|cover|hero)[^"']*["']"#
        if let regex = try? NSRegularExpression(pattern: bannerPattern, options: [.caseInsensitive]) {
            let ns = NSRange(html.startIndex..., in: html)
            if let m = regex.firstMatch(in: html, range: ns),
               let r = Range(m.range(at: 1), in: html) {
                return HTML.decodeEntities(String(html[r]))
            }
        }
        return nil
    }

    private static func extractByParagraphs(_ html: String) -> String? {
        let pattern = #"<p[^>]*>(.*?)</p>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return nil }
        var paragraphs: [Paragraph] = []
        let ns = NSRange(html.startIndex..., in: html)
        for m in regex.matches(in: html, range: ns) {
            guard let full = Range(m.range, in: html), let inner = Range(m.range(at: 1), in: html) else { continue }
            let segHTML = String(html[full])
            paragraphs.append(Paragraph(
                html: segHTML,
                length: HTML.stripTags(String(html[inner])).count,
                start: m.range.location,
                end: m.range.location + m.range.length
            ))
        }
        guard paragraphs.count > 1 || paragraphs.first?.length ?? 0 >= 60 else {
            return paragraphs.first.map { $0.html }
        }

        // 聚类：连续"长段落"（>=60 字），允许当中跳过 1 个短段（如小标题）
        var best: (start: Int, end: Int, score: Int) = (0, -1, 0)
        var i = 0
        while i < paragraphs.count {
            if paragraphs[i].length < 60 { i += 1; continue }
            var j = i
            var skipped = 0
            var score = 0
            while j < paragraphs.count {
                if paragraphs[j].length >= 60 {
                    skipped = 0
                    score += paragraphs[j].length
                } else {
                    skipped += 1
                    if skipped > 1 { break }
                }
                j += 1
            }
            if score > best.score { best = (i, j - 1, score) }
            i = j
        }
        guard best.end >= best.start, best.score > 0 else { return nil }

        var chosen = Array(paragraphs[best.start...best.end])
        while let first = chosen.first, first.length < 60 { chosen.removeFirst() }
        while let last = chosen.last, last.length < 60 { chosen.removeLast() }
        guard !chosen.isEmpty else { return nil }
        let firstOffset = chosen[0].start
        let lastOffset = chosen[chosen.count - 1].end

        // 收集正文区域内的段落外 <img>（<div> 包裹配图等），按位置归位
        var strayImages: [(offset: Int, html: String)] = []
        if let imgRegex = try? NSRegularExpression(pattern: #"<img[^>]*>"#, options: [.caseInsensitive]) {
            for m in imgRegex.matches(in: html, range: ns) {
                let offset = m.range.location
                guard offset >= firstOffset, offset < lastOffset,
                      let r = Range(m.range, in: html) else { continue }
                // 跳过已在选中段落内部的图（段落 HTML 自带）
                let inside = chosen.contains { $0.start <= offset && offset < $0.end }
                if !inside { strayImages.append((offset, String(html[r]))) }
            }
        }

        // 按 offset 合并段落与游离图片
        var result: [String] = []
        var index = 0
        for img in strayImages.sorted(by: { $0.offset < $1.offset }) {
            while index < chosen.count, chosen[index].end <= img.offset {
                result.append(chosen[index].html)
                index += 1
            }
            if index < chosen.count, chosen[index].start <= img.offset, img.offset < chosen[index].end {
                continue // 理论不可达（已在上面过滤），防御
            }
            result.append(img.html)
        }
        while index < chosen.count {
            result.append(chosen[index].html)
            index += 1
        }
        return result.joined(separator: "\n")
    }

    private static func extractByContainer(_ html: String) -> String? {
        let pattern = #"<(article|section|div)[^>]*(?:class|id)=["'][^"']*(?:content|article|post|entry|body)[^"']*["'][^>]*>(.*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return nil }
        var best: (html: String, length: Int) = ("", 0)
        let ns = NSRange(html.startIndex..., in: html)
        for m in regex.matches(in: html, range: ns) {
            guard let r = Range(m.range, in: html) else { continue }
            let whole = String(html[r])
            let len = HTML.stripTags(whole).count
            if len > best.length { best = (whole, len) }
        }
        guard best.length >= 200 else { return nil }
        return best.html
    }

    private static func textLength(of html: String) -> Int {
        HTML.stripTags(html).count
    }
}

// MARK: - 网络：抓取文章页面

extension FeedFetcher {
    /// 抓取文章页面 HTML（浏览器 UA，规避简单反爬）
    static func fetchPage(at url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,*/*", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 抓取并提取文章全文正文 + 封面图；失败返回 nil
    static func fetchArticleBody(at url: URL) async -> ExtractedArticle? {
        do {
            let page = try await fetchPage(at: url)
            return ArticleExtractor.extract(from: page, baseURL: url)
        } catch {
            Log.error("全文抓取失败：\(url.absoluteString) - \(error.localizedDescription)")
            return nil
        }
    }
}