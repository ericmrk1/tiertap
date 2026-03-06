import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var showCheckIn = false
    @State private var showLive = false
    @State private var showBuyInSheet = false
    @State private var showAddPast = false
    @State private var showHistory = false
    @State private var showBankroll = false

    /// Quick-add buy-in denominations for the live buy-in sheet.
    private var quickBuyIns: [Int] {
        [50, 100, 200, 500, 1_000, 5_000, 10_000, 20_000, 50_000, 100_000]
    }

    /// Logo with black pixels made transparent so the gradient shows through.
    private var logoImage: Image {
        if let processed = TransparentLogoCache.image {
            return Image(uiImage: processed)
        }
        return Image("LogoSplash")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settingsStore.primaryGradient.ignoresSafeArea()
                VStack(spacing: 24) {
                    logoImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .padding(.horizontal, 24)
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
                            Button {
                                showBuyInSheet = true
                            } label: {
                                Label("Add Buy-In", systemImage: "plus.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .padding(.horizontal)
                                    .background(Color(.systemGray6).opacity(0.25))
                                    .foregroundColor(.green)
                                    .cornerRadius(16).font(.title3.bold())
                            }
                        } else {
                            Button { showCheckIn = true } label: {
                                Label("Check In", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .padding(.horizontal)
                                    .background(Color.green).foregroundColor(.black)
                                    .cornerRadius(16).font(.title2.bold())
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
                        Button { showBankroll = true } label: {
                            Label("Bankroll", systemImage: "dollarsign.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color(.systemGray6).opacity(0.25))
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .font(.title3.bold())
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 44)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showCheckIn) { CheckInView().environmentObject(store).environmentObject(settingsStore) }
        .sheet(isPresented: $showLive) { LiveSessionView().environmentObject(store).environmentObject(settingsStore) }
        .sheet(isPresented: $showBuyInSheet) {
            BuyInQuickAddSheet(quickBuyIns: quickBuyIns) { amount in
                store.addBuyIn(amount)
            }
        }
        .sheet(isPresented: $showAddPast) { AddPastSessionView().environmentObject(store).environmentObject(settingsStore) }
        .sheet(isPresented: $showHistory) { HistoryView().environmentObject(store).environmentObject(settingsStore) }
        .sheet(isPresented: $showBankroll) { BankrollView().environmentObject(store).environmentObject(settingsStore) }
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
