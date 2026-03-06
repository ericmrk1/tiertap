import SwiftUI

/// Watch app is a remote only. Shown when no session is in progress on iPhone.
struct WatchStartView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        VStack(spacing: 12) {
            Image("TierTapLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)

            Text("TierTap")
                .font(.headline)

            Text("No session in progress")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("Start a session on your iPhone to control it from here")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Remote")
    }
}
