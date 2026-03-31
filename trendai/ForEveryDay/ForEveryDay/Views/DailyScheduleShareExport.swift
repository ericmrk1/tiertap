import SwiftUI
import UIKit

enum ScheduleShareOrientation: String, CaseIterable {
    case vertical
    case horizontal

    var menuTitle: String {
        switch self {
        case .vertical: return "Portrait (vertical)"
        case .horizontal: return "Landscape (horizontal)"
        }
    }
}

struct DailyScheduleSharePayload {
    struct ScheduledRow: Hashable {
        let taskId: UUID
        let time: String
        let title: String
    }

    struct UnscheduledRow: Hashable {
        let taskId: UUID
        let title: String
    }

    struct IntentionRow: Hashable {
        let id: UUID
        let title: String
    }

    let date: Date
    let dayStart: TimeOfDay
    let dayEnd: TimeOfDay
    let completedTaskIds: Set<UUID>
    let scheduledRows: [ScheduledRow]
    let unscheduledRows: [UnscheduledRow]
    let intentionRows: [IntentionRow]
}

// MARK: - Share card (static layout for image export)

private struct DailyScheduleShareCard: View {
    let payload: DailyScheduleSharePayload
    let orientation: ScheduleShareOrientation

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        Group {
            switch orientation {
            case .vertical:
                verticalLayout
            case .horizontal:
                horizontalLayout
            }
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            scheduleSection
            unscheduledSection
            intentionsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                header
                scheduleSection
                unscheduledSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                intentionsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("For Every Day")
                .font(.title.bold())
                .foregroundStyle(.primary)
            Text(Self.dateFormatter.string(from: payload.date))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Day \(payload.dayStart.displayString) – \(payload.dayEnd.displayString)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        if !payload.scheduledRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Scheduled", systemImage: "clock")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(payload.scheduledRows, id: \.taskId) { row in
                        shareTaskLine(
                            isDone: payload.completedTaskIds.contains(row.taskId),
                            primary: row.time,
                            secondary: nil,
                            title: row.title
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var unscheduledSection: some View {
        if !payload.unscheduledRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Unscheduled", systemImage: "tray")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(payload.unscheduledRows, id: \.taskId) { row in
                        shareTaskLine(
                            isDone: payload.completedTaskIds.contains(row.taskId),
                            primary: nil,
                            secondary: nil,
                            title: row.title
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var intentionsSection: some View {
        if !payload.intentionRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Daily intentions", systemImage: "leaf")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(payload.intentionRows, id: \.id) { row in
                        shareTaskLine(
                            isDone: payload.completedTaskIds.contains(row.id),
                            primary: nil,
                            secondary: nil,
                            title: row.title
                        )
                    }
                }
            }
        }
    }

    private func shareTaskLine(isDone: Bool, primary: String?, secondary: String?, title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(isDone ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let primary {
                    Text(primary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let secondary {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Rendering + share UI

enum DailyScheduleShare {
    /// Renders the schedule snapshot to a bitmap before any share UI is shown.
    @MainActor
    static func renderImage(payload: DailyScheduleSharePayload, orientation: ScheduleShareOrientation) -> UIImage? {
        let content = DailyScheduleShareCard(payload: payload, orientation: orientation)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(.systemBackground))

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        switch orientation {
        case .vertical:
            renderer.proposedSize = ProposedViewSize(width: 390, height: nil)
        case .horizontal:
            renderer.proposedSize = ProposedViewSize(width: 780, height: nil)
        }
        return renderer.uiImage
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
