import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showCheckIn = false
    @State private var showLive = false
    @State private var showAddPast = false
    @State private var showHistory = false
    @State private var showRiskOfRuin = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 24) {
                    HStack {
                        Spacer()
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3).foregroundColor(.gray)
                        }
                        .padding(.trailing, 20).padding(.top, 8)
                    }
                    VStack(spacing: 8) {
                        Image(systemName: "suit.club.fill")
                            .font(.system(size: 52)).foregroundColor(.green)
                        Text("TierTap")
                            .font(.title.bold()).foregroundColor(.white)
                        Text("Table Games Edition")
                            .font(.caption).foregroundColor(.gray)
                    }
                    .padding(.top, 8)

                    if let live = store.liveSession {
                        LiveNowCard(session: live)
                            .onTapGesture { showLive = true }
                            .padding(.horizontal)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        if store.liveSession != nil {
                            Button { showLive = true } label: {
                                Label("Resume Live Session", systemImage: "play.circle.fill")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.green).foregroundColor(.black)
                                    .cornerRadius(14).font(.headline)
                            }
                        } else {
                            Button { showCheckIn = true } label: {
                                Label("Check In", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.green).foregroundColor(.black)
                                    .cornerRadius(14).font(.headline)
                            }
                        }
                        HStack(spacing: 12) {
                            Button { showAddPast = true } label: {
                                Label("Add Past Session", systemImage: "clock.arrow.circlepath")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(.white).cornerRadius(14).font(.subheadline)
                            }
                            Button { showHistory = true } label: {
                                Label("History", systemImage: "list.bullet.rectangle")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(.white).cornerRadius(14).font(.subheadline)
                            }
                        }
                        Button { showRiskOfRuin = true } label: {
                            Label("Risk of Ruin", systemImage: "chart.bar.doc.horizontal")
                                .frame(maxWidth: .infinity).padding()
                                .background(Color(.systemGray6).opacity(0.25))
                                .foregroundColor(.white).cornerRadius(14).font(.subheadline)
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 44)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showCheckIn) { CheckInView().environmentObject(store).environmentObject(settingsStore) }
        .sheet(isPresented: $showLive) { LiveSessionView().environmentObject(store).environmentObject(settingsStore) }
        .sheet(isPresented: $showAddPast) { AddPastSessionView().environmentObject(store).environmentObject(settingsStore) }
        .sheet(isPresented: $showHistory) { HistoryView().environmentObject(store) }
        .sheet(isPresented: $showRiskOfRuin) { RiskOfRuinView().environmentObject(store).environmentObject(settingsStore) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store).environmentObject(settingsStore) }
    }
}

struct LiveNowCard: View {
    let session: Session
    @State private var elapsed: TimeInterval = 0
    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("LIVE NOW").font(.caption.bold()).foregroundColor(.red)
                Spacer()
                Text(Session.durationString(elapsed))
                    .font(.system(.caption, design: .monospaced)).foregroundColor(.green)
            }
            Text(session.casino).font(.headline).foregroundColor(.white)
            Text(session.game).font(.subheadline).foregroundColor(.gray)
            Text("Buy-in: $\(session.totalBuyIn)").font(.caption).foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.2))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.4), lineWidth: 1))
        .onReceive(ticker) { _ in elapsed = Date().timeIntervalSince(session.startTime) }
        .onAppear { elapsed = Date().timeIntervalSince(session.startTime) }
    }
}
