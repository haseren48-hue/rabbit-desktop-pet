import Foundation

@MainActor
final class CodexTaskMonitor {
    private let onWorkingChanged: (Bool) -> Void
    private var activeFiles: Set<String> = []
    private var timer: Timer?
    private var hasBaseline = false

    init(onWorkingChanged: @escaping (Bool) -> Void) {
        self.onWorkingChanged = onWorkingChanged
    }

    func start() {
        timer?.invalidate()
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    private func scan() {
        let current = currentActiveTaskFiles()
        if hasBaseline {
            if current.isEmpty != activeFiles.isEmpty { onWorkingChanged(!current.isEmpty) }
        } else {
            hasBaseline = true
            onWorkingChanged(!current.isEmpty)
        }
        activeFiles = current
    }

    private func currentActiveTaskFiles() -> Set<String> {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Interrupted Codex runs can leave a final task_started event without a
        // matching task_complete. Only a recently updating session is live.
        let recentCutoff = Date().addingTimeInterval(-15 * 60)
        var result: Set<String> = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) >= recentCutoff,
                  isTaskActive(in: url) else { continue }
            result.insert(url.path)
        }
        return result
    }

    private func isTaskActive(in url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd() else { return false }
        let maximumTail: UInt64 = 512 * 1024
        try? handle.seek(toOffset: length > maximumTail ? length - maximumTail : 0)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return false }

        let started = text.range(of: "\"type\":\"task_started\"", options: .backwards)?.lowerBound
        let completed = text.range(of: "\"type\":\"task_complete\"", options: .backwards)?.lowerBound
        guard let started else { return false }
        guard let completed else { return true }
        return started > completed
    }
}
