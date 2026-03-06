import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedSession: Session?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if store.sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 52)).foregroundColor(.gray)
                        Text("No Sessions Yet").font(.title3).foregroundColor(.gray)
                        Text("Complete a session to see your history.")
                            .font(.subheadline).foregroundColor(.gray.opacity(0.7))
                    }
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            SessionRow(session: session)
                                .onTapGesture { selectedSession = session }
                                .listRowBackground(Color(.systemGray6).opacity(0.15))
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                        .onDelete(perform: store.deleteSession)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Session History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.green)
                }
            }
            .sheet(item: $selectedSession) { SessionDetailView(session: $0) }
        }
    }
}

struct SessionRow: View {
    let session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.casino).font(.headline).foregroundColor(.white)
                Spacer()
                if let e = session.tierPointsEarned {
                    Text("\(e >= 0 ? "+" : "")\(e) pts")
                        .font(.subheadline.bold())
                        .foregroundColor(e >= 0 ? .green : .orange)
                }
            }
            HStack {
                Text(session.game).font(.subheadline).foregroundColor(.gray)
                Spacer()
                Text(session.startTime, style: .date).font(.caption).foregroundColor(.gray)
            }
            HStack {
                Text(Session.durationString(session.duration))
                    .font(.caption).foregroundColor(.gray)
                Spacer()
                if let t = session.tiersPerHour {
                    Text(String(format: "%.1f pts/hr", t))
                        .font(.caption).foregroundColor(.gray)
                }
                if let wl = session.winLoss {
                    Text(wl >= 0 ? "+$\(wl)" : "-$\(abs(wl))")
                        .font(.caption.bold())
                        .foregroundColor(wl >= 0 ? .green : .red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
