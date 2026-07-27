import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: MetricsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            Divider().opacity(0.25)
            rows
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .frame(minWidth: 230, maxWidth: 280)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "speedometer")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("PerfMonitor")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                viewModel.overlayEnabled = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var rows: some View {
        if viewModel.showCPU {
            overlayRow(
                icon: "cpu",
                label: "CPU",
                value: String(format: "%.1f%%", viewModel.snapshot.cpuUsagePercent),
                isAlerting: viewModel.isCPUAlerting(for: viewModel.snapshot)
            )
        }
        if viewModel.showMemory {
            let pct = viewModel.snapshot.memoryTotalBytes > 0
                ? Double(viewModel.snapshot.memoryUsedBytes) / Double(viewModel.snapshot.memoryTotalBytes) * 100
                : 0.0
            overlayRow(
                icon: "memorychip",
                label: "MEM",
                value: String(format: "%.1f%%", pct),
                isAlerting: viewModel.isMemoryAlerting(for: viewModel.snapshot)
            )
        }
        if viewModel.showNetwork {
            overlayRow(
                icon: "arrow.down.circle",
                label: "DOWN",
                value: "\(MetricFormatting.speed(viewModel.snapshot.downloadBytesPerSecond))/s",
                isAlerting: viewModel.isDownloadAlerting(for: viewModel.snapshot)
            )
            overlayRow(
                icon: "arrow.up.circle",
                label: "UP",
                value: "\(MetricFormatting.speed(viewModel.snapshot.uploadBytesPerSecond))/s",
                isAlerting: viewModel.isUploadAlerting(for: viewModel.snapshot)
            )
        }
        if viewModel.showDisk {
            overlayRow(
                icon: "externaldrive",
                label: "DR",
                value: "\(MetricFormatting.speed(viewModel.snapshot.diskReadBytesPerSecond))/s",
                isAlerting: false
            )
            overlayRow(
                icon: "externaldrive.fill.badge.plus",
                label: "DW",
                value: "\(MetricFormatting.speed(viewModel.snapshot.diskWriteBytesPerSecond))/s",
                isAlerting: false
            )
        }
        if viewModel.showFPS {
            overlayRow(
                icon: "display",
                label: "FPS",
                value: MetricFormatting.fps(viewModel.snapshot.fps),
                isAlerting: false
            )
        }
    }

    private func overlayRow(icon: String, label: String, value: String, isAlerting: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isAlerting ? .red : Color.accentColor)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(isAlerting ? .red : .primary)
        }
    }
}
