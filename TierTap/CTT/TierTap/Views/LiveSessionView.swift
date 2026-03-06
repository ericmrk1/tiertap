import SwiftUI

struct LiveSessionView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) var dismiss
    @State private var elapsed: TimeInterval = 0
    @State private var showAddBuyIn = false
    @State private var customBuyIn = ""
    @State private var showCloseout = false

    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let quickBuyIns = [100, 200, 300, 500]

    var s: Session { store.liveSession ?? Session(game: "", casino: "", startTime: Date(), startingTierPoints: 0) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Timer Hero
                    VStack(spacing: 6) {
                        HStack {
                            HStack(spacing: 5) {
                                Circle().fill(Color.red).frame(width: 7, height: 7)
                                Text("LIVE").font(.caption.bold()).foregroundColor(.red)
                            }
                            Spacer()
                            Text("Started \(s.startTime, style: .time)")
                                .font(.caption).foregroundColor(.gray)
                        }
                        Text(s.casino).font(.title2.bold()).foregroundColor(.white)
                        Text(s.game).font(.subheadline).foregroundColor(.gray)
                        Text(Session.durationString(elapsed))
                            .font(.system(size: 60, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.vertical, 4)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6).opacity(0.12))

                    ScrollView {
                        VStack(spacing: 16) {
                            // Buy-In Panel
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Buy-Ins").font(.headline).foregroundColor(.white)
                                    Spacer()
                                    Text("Total: $\(s.totalBuyIn)")
                                        .font(.title3.bold()).foregroundColor(.white)
                                }
                                ForEach(s.buyInEvents) { ev in
                                    HStack {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .foregroundColor(.green).font(.caption)
                                        Text("$\(ev.amount)").foregroundColor(.white)
                                        Spacer()
                                        Text(ev.timestamp, style: .time)
                                            .font(.caption).foregroundColor(.gray)
                                    }
                                }
                                if showAddBuyIn {
                                    VStack(spacing: 8) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(quickBuyIns, id: \.self) { amt in
                                                    Button("$\(amt)") {
                                                        store.addBuyIn(amt); showAddBuyIn = false
                                                    }
                                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                                    .background(Color.green.opacity(0.2))
                                                    .foregroundColor(.green).cornerRadius(8).font(.subheadline)
                                                }
                                            }
                                        }
                                        HStack {
                                            TextField("Custom amount", text: $customBuyIn)
                                                .textFieldStyle(DarkTextFieldStyle())
                                                .keyboardType(.numberPad)
                                            Button("Add") {
                                                if let a = Int(customBuyIn), a > 0 {
                                                    store.addBuyIn(a); customBuyIn = ""; showAddBuyIn = false
                                                }
                                            }
                                            .padding(.horizontal, 16).padding(.vertical, 12)
                                            .background(Color.green).foregroundColor(.black).cornerRadius(10)
                                            .disabled((Int(customBuyIn) ?? 0) <= 0)
                                        }
                                    }
                                } else {
                                    Button { withAnimation { showAddBuyIn = true } } label: {
                                        Label("Add Buy-In", systemImage: "plus.circle")
                                            .frame(maxWidth: .infinity).padding(10)
                                            .background(Color(.systemGray6).opacity(0.25))
                                            .foregroundColor(.green).cornerRadius(10)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.15))
                            .cornerRadius(16)

                            HStack(spacing: 12) {
                                StatMini(title: "Hours", value: String(format: "%.1f", s.hoursPlayed))
                                StatMini(title: "Start Pts", value: "\(s.startingTierPoints)")
                            }

                            Button { showCloseout = true } label: {
                                Label("Stop & Close Out", systemImage: "stop.circle.fill")
                                    .frame(maxWidth: .infinity).padding()
                                    .background(Color.red.opacity(0.85))
                                    .foregroundColor(.white).cornerRadius(14).font(.headline)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Live Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }.foregroundColor(.green)
                }
            }
            .onReceive(ticker) { _ in elapsed = Date().timeIntervalSince(s.startTime) }
            .onAppear { elapsed = Date().timeIntervalSince(s.startTime) }
            .sheet(isPresented: $showCloseout) { CloseoutView().environmentObject(store).environmentObject(settingsStore) }
            .onChange(of: store.liveSession) { newVal in if newVal == nil { dismiss() } }
        }
    }
}
