import Foundation

/// 图片磁盘缓存管理器：500MB 上限，超限自动按"最久未使用"清理
/// 配合 URLCache.shared（AsyncImage 缩略图/头像/正文图共用）
enum CacheManager {
    /// 磁盘缓存硬上限（500MB）
    static let maxBytes: Int64 = 500 * 1024 * 1024
    /// 清理后的目标水位（保留余量，避免频繁清理）
    static let pruneTargetBytes: Int64 = 400 * 1024 * 1024
    /// URLCache 磁盘路径（相对 ~/Library/Caches）
    static let diskPath = "HealthReaderLite"

    static var cachesRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    /// 缓存数据目录（URLCache 实际落盘位置）
    static var cacheDataDir: URL {
        cachesRoot.appendingPathComponent(diskPath, isDirectory: true)
            .appendingPathComponent("fsCachedData", isDirectory: true)
    }

    /// 配置共享 URL 缓存（64MB 内存 / 500MB 磁盘），让 AsyncImage 图片只下载一次
    static func configure() {
        try? FileManager.default.createDirectory(
            at: cachesRoot.appendingPathComponent(diskPath, isDirectory: true),
            withIntermediateDirectories: true
        )
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: Int(maxBytes),
            diskPath: diskPath
        )
        Log.t("图片缓存已配置：磁盘上限 \(maxBytes / 1024 / 1024)MB")
    }

    /// 扫描磁盘缓存，统计总量；超过上限则按最久未使用清理到目标水位
    /// - Parameters:
    ///   - limit: 上限（默认 500MB，供自测注入小阈值）
    ///   - target: 清理后的目标水位（默认 400MB）
    static func pruneIfNeeded(limit: Int64? = nil, target: Int64? = nil) {
        let max = limit ?? maxBytes
        let targetBytes = target ?? pruneTargetBytes
        let dir = cacheDataDir
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
        ) else { return }

        var total: Int64 = 0
        let dated: [(url: URL, date: Date, size: Int64)] = files.compactMap { url in
            guard let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
            ), let size = values.fileSize else { return nil }
            let date = values.contentAccessDate ?? values.contentModificationDate ?? .distantPast
            total += Int64(size)
            return (url, date, Int64(size))
        }

        guard total > max else { return }
        // 最久未使用 → 最早被清理
        let sorted = dated.sorted { $0.date < $1.date }
        var freed: Int64 = 0
        for entry in sorted where total - freed > targetBytes {
            if (try? FileManager.default.removeItem(at: entry.url)) != nil {
                freed += entry.size
            }
        }
        let freedMB = freed / 1024 / 1024
        Log.t("图片缓存超过 \(max / 1024 / 1024)MB 上限，已按最久未使用清理 \(freedMB)MB（现约 \((total - freed) / 1024 / 1024)MB）")
    }
}