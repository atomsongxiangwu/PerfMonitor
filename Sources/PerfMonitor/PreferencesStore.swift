import Foundation

final class PreferencesStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fm = FileManager.default

    init(appName: String = "PerfMonitor") {
        let baseURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        fileURL = baseURL
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("preferences.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> AppSettings? {
        guard fm.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            print("Failed to load preferences: \(error.localizedDescription)")
            return nil
        }
    }

    func decode(_ data: Data) throws -> AppSettings {
        try decoder.decode(AppSettings.self, from: data)
    }

    func exportData(_ settings: AppSettings) throws -> Data {
        try encoder.encode(settings)
    }

    func save(_ settings: AppSettings) {
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try exportData(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save preferences: \(error.localizedDescription)")
        }
    }
}
