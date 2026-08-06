import AppKit
import SwiftUI

struct DiskCleanupDetailView: View {
    @ObservedObject var viewModel: MetricsViewModel
    let onDone: () -> Void

    @State private var pendingCleanupAction: PendingCleanupAction?
    @State private var expandedCategories = Set(DiskCleanupCategory.allCases)

    init(viewModel: MetricsViewModel, onDone: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 620, minHeight: 520)
        .onAppear {
            if viewModel.diskCleanupItems.isEmpty {
                viewModel.refreshDiskCleanupItems()
            }
        }
        .confirmationDialog(
            "Clean up files?",
            isPresented: Binding(
                get: { pendingCleanupAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingCleanupAction = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingCleanupAction {
                Button(action.confirmTitle, role: .destructive) {
                    performCleanup(action)
                    pendingCleanupAction = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCleanupAction = nil
            }
        } message: {
            if let action = pendingCleanupAction {
                Text(action.message)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Cleanup")
                    .font(.headline)
                Text("Preview large reclaimable items, then clean selected entries or a whole category")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.refreshDiskCleanupItems()
            } label: {
                if viewModel.diskCleanupIsScanning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.diskCleanupIsScanning)

            Button("Done") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(16)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow

            if let message = viewModel.diskCleanupMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if let error = viewModel.diskCleanupError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.diskCleanupItems.isEmpty, !viewModel.diskCleanupIsScanning {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(viewModel.diskCleanupItems) { item in
                            cleanupRow(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Text("Only user-level files are cleaned. System files are never modified.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var summaryRow: some View {
        HStack {
            Label("Reclaimable", systemImage: "externaldrive.badge.minus")
                .font(.subheadline)
            Spacer()
            Text(MetricFormatting.bytes(totalReclaimableBytes))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.primary)
            if let scannedAt = viewModel.diskCleanupLastScannedAt {
                Text("• \(scannedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("No cleanup targets found")
                .font(.subheadline)
            Text("Run a scan to preview reclaimable caches, logs, and build artifacts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
    }

    private func cleanupRow(_ item: DiskCleanupItem) -> some View {
        let isCleaning = viewModel.isCleaningDiskCategory(item.category)
        let selectedCandidates = viewModel.selectedDiskCleanupCandidates(for: item)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.category.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.category.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(MetricFormatting.bytes(item.sizeBytes))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Text(item.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                metaBadge("\(item.fileCount) files")
                if let modifiedAt = item.lastModifiedAt {
                    metaBadge(modifiedAt.formatted(date: .abbreviated, time: .shortened))
                }
                finderButton(forPath: item.path)
            }

            if !item.topCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button {
                            togglePreview(for: item.category)
                        } label: {
                            Label(
                                isPreviewExpanded(for: item.category) ? "Hide Preview" : "Preview",
                                systemImage: isPreviewExpanded(for: item.category)
                                    ? "chevron.down"
                                    : "chevron.right"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if isPreviewExpanded(for: item.category) {
                            Button("Select All") {
                                viewModel.setDiskCleanupSelection(true, candidates: item.topCandidates)
                            }
                            .buttonStyle(.plain)
                            .font(.caption2)

                            Button("Clear") {
                                viewModel.setDiskCleanupSelection(false, candidates: item.topCandidates)
                            }
                            .buttonStyle(.plain)
                            .font(.caption2)
                        }
                    }

                    if isPreviewExpanded(for: item.category) {
                        ForEach(item.topCandidates) { candidate in
                            candidateRow(candidate)
                        }
                    }
                }
            }

            HStack {
                if !selectedCandidates.isEmpty {
                    Text("Selected: \(selectedCandidates.count) item(s) • \(MetricFormatting.bytes(selectedCandidates.reduce(0) { $0 + $1.sizeBytes }))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clean Selected") {
                    pendingCleanupAction = .selected(item: item, candidates: selectedCandidates)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCleaning || selectedCandidates.isEmpty)

                Button("Clean All") {
                    pendingCleanupAction = .category(item)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isCleaning || item.sizeBytes == 0)
            }
        }
        .padding(12)
        .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func candidateRow(_ candidate: DiskCleanupCandidate) -> some View {
        let isSelected = viewModel.isDiskCleanupCandidateSelected(candidate)

        return HStack(spacing: 10) {
            Button {
                viewModel.toggleDiskCleanupCandidate(candidate)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(candidate.path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(MetricFormatting.bytes(candidate.sizeBytes))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                HStack(spacing: 6) {
                    Text(candidate.isDirectory ? "\(candidate.fileCount) files" : "File")
                    if let modifiedAt = candidate.lastModifiedAt {
                        Text(modifiedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            finderButton(forPath: candidate.path)
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func finderButton(forPath path: String) -> some View {
        Button("Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        .buttonStyle(.borderless)
        .font(.caption2)
    }

    private func metaBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.gray.opacity(0.12), in: Capsule())
    }

    private func performCleanup(_ action: PendingCleanupAction) {
        switch action {
        case .category(let item):
            viewModel.cleanDiskCleanupCategory(item.category)
        case .selected(let item, _):
            viewModel.cleanSelectedDiskCleanupCandidates(in: item)
        }
    }

    private func isPreviewExpanded(for category: DiskCleanupCategory) -> Bool {
        expandedCategories.contains(category)
    }

    private func togglePreview(for category: DiskCleanupCategory) {
        if expandedCategories.contains(category) {
            expandedCategories.remove(category)
        } else {
            expandedCategories.insert(category)
        }
    }

    private var totalReclaimableBytes: UInt64 {
        viewModel.diskCleanupItems.reduce(0) { $0 + $1.sizeBytes }
    }
}

private enum PendingCleanupAction {
    case category(DiskCleanupItem)
    case selected(item: DiskCleanupItem, candidates: [DiskCleanupCandidate])

    var confirmTitle: String {
        switch self {
        case .category(let item):
            return "Clean \(item.category.title)"
        case .selected(_, let candidates):
            return "Clean \(candidates.count) Selected Item(s)"
        }
    }

    var message: String {
        switch self {
        case .category(let item):
            return "This will remove all files inside \(item.category.title)."
        case .selected(_, let candidates):
            let totalBytes = candidates.reduce(0) { $0 + $1.sizeBytes }
            return "This will remove \(candidates.count) selected item(s), about \(MetricFormatting.bytes(totalBytes))."
        }
    }
}
