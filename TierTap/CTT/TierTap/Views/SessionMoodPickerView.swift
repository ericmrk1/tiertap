import SwiftUI

/// Post-session popup: full-screen grid of mood cells. Happy states in the center, worse moods toward the edges.
/// Each cell maps to one of the stored SessionMood values.
struct SessionMoodPickerView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    let onSelect: (SessionMood) -> Void

    private let gridSize = 5
    private var centerIndex: Int { gridSize / 2 }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    Text("🧠 How did the session feel?")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.vertical, 12)

                    GeometryReader { geo in
                        let side = min(geo.size.width, geo.size.height) / CGFloat(gridSize)
                        let cols = (0..<gridSize).map { _ in GridItem(.fixed(side), spacing: 4) }
                        LazyVGrid(columns: cols, spacing: 4) {
                            ForEach(0..<(gridSize * gridSize), id: \.self) { index in
                                let row = index / gridSize
                                let col = index % gridSize
                                let mood = moodAt(row: row, col: col)
                                Button {
                                    onSelect(mood)
                                    dismiss()
                                } label: {
                                    Text(mood.label)
                                        .font(.caption.bold())
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.6)
                                        .foregroundColor(.white)
                                        .frame(width: side - 4, height: side - 4)
                                        .background(moodGradient(mood))
                                        .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Session mood")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settingsStore.primaryGradient, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    /// Maps grid position to mood: center = best, edges = worst (gradient from happy in middle to worse at edges).
    private func moodAt(row: Int, col: Int) -> SessionMood {
        let dr = abs(row - centerIndex)
        let dc = abs(col - centerIndex)
        let dist = max(dr, dc)

        switch dist {
        case 0:
            return .epic
        case 1:
            return .great
        case 2:
            let isCorner = (row == 0 || row == gridSize - 1) && (col == 0 || col == gridSize - 1)
            if isCorner { return .rough }
            let isCardinal = (row == centerIndex && (col == 0 || col == gridSize - 1))
                || (col == centerIndex && (row == 0 || row == gridSize - 1))
            if isCardinal { return .good }
            let edge = gridSize - 1
            switch (row, col) {
            case (0, 1), (1, 0): return .tilt
            case (0, 3), (3, 0): return .frustrated
            case (1, edge), (edge, 1): return .disappointed
            case (3, edge), (edge, 3): return .meh
            default: return .okay
            }
        default:
            return .rough
        }
    }

    /// Gradient for the cell: green (happy) through neutral to red (bad).
    private func moodGradient(_ mood: SessionMood) -> LinearGradient {
        let (start, end): (Color, Color) = {
            switch mood {
            case .epic, .great:
                return (Color.green.opacity(0.6), Color.green.opacity(0.35))
            case .good:
                return (Color.green.opacity(0.4), Color.mint.opacity(0.3))
            case .okay:
                return (Color(.systemGray4).opacity(0.4), Color(.systemGray5).opacity(0.25))
            case .meh:
                return (Color.orange.opacity(0.3), Color.orange.opacity(0.2))
            case .disappointed:
                return (Color.orange.opacity(0.45), Color.orange.opacity(0.3))
            case .frustrated:
                return (Color.orange.opacity(0.5), Color.red.opacity(0.3))
            case .tilt:
                return (Color.red.opacity(0.45), Color.red.opacity(0.35))
            case .rough:
                return (Color.red.opacity(0.55), Color.red.opacity(0.4))
            }
        }()
        return LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

#Preview {
    SessionMoodPickerView { _ in }
        .environmentObject(SettingsStore())
}
