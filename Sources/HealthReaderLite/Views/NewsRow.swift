import SwiftUI

/// 新闻列表行：图标 + 标题 + 缩略小图
struct NewsRow: View {
    let item: FeedItem
    @ObservedObject var store: AppStore
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(item.read ? Color.clear : Color.accentColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if let feed = store.feed(item.feedID) {
                            FaviconView(feed: feed, size: 13)
                                .padding(.top, 1)
                            Text(feed.title)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(Dates.relative(item.published))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Text(item.title)
                        .font(.system(size: 13, weight: item.read ? .regular : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                if let thumb = item.thumbnailURL, let url = URL(string: thumb) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .interpolation(.medium)
                                .scaledToFill()
                        default:
                            thumbPlaceholder
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private var thumbPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
            Image(systemName: "photo")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        }
    }
}