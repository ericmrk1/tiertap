import SwiftUI

/// watchOS has no `ColorPicker`; use named swatches matching iPhone theme buckets.
enum WatchThemeColorOption: String, CaseIterable, Identifiable {
    case black, red, orange, yellow, mint, teal, blue, indigo, purple, pink, green

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var color: Color {
        TierTapThemeSettings.color(fromName: rawValue)
    }
}

struct WatchThemeColorPickerSheet: View {
    let title: String
    let selectedName: String
    let onSelect: (Color) -> Void

    @Environment(\.dismiss) private var dismiss

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 44, maximum: 56), spacing: 6)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(WatchThemeColorOption.allCases) { option in
                    Button {
                        onSelect(option.color)
                        dismiss()
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(option.color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if option.rawValue == selectedName {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.bold())
                                            .foregroundStyle(option.rawValue == "yellow" ? .black : .white)
                                    }
                                }
                            Text(option.title)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .localizedNavigationTitle(title)
    }
}
