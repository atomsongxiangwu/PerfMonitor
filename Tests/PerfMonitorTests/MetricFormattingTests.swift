import XCTest
@testable import PerfMonitor

final class MetricFormattingTests: XCTestCase {
    func testDiskUsagePercentUsesUsedOverTotal() {
        XCTAssertEqual(MetricFormatting.diskUsagePercent(used: 100, total: 200), 50.0)
        XCTAssertEqual(MetricFormatting.diskUsagePercent(used: 0, total: 0), 0.0)
    }
}
