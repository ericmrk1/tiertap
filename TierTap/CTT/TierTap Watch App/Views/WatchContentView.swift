import SwiftUI

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
