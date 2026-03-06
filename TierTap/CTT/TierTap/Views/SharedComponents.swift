import SwiftUI

struct DarkTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color(.systemGray6).opacity(0.25))
            .foregroundColor(.white)
            .cornerRadius(10)
            .tint(.green)
    }
}

struct GameButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10).padding(.horizontal, 4)
                .background(isSelected ? Color.green : Color(.systemGray6).opacity(0.25))
                .foregroundColor(isSelected ? .black : .white)
                .cornerRadius(10)
        }
    }
}

struct InputRow: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.bold()).foregroundColor(.white)
            TextField(placeholder, text: $value)
                .textFieldStyle(DarkTextFieldStyle())
                .keyboardType(.numberPad)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(12)
    }
}

struct SummaryRow: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.gray)
            Spacer()
            Text(value).font(.subheadline.bold()).foregroundColor(color)
        }
    }
}

struct StatMini: View {
    let title: String; let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundColor(.gray)
            Text(value).font(.title3.bold()).foregroundColor(.white)
        }
        .frame(maxWidth: .infinity).padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(12)
    }
}

struct DetailSection<Content: View>: View {
    let title: String; let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline).foregroundColor(.white)
            Divider().background(Color.gray.opacity(0.3))
            content
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

struct DetailRow: View {
    let label: String; let value: String
    var valueColor: Color = .white; var bold: Bool = false
    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.gray)
            Spacer()
            Text(value).font(bold ? .subheadline.bold() : .subheadline).foregroundColor(valueColor)
        }
    }
}

struct GamePickerView: View {
    @Binding var selectedGame: String
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    var filtered: [String] {
        search.isEmpty ? GamesList.all : GamesList.all.filter { $0.lowercased().contains(search.lowercased()) }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List {
                    ForEach(filtered, id: \.self) { game in
                        Button {
                            selectedGame = game; dismiss()
                        } label: {
                            HStack {
                                Text(game).foregroundColor(.white)
                                Spacer()
                                if selectedGame == game { Image(systemName: "checkmark").foregroundColor(.green) }
                            }
                        }
                        .listRowBackground(Color(.systemGray6).opacity(0.15))
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
            .searchable(text: $search, prompt: "Search games")
            .navigationTitle("Select Game").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.green)
                }
            }
        }
    }
}
