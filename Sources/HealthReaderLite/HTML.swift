import Foundation

// MARK: - HTML 清洗 / 日期解析 工具

enum HTML {
    /// 去除标签、解码实体、压缩空白，得到纯文本
    static func stripTags(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "\u{00a0}", with: " ")
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ raw: String) -> String {
        var s = raw
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
            "&#39;": "'", "&nbsp;": " ", "&hellip;": "…", "&mdash;": "—", "&ndash;": "–",
            "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&middot;": "·",
            "&raquo;": "»", "&laquo;": "«", "&times;": "×", "&copy;": "©", "&reg;": "®"
        ]
        for (k, v) in named { s = s.replacingOccurrences(of: k, with: v) }
        return decodeNumericEntities(s)
    }

    private static func decodeNumericEntities(_ s: String) -> String {
        let pattern = #"&#(x?)([0-9a-fA-F]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = NSRange(s.startIndex..., in: s)
        var out = ""
        var last = s.startIndex
        for match in regex.matches(in: s, range: ns) {
            guard let r = Range(match.range, in: s) else { continue }
            out += s[last..<r.lowerBound]
            let hexRange = Range(match.range(at: 1), in: s)
            let numRange = Range(match.range(at: 2), in: s)
            let isHex = hexRange.map { s[$0] == "x" || s[$0] == "X" } ?? false
            if let numStr = numRange.map({ String(s[$0]) }), let scalarValue = Int(numStr, radix: isHex ? 16 : 10),
               let scalar = UnicodeScalar(scalarValue) {
                out.unicodeScalars.append(scalar)
            } else {
                out += s[r]
            }
            last = r.upperBound
        }
        out += s[last...]
        return out
    }

    /// 提取 HTML 中第一个 <img> 的 src
    static func extractFirstImage(_ html: String) -> String? {
        let patterns = [
            #"<img[^>]+src=["']([^"']+)["']"#,
            #"<img[^>]+src=([^\s>"']+)"#
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: html) {
                return String(html[r])
            }
        }
        return nil
    }

    /// 相对地址转绝对
    static func resolve(_ href: String?, base: String?) -> String? {
        guard let href = href?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty else { return nil }
        if href.hasPrefix("http://") || href.hasPrefix("https://") { return href }
        if href.hasPrefix("//") { return "https:" + href }
        guard let base, let baseURL = URL(string: base) else { return nil }
        if let u = URL(string: href, relativeTo: baseURL) { return u.absoluteString }
        return nil
    }

    /// 把 HTML 转成富文本（用于阅读窗口）；失败返回 nil。返回 Sendable 类型，可在后台线程渲染。
    static func renderHTML(_ html: String) -> AttributedString? {
        guard let data = html.data(using: .utf8) else { return nil }
        guard let attr = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else { return nil }
        return AttributedString(attr)
    }
}

// MARK: - 块级排版引擎（统一美观的正文渲染）

/// 正文排版块
enum HTMLBlock: Hashable {
    case paragraph(String)      // 内容为轻量 Markdown（链接/粗体/斜体）
    case heading(Int, String)   // 级别 + Markdown 文本
    case image(String)          // 绝对 URL
    case quote(String)
    case listItem(String)
}

extension HTML {
    /// 用 NSRegularExpression 替换（支持 dotAll / 忽略大小写）
    static func replaceRegex(_ pattern: String, in text: String, with template: String,
                             dotAll: Bool = false, caseInsensitive: Bool = true) -> String {
        var options: NSRegularExpression.Options = []
        if dotAll { options.insert(.dotMatchesLineSeparators) }
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func removeTagBlocks(_ html: String, tags: [String]) -> String {
        var out = html
        for tag in tags {
            out = replaceRegex("<\(tag)[^>]*>.*?</\(tag)>", in: out, with: " ", dotAll: true)
        }
        return out
    }

    /// 从 HTML 正文切出排版块（后台线程调用）
    static func blocks(from raw: String, baseURL: String?) -> [HTMLBlock] {
        var html = removeTagBlocks(raw, tags: ["script", "style"])

        // 块级标签归一化为行分隔
        let blockPattern = #"(<br\s*/?>|<p[^>]*>|</p>|<div[^>]*>|</div>|<h[1-6][^>]*>|</h[1-6]>|<li[^>]*>|</li>|<blockquote[^>]*>|</blockquote>|<ul[^>]*>|</ul>|<ol[^>]*>|</ol>|<img[^>]*>)"#
        html = html.replacingOccurrences(of: blockPattern, with: "\n$1", options: .regularExpression)
        let lines = html.components(separatedBy: "\n")

        var blocks: [HTMLBlock] = []
        var listBuffer: [String] = []

        func flushList() {
            for item in listBuffer { blocks.append(.listItem(item)) }
            listBuffer = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()

            // 列表结尾
            if lower.hasPrefix("</ul") || lower.hasPrefix("</ol") {
                flushList()
                continue
            }
            if lower.hasPrefix("<ul") || lower.hasPrefix("<ol") { continue }

            // 标题
            if let level = headingLevel(trimmed) {
                let level = level
                var content = trimmed
                content = content.replacingOccurrences(of: #"^<h[1-6][^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
                content = content.replacingOccurrences(of: #"</h[1-6]>"#, with: "", options: [.regularExpression, .caseInsensitive])
                let md = inlineMarkdown(content, baseURL: baseURL)
                if !md.isEmpty { blocks.append(.heading(level, md)) }
                continue
            }
            // 引用
            if lower.hasPrefix("<blockquote") {
                var content = trimmed
                content = content.replacingOccurrences(of: #"</?blockquote[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
                let md = inlineMarkdown(content, baseURL: baseURL)
                if !md.isEmpty { blocks.append(.quote(md)) }
                continue
            }
            // 列表项
            if lower.hasPrefix("<li") {
                var content = trimmed
                content = content.replacingOccurrences(of: #"</?li[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
                let md = inlineMarkdown(content, baseURL: baseURL)
                if !md.isEmpty { listBuffer.append(md) }
                continue
            }
            // 图片（可能夹带文字）
            var remaining = trimmed
            let imageURLs = extractAllImageURLs(from: trimmed, base: baseURL)
            if !imageURLs.isEmpty {
                for url in imageURLs { blocks.append(.image(url)) }
                remaining = remaining.replacingOccurrences(of: #"<img[^>]*>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            }
            // 普通段落
            let md = inlineMarkdown(remaining, baseURL: baseURL)
            if !md.isEmpty { blocks.append(.paragraph(md)) }
        }
        flushList()
        return blocks
    }

    /// 纯文本自动分段：以空行作为段落边界，超长段落再按句子拆分（提升可读性）
    static func paragraphs(from text: String) -> [String] {
        let cleaned = decodeEntities(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // 空行分段（尊重原文意图），段内单个换行视为空格
        let rawParagraphs = cleaned.components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }

        // 超长段落按句子拆分
        var result: [String] = []
        for paragraph in rawParagraphs {
            if paragraph.count <= 360 {
                result.append(paragraph)
                continue
            }
            var piece = ""
            for sentence in splitSentences(paragraph) {
                let trimmed = sentence.trimmingCharacters(in: .whitespaces)
                if piece.count + trimmed.count > 360, !piece.isEmpty {
                    result.append(piece)
                    piece = trimmed
                } else {
                    piece = piece.isEmpty ? trimmed : piece + trimmed
                }
            }
            if !piece.isEmpty { result.append(piece) }
        }
        return result
    }

    /// 行内 HTML → 轻量 Markdown（链接/粗体/斜体/代码），保证统一字体渲染
    static func inlineMarkdown(_ raw: String, baseURL: String?) -> String {
        var out = ""
        let s = raw
        guard let linkRegex = try? NSRegularExpression(
            pattern: #"<a\s+[^>]*href=["']([^"']*)["'][^>]*>(.*?)</a>"#,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else { return decodeEntities(raw) }

        var last = s.startIndex
        for m in linkRegex.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range, in: s) else { continue }
            out += s[last..<r.lowerBound]
            let href = Range(m.range(at: 1), in: s).map { String(s[$0]) } ?? ""
            let text = Range(m.range(at: 2), in: s).map { String(s[$0]) } ?? ""
            var resolved = decodeEntities(href)
            resolved = HTML.resolve(resolved, base: baseURL) ?? resolved
            out += "[\(text)](\(resolved))"
            last = r.upperBound
        }
        out += s[last...]

        for (open, close) in [("<b[^>]*>", "**"), ("<strong[^>]*>", "**"), ("<em[^>]*>", "*"), ("<i[^>]*>", "*"), ("<code[^>]*>", "`")] {
            out = out.replacingOccurrences(of: open, with: close, options: [.regularExpression, .caseInsensitive])
            let closeTag = close == "`" ? "</code>" : (close == "**" ? "</strong>|</b>" : "</em>|</i>")
            out = out.replacingOccurrences(of: closeTag, with: close, options: [.regularExpression, .caseInsensitive])
        }
        out = out.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: [.regularExpression, .caseInsensitive])
        out = out.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        out = decodeEntities(out)
        // 修整 markdown 符号与邻接空白
        out = out.replacingOccurrences(of: "** ", with: "**")
        out = out.replacingOccurrences(of: " **", with: "**")
        out = out.replacingOccurrences(of: "* ", with: "*")
        out = out.replacingOccurrences(of: " *", with: "*")
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func headingLevel(_ line: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"^<h([1-6])[^>]*>"#, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r = Range(m.range(at: 1), in: line) else { return nil }
        return Int(line[r])
    }

    private static func extractAllImageURLs(from html: String, base: String?) -> [String] {
        var urls: [String] = []
        let pattern = #"<img[^>]+src=["']([^"']+)["']"#
        let pattern2 = #"<img[^>]+data-src=["']([^"']+)["']"#
        for p in [pattern, pattern2] {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                for m in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                    if let r = Range(m.range(at: 1), in: html) {
                        var url = String(html[r])
                        url = decodeEntities(url)
                        if let resolved = resolve(url, base: base) { urls.append(resolved) }
                    }
                }
            }
        }
        // 去重
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    private static func splitSentences(_ s: String) -> [String] {
        let marked = s.replacingOccurrences(
            of: #"(?<=[。！？!?；;])"#,
            with: "\u{1}",
            options: .regularExpression
        )
        return marked.components(separatedBy: "\u{1}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - 日期解析

enum Dates {
    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    private static let rfc822Short: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    private static let rfc822NoZone: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss"
        return f
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 兜底格式（静态缓存，避免每次 new DateFormatter）
    private static let fallbackFormatters: [DateFormatter] = {
        ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd"].map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            return f
        }
    }()

    /// 兼容常见 RSS/Atom 日期格式
    static func parse(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let value = raw.replacingOccurrences(of: " UTC", with: " +0000")
        if let d = rfc822.date(from: value) { return d }
        if let d = rfc822Short.date(from: value) { return d }
        if let d = rfc822NoZone.date(from: value) { return d }
        if let d = iso8601.date(from: value) { return d }
        if let d = iso8601Plain.date(from: value) { return d }
        for f in fallbackFormatters {
            if let d = f.date(from: value) { return d }
        }
        return nil
    }

    /// 相对时间显示："刚刚 / n 分钟前 / n 小时前 / 昨天 / MM月dd日"
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 172800 { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM月dd日"
        return f.string(from: date)
    }
}