import SwiftUI

struct RootView: View {
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Text("Watchkonomi")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
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
    }
}
