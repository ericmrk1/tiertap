import SwiftUI

#if os(watchOS)
/// watchOS SwiftUI does not support `keyboardType(.numberPad)`. Use an on-screen digit pad for numeric entry.
struct WatchNumericDigitPad: View {
    @Binding var text: String
    /// When true, includes a space key for values like `20 100 200 500`.
    var allowSpace: Bool = false
    var maxLength: Int = 12

    private let padSpacing: CGFloat = 4
    private let padMinHeight: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayLine)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)

            VStack(spacing: padSpacing) {
                row(["1", "2", "3"])
                row(["4", "5", "6"])
                row(["7", "8", "9"])
                HStack(spacing: padSpacing) {
                    padButton("⌫", accessibilityLabel: "Delete") { deleteLast() }
                    padButton("0") { appendDigit("0") }
                    clearButton()
                    if allowSpace {
                        padButton("␣", accessibilityLabel: "Space") { appendSpace() }
                    }
                }
            }
        }
    }

    private var displayLine: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "—" : text
    }

    private func row(_ keys: [String]) -> some View {
        HStack(spacing: padSpacing) {
            ForEach(keys, id: \.self) { key in
                padButton(key) { appendDigit(key) }
            }
        }
    }

    private func appendDigit(_ digit: String) {
        guard digit.count == 1, digit.first?.isNumber == true else { return }
        guard text.count < maxLength else { return }
        text.append(digit)
    }

    private func appendSpace() {
        guard allowSpace else { return }
        guard text.count < maxLength else { return }
        guard !text.isEmpty else { return }
        if text.last == " " { return }
        text.append(" ")
    }

    private func deleteLast() {
        guard !text.isEmpty else { return }
        text.removeLast()
    }

    private func clearAll() {
        text = ""
    }

    private func padButton(_ title: String, accessibilityLabel: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: padMinHeight)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(accessibilityLabel ?? title)
    }

    private func clearButton() -> some View {
        Button(action: clearAll) {
            Text("Clear")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, minHeight: padMinHeight)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Clear")
    }
}
#endif
