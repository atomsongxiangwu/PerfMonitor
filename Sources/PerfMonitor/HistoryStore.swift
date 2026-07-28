import Foundation

enum HistoryExportFormat {
    case json
    case csv
}

private struct PersistedHistoryFile: Codable {
    var day: String
    var savedAt: Date
    var entries: [MetricsSnapshot]
}

private struct LegacyPersistedHistory: Codable {
    var savedAt: Date
    var entries: [MetricsSnapshot]
}

final class HistoryStore {
    private let directoryURL: URL
    private let legacyFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fm = FileManager.default
    private let calendar = Calendar.current
    private let retentionDays: Int
    private let fileNameDateFormatter: DateFormatter

    init(appName: String = "PerfMonitor", retentionDays: Int = 7) {
        self.retentionDays = retentionDays

        let baseURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directoryURL = baseURL.appendingPathComponent(appName, isDirectory: true)
        legacyFileURL = directoryURL.appendingPathComponent("history.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        fileNameDateFormatter = DateFormatter()
        fileNameDateFormatter.calendar = Calendar(identifier: .gregorian)
        fileNameDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        fileNameDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        fileNameDateFormatter.dateFormat = "yyyy-MM-dd"
    }

    func load() -> [MetricsSnapshot] {
        let dailyFiles = dailyFileURLs()
        if dailyFiles.isEmpty, let legacy = loadLegacy() {
            return normalize(legacy.entries)
        }

        let loaded = dailyFiles.flatMap(loadDailyFile)
        if !loaded.isEmpty {
            return normalize(loaded)
        }

        if let legacy = loadLegacy() {
            return normalize(legacy.entries)
        }

        return []
    }

    func save(_ entries: [MetricsSnapshot]) {
        do {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if entries.isEmpty {
                try removeAllHistoryFiles()
                return
            }

            let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.sampledAt) }
            for day in grouped.keys.sorted() {
                let payload = PersistedHistoryFile(
                    day: dayString(for: day),
                    savedAt: Date(),
                    entries: grouped[day, default: []]
                )
                try writeDailyFile(payload, for: day)
            }

            try pruneExpiredFiles(reference: entries.last?.sampledAt ?? Date())
            try removeLegacyIfNeeded()
        } catch {
            print("Failed to save history: \(error.localizedDescription)")
        }
    }

    func export(_ entries: [MetricsSnapshot], as format: HistoryExportFormat) throws -> Data {
        let normalized = normalize(entries)
        switch format {
        case .json:
            let payload = PersistedHistoryFile(
                day: "export",
                savedAt: Date(),
                entries: normalized
            )
            return try encoder.encode(payload)
        case .csv:
            return Data(csvString(for: normalized).utf8)
        }
    }

    func clear() throws {
        try removeAllHistoryFiles()
    }

    private func normalize(_ entries: [MetricsSnapshot]) -> [MetricsSnapshot] {
        entries.sorted { $0.sampledAt < $1.sampledAt }
    }

    private func writeDailyFile(_ payload: PersistedHistoryFile, for day: Date) throws {
        let data = try encoder.encode(payload)
        try data.write(to: fileURL(for: day), options: .atomic)
    }

    private func loadDailyFile(_ url: URL) -> [MetricsSnapshot] {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(PersistedHistoryFile.self, from: data).entries
        } catch {
            print("Failed to load history file \(url.lastPathComponent): \(error.localizedDescription)")
            return []
        }
    }

    private func loadLegacy() -> LegacyPersistedHistory? {
        guard fm.fileExists(atPath: legacyFileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: legacyFileURL)
            return try decoder.decode(LegacyPersistedHistory.self, from: data)
        } catch {
            print("Failed to load legacy history: \(error.localizedDescription)")
            return nil
        }
    }

    private func dailyFileURLs() -> [URL] {
        guard let urls = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls
            .filter { $0.lastPathComponent.hasPrefix("history-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func fileURL(for day: Date) -> URL {
        directoryURL.appendingPathComponent("history-\(dayString(for: day)).json")
    }

    private func dayString(for day: Date) -> String {
        fileNameDateFormatter.string(from: day)
    }

    private func pruneExpiredFiles(reference: Date) throws {
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: reference)) else {
            return
        }

        for url in dailyFileURLs() {
            guard let day = dayFromFileName(url.lastPathComponent), day < cutoff else { continue }
            try fm.removeItem(at: url)
        }
    }

    private func dayFromFileName(_ fileName: String) -> Date? {
        let prefix = "history-"
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(".json") else { return nil }
        let start = fileName.index(fileName.startIndex, offsetBy: prefix.count)
        let end = fileName.index(fileName.endIndex, offsetBy: -5)
        let dayString = String(fileName[start..<end])
        return fileNameDateFormatter.date(from: dayString)
    }

    private func removeLegacyIfNeeded() throws {
        guard fm.fileExists(atPath: legacyFileURL.path) else { return }
        try fm.removeItem(at: legacyFileURL)
    }

    private func removeAllHistoryFiles() throws {
        for url in dailyFileURLs() {
            try fm.removeItem(at: url)
        }
        if fm.fileExists(atPath: legacyFileURL.path) {
            try fm.removeItem(at: legacyFileURL)
        }
    }

    private func csvString(for entries: [MetricsSnapshot]) -> String {
        var lines = [
            "sampledAt,cpuUsagePercent,memoryUsedBytes,memoryTotalBytes,uploadBytesPerSecond,downloadBytesPerSecond,diskReadBytesPerSecond,diskWriteBytesPerSecond,fps"
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for entry in entries {
            lines.append([
                formatter.string(from: entry.sampledAt),
                String(format: "%.2f", entry.cpuUsagePercent),
                String(entry.memoryUsedBytes),
                String(entry.memoryTotalBytes),
                String(format: "%.2f", entry.uploadBytesPerSecond),
                String(format: "%.2f", entry.downloadBytesPerSecond),
                String(format: "%.2f", entry.diskReadBytesPerSecond),
                String(format: "%.2f", entry.diskWriteBytesPerSecond),
                String(format: "%.2f", entry.fps)
            ].joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
