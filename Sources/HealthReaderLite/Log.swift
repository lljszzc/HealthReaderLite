import Foundation

/// 极简日志：追加写入 Application Support 下的 debug.log，同时输出 stdout。
enum Log {
    static var consoleOnly = false
    static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("HealthReaderLite", isDirectory: true)
    }()

    private static let lock = NSLock()
    private static var fileHandle: FileHandle?

    static func t(_ message: String) {
        let line = "[\(Self.timestamp())] \(message)"
        if !consoleOnly { print(line) }
        write(line)
    }

    static func error(_ message: String) {
        let line = "[\(Self.timestamp())] [ERROR] \(message)"
        fputs("\(line)\n", stderr)
        write(line)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    private static func write(_ line: String) {
        if consoleOnly { return }
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            let file = appSupportDir.appendingPathComponent("debug.log")
            if fileHandle == nil {
                if !FileManager.default.fileExists(atPath: file.path) {
                    FileManager.default.createFile(atPath: file.path, contents: nil)
                }
                fileHandle = try FileHandle(forWritingTo: file)
                fileHandle?.seekToEndOfFile()
            }
            if let data = "\(line)\n".data(using: .utf8) {
                fileHandle?.write(data)
            }
        } catch {
            // 日志失败不影响主流程
        }
    }
}