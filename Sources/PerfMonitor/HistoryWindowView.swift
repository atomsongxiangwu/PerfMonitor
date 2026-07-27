import Charts
import SwiftUI

struct HistoryWindowView: View {
    @ObservedObject var viewModel: MetricsViewModel

    @State private var selectedRange: HistoryTimeRange = .oneHour
    @State private var selectedMetric: HistoryMetric = .cpu
    @State private var hoverSnapshot: MetricsSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            stats
            chart
            if let hoverSnapshot {
                Text("\(hoverSnapshot.sampledAt.formatted(date: .abbreviated, time: .standard)) · \(viewModel.historyValueText(for: selectedMetric, snapshot: hoverSnapshot))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(minWidth: 760, minHeight: 460)
    }

    private var data: [MetricsSnapshot] {
        viewModel.historyData(for: selectedRange)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Range", selection: $selectedRange) {
                ForEach(HistoryTimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            Picker("Metric", selection: $selectedMetric) {
                ForEach(HistoryMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Spacer()
        }
    }

    private var stats: some View {
        let values = data.map { viewModel.historyValue(for: selectedMetric, snapshot: $0) }
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let maxValue = values.max() ?? 0

        return HStack(spacing: 14) {
            statCard(title: "Samples", value: "\(data.count)")
            statCard(title: "Average", value: metricText(avg))
            statCard(title: "Peak", value: metricText(maxValue))
            Spacer()
        }
    }

    private var chart: some View {
        Chart(data, id: \.sampledAt) { item in
            LineMark(
                x: .value("Time", item.sampledAt),
                y: .value("Value", viewModel.historyValue(for: selectedMetric, snapshot: item))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.accentColor)

            if let hoverSnapshot {
                RuleMark(x: .value("Hover", hoverSnapshot.sampledAt))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
                PointMark(
                    x: .value("Hover", hoverSnapshot.sampledAt),
                    y: .value("Hover Value", viewModel.historyValue(for: selectedMetric, snapshot: hoverSnapshot))
                )
                .symbolSize(38)
                .foregroundStyle(Color.accentColor)
            }
        }
        .chartYScale(domain: 0...viewModel.historyChartMaxY(for: selectedMetric, data: data))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let frame = geometry[proxy.plotAreaFrame]
                            guard frame.contains(location) else {
                                hoverSnapshot = nil
                                return
                            }
                            let x = location.x - frame.origin.x
                            if let date: Date = proxy.value(atX: x) {
                                hoverSnapshot = nearestSnapshot(to: date)
                            }
                        case .ended:
                            hoverSnapshot = nil
                        }
                    }
            }
        }
        .frame(height: 320)
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metricText(_ value: Double) -> String {
        switch selectedMetric {
        case .cpu, .memory:
            return String(format: "%.1f%%", value)
        case .download, .upload, .diskRead, .diskWrite:
            return "\(MetricFormatting.speed(value))/s"
        }
    }

    private func nearestSnapshot(to date: Date) -> MetricsSnapshot? {
        guard !data.isEmpty else { return nil }
        return data.min(by: {
            abs($0.sampledAt.timeIntervalSince(date)) < abs($1.sampledAt.timeIntervalSince(date))
        })
    }
}
