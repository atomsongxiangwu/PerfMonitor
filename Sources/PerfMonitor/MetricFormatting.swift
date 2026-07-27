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

    private static func byteFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }
}
