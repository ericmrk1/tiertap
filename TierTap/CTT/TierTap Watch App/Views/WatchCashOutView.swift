import SwiftUI

struct WatchCashOutView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss
    @State private var cashOutAmount = ""
    @State private var selectedPreset: Int? = nil

    let presets = [100, 200, 300, 500, 1000, 0]

    var s: Session { store.liveSession ?? Session(game: "", casino: "", startTime: Date(), startingTierPoints: 0) }

    var cashOutValue: Int? {
        if let p = selectedPreset, p > 0 { return p }
        return Int(cashOutAmount)
    }

    var canSave: Bool {
        guard let v = cashOutValue else { return false }
        return v >= 0
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Cash out")
                .font(.headline)
            Text("Total in: $\(s.totalBuyIn)")
                .font(.caption)

            TextField("Amount", text: $cashOutAmount)
                .onChange(of: cashOutAmount) { _ in selectedPreset = nil }

            Text("Quick").font(.caption2)
            HStack(spacing: 6) {
                ForEach(presets.filter { $0 > 0 }, id: \.self) { amt in
                    Button("$\(amt)") {
                        cashOutAmount = "\(amt)"
                        selectedPreset = amt
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedPreset == amt ? .green : .gray)
                }
            }

            Button {
                saveAndDismiss()
            } label: {
                Text("Save (complete on iPhone)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!canSave)

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    private func saveAndDismiss() {
        guard let amount = cashOutValue, amount >= 0 else { return }
        store.closeSessionCashOutOnly(cashOut: amount)
        dismiss()
    }
}
