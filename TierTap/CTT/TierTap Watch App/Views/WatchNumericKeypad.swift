import SwiftUI

#if os(watchOS)
/// watchOS SwiftUI does not support `keyboardType(.numberPad)`. Use an on-screen digit pad for numeric entry.
struct WatchNumericDigitPad: View {
    @Binding var text: String
    /// When true, includes a space key for values like `20 100 200 500`.
    var allowSpace: Bool = false
    var maxLength: Int = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayLine)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)

            VStack(spacing: 6) {
                row(["1", "2", "3"])
                row(["4", "5", "6"])
                row(["7", "8", "9"])
                HStack(spacing: 6) {
                    padButton("⌫", accessibilityLabel: "Delete") { deleteLast() }
                    padButton("0") { appendDigit("0") }
                    if allowSpace {
                        padButton("␣", accessibilityLabel: "Space") { appendSpace() }
                    } else {
                        Spacer(minLength: 0)
                            .frame(maxWidth: .infinity)
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
        HStack(spacing: 6) {
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

    private func padButton(_ title: String, accessibilityLabel: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}
#endif
