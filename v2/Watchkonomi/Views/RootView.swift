import SwiftUI

struct RootView: View {
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ChannelListView()
                .navigationTitle("Watchkonomi")
                .toolbar {
                    ToolbarItem {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView()
                            .navigationTitle("設定")
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}
