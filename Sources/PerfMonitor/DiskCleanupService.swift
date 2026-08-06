import Foundation

enum DiskCleanupCategory: String, CaseIterable, Identifiable, Hashable {
    case userCaches
    case userLogs
    case xcodeDerivedData
    case trash
    case simulatorCaches

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCaches:
            return "User Caches"
        case .userLogs:
            return "User Logs"
        case .xcodeDerivedData:
            return "Xcode DerivedData"
        case .trash:
            return "Trash"
        case .simulatorCaches:
            return "Simulator Caches"
        }
    }

    var subtitle: String {
        switch self {
        case .userCaches:
            return "App caches under ~/Library/Caches"
        case .userLogs:
            return "Log files under ~/Library/Logs"
        case .xcodeDerivedData:
            return "Build artifacts and indexing cache"
        case .trash:
            return "Files currently in ~/.Trash"
        case .simulatorCaches:
            return "iOS simulator caches in CoreSimulator"
        }
    }

    func directoryURL(in home: URL) -> URL {
        switch self {
        case .userCaches:
            return home.appendingPathComponent("Library/Caches", isDirectory: true)
        case .userLogs:
            return home.appendingPathComponent("Library/Logs", isDirectory: true)
        case .xcodeDerivedData:
            return home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        case .trash:
            return home.appendingPathComponent(".Trash", isDirectory: true)
        case .simulatorCaches:
            return home.appendingPathComponent("Library/Developer/CoreSimulator/Caches", isDirectory: true)
        }
    }
}

struct DiskCleanupItem: Identifiable, Hashable {
    let category: DiskCleanupCategory
    let path: String
    let sizeBytes: UInt64
    let fileCount: Int
    let lastModifiedAt: Date?
    let topCandidates: [DiskCleanupCandidate]

    var id: String { category.id }
}

struct DiskCleanupCandidate: Identifiable, Hashable {
    let category: DiskCleanupCategory
    let path: String
    let displayName: String
    let sizeBytes: UInt64
    let fileCount: Int
    let isDirectory: Bool
    let lastModifiedAt: Date?

    var id: String { "\(category.rawValue):\(path)" }
}

struct DiskCleanupResult {
    let freedBytes: UInt64
    let cleanedPaths: [String]
    let failedPaths: [String]
}

actor DiskCleanupService {
    private let fm = FileManager.default

    func scanItems(maxCandidatesPerCategory: Int = 6) -> [DiskCleanupItem] {
        let home = fm.homeDirectoryForCurrentUser
        var items: [DiskCleanupItem] = []

        for category in DiskCleanupCategory.allCases {
            let directoryURL = category.directoryURL(in: home)
            let path = directoryURL.path
            guard fm.fileExists(atPath: path) else { continue }

            let summary = directorySummary(at: directoryURL)
            let topCandidates = childCandidates(in: directoryURL, category: category)
                .sorted { $0.sizeBytes > $1.sizeBytes }
                .prefix(maxCandidatesPerCategory)
            items.append(
                DiskCleanupItem(
                    category: category,
                    path: path,
                    sizeBytes: summary.sizeBytes,
                    fileCount: summary.fileCount,
                    lastModifiedAt: summary.lastModifiedAt,
                    topCandidates: Array(topCandidates)
                )
            )
        }

        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    func clean(category: DiskCleanupCategory) throws -> DiskCleanupResult {
        let home = fm.homeDirectoryForCurrentUser
        let directoryURL = category.directoryURL(in: home)
        guard fm.fileExists(atPath: directoryURL.path) else {
            return DiskCleanupResult(freedBytes: 0, cleanedPaths: [], failedPaths: [])
        }

        let childURLs = try fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return try clean(urls: childURLs)
    }

    func clean(category: DiskCleanupCategory, candidatePaths: [String]) throws -> DiskCleanupResult {
        guard !candidatePaths.isEmpty else {
            return DiskCleanupResult(freedBytes: 0, cleanedPaths: [], failedPaths: [])
        }

        let urls = candidatePaths.map { URL(fileURLWithPath: $0, isDirectory: false) }
        return try clean(urls: urls)
    }

    private func clean(urls: [URL]) throws -> DiskCleanupResult {
        var freedBytes: UInt64 = 0
        var cleanedPaths: [String] = []
        var failedPaths: [String] = []

        for url in urls {
            guard fm.fileExists(atPath: url.path) else { continue }

            let before = itemSummary(at: url).sizeBytes
            do {
                try fm.removeItem(at: url)
                freedBytes += before
                cleanedPaths.append(url.path)
            } catch {
                failedPaths.append(url.path)
            }
        }

        return DiskCleanupResult(
            freedBytes: freedBytes,
            cleanedPaths: cleanedPaths,
            failedPaths: failedPaths
        )
    }

    private func childCandidates(in directoryURL: URL, category: DiskCleanupCategory) -> [DiskCleanupCandidate] {
        guard let childURLs = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return childURLs.map { childURL in
            let summary = itemSummary(at: childURL)
            return DiskCleanupCandidate(
                category: category,
                path: childURL.path,
                displayName: childURL.lastPathComponent,
                sizeBytes: summary.sizeBytes,
                fileCount: summary.fileCount,
                isDirectory: summary.isDirectory,
                lastModifiedAt: summary.lastModifiedAt
            )
        }
    }

    private func itemSummary(at url: URL) -> (sizeBytes: UInt64, fileCount: Int, isDirectory: Bool, lastModifiedAt: Date?) {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .contentModificationDateKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]

        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            return (0, 0, false, nil)
        }

        if values.isDirectory == true {
            let summary = directorySummary(at: url)
            return (summary.sizeBytes, summary.fileCount, true, summary.lastModifiedAt)
        }

        let fileSize = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
        return (
            UInt64(max(fileSize, 0)),
            values.isRegularFile == true ? 1 : 0,
            false,
            values.contentModificationDate
        )
    }

    private func directorySummary(at root: URL) -> (sizeBytes: UInt64, fileCount: Int, lastModifiedAt: Date?) {
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            return (0, 0, nil)
        }

        var sizeBytes: UInt64 = 0
        var fileCount = 0
        var lastModifiedAt: Date?

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .contentModificationDateKey
            ]) else {
                continue
            }
            guard values.isRegularFile == true else { continue }

            let fileSize = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            sizeBytes += UInt64(max(fileSize, 0))
            fileCount += 1
            if let modifiedAt = values.contentModificationDate,
               lastModifiedAt.map({ modifiedAt > $0 }) ?? true {
                lastModifiedAt = modifiedAt
            }
        }

        return (sizeBytes, fileCount, lastModifiedAt)
    }
}
