import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var bankrollText: String = ""
    @State private var unitSizeText: String = ""
    @State private var targetAverageText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        bankrollSection
                        riskOfRuinSection
                        socialLoginsSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.green)
                }
            }
            .onAppear {
                bankrollText = settingsStore.bankroll > 0 ? "\(settingsStore.bankroll)" : ""
                unitSizeText = settingsStore.unitSize > 0 ? "\(settingsStore.unitSize)" : ""
                if let t = settingsStore.targetAveragePerSession {
                    targetAverageText = String(format: "%.0f", t)
                } else {
                    targetAverageText = ""
                }
            }
        }
    }

    private var bankrollSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bankroll & Units", systemImage: "dollarsign.circle.fill")
                .font(.headline).foregroundColor(.white)
            VStack(spacing: 10) {
                InputRow(label: "Bankroll ($)", placeholder: "Total bankroll", value: $bankrollText)
                    .onChange(of: bankrollText) { new in
                        if let v = Int(new.filter { $0.isNumber }) { settingsStore.bankroll = v }
                    }
                InputRow(label: "Unit size ($)", placeholder: "Max bet per unit (recommended 1–2% of bankroll)", value: $unitSizeText)
                    .onChange(of: unitSizeText) { new in
                        if let v = Int(new.filter { $0.isNumber }) { settingsStore.unitSize = v }
                    }
            }
            Text("Risk of Ruin uses bankroll and unit size. Keep bets at or below unit size to stay within target risk.")
                .font(.caption).foregroundColor(.gray)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

    private var riskOfRuinSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Target average", systemImage: "target")
                .font(.headline).foregroundColor(.white)
            InputRow(label: "Target win per session ($)", placeholder: "Optional — e.g. 100", value: $targetAverageText)
                .onChange(of: targetAverageText) { new in
                    let n = new.replacingOccurrences(of: ",", with: ".")
                    if n.isEmpty {
                        settingsStore.targetAveragePerSession = nil
                    } else if let v = Double(n.filter { $0.isNumber || $0 == "." }) {
                        settingsStore.targetAveragePerSession = v
                    }
                }
            Text("Compare your actual average win/loss per session to this target in the Risk of Ruin screen.")
                .font(.caption).foregroundColor(.gray)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }

    private var socialLoginsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Account", systemImage: "person.crop.circle.fill")
                .font(.headline).foregroundColor(.white)
            VStack(spacing: 10) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success:
                        settingsStore.isAppleSignedIn = true
                    case .failure:
                        settingsStore.isAppleSignedIn = false
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)

                Button {
                    settingsStore.isGoogleSignedIn.toggle()
                } label: {
                    HStack {
                        Image(systemName: "globe")
                        Text(settingsStore.isGoogleSignedIn ? "Signed in with Google" : "Continue with Google")
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Color(.systemGray6).opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(true)
                .opacity(0.8)

                if settingsStore.isAppleSignedIn || settingsStore.isGoogleSignedIn {
                    Button("Sign out") {
                        settingsStore.isAppleSignedIn = false
                        settingsStore.isGoogleSignedIn = false
                    }
                    .font(.subheadline).foregroundColor(.red)
                }
            }
            Text("Sign in to sync sessions across devices (Google sign-in coming soon).")
                .font(.caption).foregroundColor(.gray)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}
