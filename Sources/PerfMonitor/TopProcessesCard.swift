import SwiftUI

/// Always-visible Top-N process ranking for the Monitor panel.
struct TopProcessesCard: View {
    let processes: [ProcessMetricEntry]
    @Binding var sortKey: ProcessSortKey
    var memoryTotalBytes: UInt64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if processes.isEmpty {
                emptyState
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(processes.enumerated()), id: \.element.id) { index, entry in
                        ProcessRankRow(
                            rank: index + 1,
                            entry: entry,
                            sortKey: sortKey,
                            barFraction: barFraction(for: entry),
                            isLast: index == processes.count - 1
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(.gray.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Top Processes")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 4)
            Picker("", selection: $sortKey) {
                ForEach(ProcessSortKey.allCases) { key in
                    Text(key.rawValue).tag(key)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .frame(width: 88)
            .labelsHidden()
        }
    }

    private var emptyState: some View {
        Text("Sampling…")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
    }

    private func barFraction(for entry: ProcessMetricEntry) -> Double {
        switch sortKey {
        case .cpu:
            // Absolute scale; values can exceed 100% on multi-core — clamp for the bar.
            return min(max(entry.cpuPercent / 100, 0), 1)
        case .memory:
            let denom: Double
            if memoryTotalBytes > 0 {
                denom = Double(memoryTotalBytes)
            } else {
                denom = Double(processes.map(\.memoryBytes).max() ?? 1)
            }
            guard denom > 0 else { return 0 }
            return min(max(Double(entry.memoryBytes) / denom, 0), 1)
        }
    }
}

// MARK: - Row

private struct ProcessRankRow: View {
    let rank: Int
    let entry: ProcessMetricEntry
    let sortKey: ProcessSortKey
    let barFraction: Double
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text("\(rank)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(rankColor)
                    .frame(width: 16, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(primaryText)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(primaryColor)
                            .layoutPriority(1)

                        Text(secondaryText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .layoutPriority(1)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(barColor.opacity(0.85))
                                .frame(width: max(2, geo.size.width * barFraction))
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(.vertical, 5)

            if !isLast {
                Divider().opacity(0.35)
            }
        }
    }

    private var primaryText: String {
        switch sortKey {
        case .cpu: return String(format: "%.1f%%", entry.cpuPercent)
        case .memory: return MetricFormatting.bytes(entry.memoryBytes)
        }
    }

    private var secondaryText: String {
        switch sortKey {
        case .cpu: return MetricFormatting.bytes(entry.memoryBytes)
        case .memory: return String(format: "%.1f%%", entry.cpuPercent)
        }
    }

    private var primaryColor: Color {
        switch sortKey {
        case .cpu:
            if entry.cpuPercent >= 80 { return .red }
            if entry.cpuPercent >= 40 { return .orange }
            return .primary
        case .memory:
            return .primary
        }
    }

    private var barColor: Color {
        switch sortKey {
        case .cpu:
            if entry.cpuPercent >= 80 { return .red }
            if entry.cpuPercent >= 40 { return .orange }
            return .accentColor
        case .memory:
            return .purple
        }
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .orange
        case 2: return .secondary
        default: return .secondary.opacity(0.55)
        }
    }
}
