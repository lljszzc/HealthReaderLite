import Foundation

/// 基于 Foundation XMLParser 的 RSS 2.0 / Atom 解析器（零第三方依赖）
final class FeedParser: NSObject, XMLParserDelegate {
    private var isAtom = false
    private var feedTitle = ""
    private var feedIconURL: String?

    private var inItem = false
    private var stack: [String] = []
    private var buffer = ""
    private var draft: ItemDraft?
    private var items: [ParsedItem] = []

    // 元素间传递的中间态
    private var linkHref: String?
    private var linkRel: String?
    private var generatedLink = ""
    private var enclosureURL: String?
    private var thumbnailURL: String?

    // Atom 子结构
    private var authorName = ""
    private var inAuthor = false
    private var inContent = false

    final class ItemDraft {
        var guid = ""
        var title = ""
        var link = ""
        var summary = ""
        var contentHTML: String?
        var author = ""
        var publishedRaw: String?
        var thumbnailURL: String?
    }

    // MARK: - 对外接口

    /// 同步解析：返回 (feed 元信息, 文章列表)；失败返回 nil
    static func parse(data: Data) -> (meta: FeedMeta, items: [ParsedItem])? {
        let parser = FeedParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.shouldProcessNamespaces = false
        xml.shouldReportNamespacePrefixes = true
        guard xml.parse(), !parser.feedTitle.isEmpty || !parser.items.isEmpty else { return nil }
        return (FeedMeta(title: parser.feedTitle, iconURL: parser.feedIconURL), parser.items)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = qName ?? elementName
        stack.append(name)
        buffer = ""

        if name == "item" || name == "entry" {
            inItem = true
            draft = ItemDraft()
            generatedLink = ""
            enclosureURL = nil
            thumbnailURL = nil
            authorName = ""
            inContent = false
            return
        }
        if name == "channel" || name == "feed" {
            isAtom = (name == "feed")
            return
        }
        guard inItem else {
            // 频道级元素：清空待填充的标题/图标缓冲
            if name == "title" || name == "icon" || name == "url" { feedIconURL = nil }
            return
        }

        // 文章级元素
        switch name {
        case "link":
            linkHref = attributeDict["href"]
            linkRel = attributeDict["rel"] ?? "alternate"
        case "enclosure":
            enclosureURL = attributeDict["url"]
            if attributeDict["type"]?.hasPrefix("image") == true { thumbnailURL = attributeDict["url"] }
        case "thumbnail", "media:thumbnail":
            if let u = attributeDict["url"] { thumbnailURL = u }
        case "content", "media:content":
            if let u = attributeDict["url"], let type = attributeDict["type"], type.hasPrefix("image") {
                thumbnailURL = u
            }
        case "image", "media:image":
            if let u = attributeDict["url"] { thumbnailURL = u }
        case "author", "dc:creator":
            inAuthor = true
            authorName = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
        if inAuthor { authorName += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = qName ?? elementName
        _ = stack.popLast()

        if name == "item" || name == "entry" {
            finalizeItem()
            inItem = false
            draft = nil
            return
        }
        guard inItem else {
            // 频道级收尾：填充 feed 标题与图标
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "title", feedTitle.isEmpty {
                feedTitle = text
            } else if (name == "url" || name == "icon"), feedIconURL == nil, !text.isEmpty {
                feedIconURL = text
            }
            return
        }

        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let draft else { return }

        switch name {
        case "title":
            if draft.title.isEmpty { draft.title = text }
        case "guid", "id":
            if draft.guid.isEmpty {
                draft.guid = text
                if text.contains("://"), draft.link.isEmpty {
                    draft.link = text
                }
            }
        case "link":
            if isAtom {
                if linkRel == "alternate" || linkRel == "via", !linkHref.isNilOrEmpty, draft.link.isEmpty {
                    draft.link = linkHref!
                } else if linkHref.isNilOrEmpty, !text.isEmpty, draft.link.isEmpty {
                    draft.link = text
                }
                generatedLink = linkHref ?? text
            } else {
                if draft.link.isEmpty { draft.link = text }
            }
            linkHref = nil
            linkRel = nil
        case "description", "summary":
            if draft.summary.isEmpty { draft.summary = text }
        case "content", "encoded":
            draft.contentHTML = text
            draft.summary = draft.summary.isEmpty ? HTML.stripTags(text) : draft.summary
        case "pubDate", "date", "updated", "published", "modified", "dc:date":
            if draft.publishedRaw == nil { draft.publishedRaw = text }
        case "author", "dc:creator":
            inAuthor = false
            if draft.author.isEmpty { draft.author = authorName.trimmingCharacters(in: .whitespacesAndNewlines) }
        case "name": // Atom <author><name>
            if inAuthor && draft.author.isEmpty {
                draft.author = text
            }
        default:
            break
        }
    }

    private func finalizeItem() {
        guard let draft else { return }
        // link 兜底
        var link = draft.link
        if link.isEmpty { link = generatedLink }
        if link.isEmpty { link = enclosureURL ?? "" }
        if link.isEmpty && draft.guid.contains("://") { link = draft.guid }

        var thumb = draft.thumbnailURL ?? thumbnailURL
        let contentForImg = draft.contentHTML ?? draft.summary
        if thumb.isNilOrEmpty {
            thumb = HTML.extractFirstImage(contentForImg)
        }

        let published = Dates.parse(draft.publishedRaw) ?? Date()
        let cleanSummary = draft.summary.isEmpty
            ? ""
            : HTML.stripTags(draft.summary)
        let item = ParsedItem(
            guid: draft.guid,
            title: draft.title.isEmpty ? "(无标题)" : HTML.decodeEntities(draft.title),
            link: link,
            summary: cleanSummary,
            contentHTML: draft.contentHTML,
            author: draft.author.isEmpty ? nil : draft.author,
            published: published,
            thumbnailURL: thumb
        )
        // 空 item 丢弃
        if !item.guid.isEmpty || !item.link.isEmpty || !item.title.isEmpty {
            items.append(item)
        }
    }
}

fileprivate extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        guard let self else { return true }
        return self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}