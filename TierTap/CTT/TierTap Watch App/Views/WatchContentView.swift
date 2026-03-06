import SwiftUI

/// Watch app is strictly a remote control for the live session on iPhone.
struct WatchContentView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        Group {
            if store.liveSession != nil {
                WatchLiveView()
            } else {
                WatchStartView()
            }
        }
    }
}
