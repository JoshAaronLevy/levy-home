import SwiftUI

struct LogsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        LogsContentView(logStore: appEnvironment.appLogStore)
    }
}

private struct LogsContentView: View {
    @ObservedObject var logStore: AppLogStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                InfoPanel(
                    title: "Runtime Logs",
                    subtitle: headerSubtitle,
                    systemImage: "terminal"
                ) {
                    HStack(spacing: AppSpacing.medium) {
                        StatusBadgeView(
                            label: logStore.entries.isEmpty ? "Waiting" : "\(logStore.entries.count) entries",
                            systemImage: logStore.entries.isEmpty ? "clock" : "list.bullet",
                            tone: logStore.entries.isEmpty ? .neutral : .accent
                        )

                        Spacer()

                        Button {
                            Task { @MainActor in
                                logStore.clear()
                            }
                        } label: {
                            Label("Clear", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .disabled(logStore.entries.isEmpty)
                    }
                }

                if logStore.entries.isEmpty {
                    emptyState
                } else {
                    ForEach(logStore.entries) { entry in
                        LogEntryCard(entry: entry)
                    }
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Logs")
    }

    private var headerSubtitle: String {
        "Local app, API, and action breadcrumbs from this device."
    }

    private var emptyState: some View {
        InfoPanel(
            title: "No Logs Yet",
            subtitle: "Trigger a home action or refresh a screen to start collecting local logs.",
            systemImage: "doc.text.magnifyingglass"
        ) {
            Text("Logs stay on this device and avoid raw payloads, tokens, and secrets.")
                .font(.body)
                .foregroundStyle(AppColors.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LogEntryCard: View {
    let entry: AppLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                Image(systemName: entry.level.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(entry.level.tone.foregroundColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    HStack(spacing: AppSpacing.small) {
                        StatusBadgeView(
                            label: entry.category,
                            systemImage: nil,
                            tone: entry.level.tone
                        )

                        Text(entry.timestamp.logTimestamp)
                            .font(.caption)
                            .foregroundStyle(AppColors.mutedText)
                            .lineLimit(1)
                    }

                    Text(entry.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = entry.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.mutedText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private extension AppLogLevel {
    var tone: StatusBadgeTone {
        switch self {
        case .info:
            return .accent
        case .success:
            return .success
        case .warning:
            return .warning
        case .error:
            return .critical
        }
    }

    var systemImage: String {
        switch self {
        case .info:
            return "arrow.right.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }
}

private extension Date {
    var logTimestamp: String {
        Self.logFormatter.string(from: self)
    }

    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

#Preview {
    NavigationStack {
        LogsContentView(logStore: previewLogStore)
    }
}

private var previewLogStore: AppLogStore {
    let store = AppLogStore(userDefaults: UserDefaults(suiteName: "LogsPreview") ?? .standard)
    store.record(
        level: .info,
        category: "Action",
        title: "Open Garage requested",
        detail: "Submitting open_garage to the Levy Home API."
    )
    store.record(
        level: .error,
        category: "API",
        title: "HTTP 400 for POST /api/home/actions",
        detail: "Unsupported quick action."
    )
    return store
}
