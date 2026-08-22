import Foundation

/// Lightweight file logging. The app runs headless, so this is the only way to see
/// what the selection watcher is actually doing.
enum Log {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        return dir.appendingPathComponent("WritingToolsAnywhere.log")
    }()

    private static let queue = DispatchQueue(label: "wta.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Off by default — the log records the text you select, which shouldn't reach disk
    /// unless debugging is deliberately turned on.
    static var isEnabled = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    static func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}
