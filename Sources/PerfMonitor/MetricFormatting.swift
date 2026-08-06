import Foundation

enum MetricFormatting {
    static func bytes(_ bytes: UInt64) -> String {
        byteFormatter().string(fromByteCount: Int64(bytes))
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        byteFormatter().string(fromByteCount: Int64(max(0, bytesPerSecond)))
    }

    static func fps(_ fps: Double) -> String {
        guard fps > 0 else { return "-" }
        return String(format: "%.0f (display)", fps)
    }

    static func diskUsagePercent(used: UInt64, total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total) * 100, 0), 100)
    }

    private static func byteFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }
}
