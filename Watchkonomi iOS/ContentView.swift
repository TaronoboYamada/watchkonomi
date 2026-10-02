import SwiftUI

struct ContentView: View {
    @StateObject private var manager = BroadcastManager()

    var body: some View {
        NavigationStack {
            Form {
                Section("状態") {
                    LabeledContent("配信") {
                        if manager.isStreaming {
                            Text("配信済み")
                                .foregroundStyle(.green)
                        } else {
                            Text("配信なし")
                        }
                    }
                    if let url = manager.streamURL {
                        LabeledContent("ストリームURL") {
                            Text(url)
                                .font(.caption2)
                                .textSelection(.enabled)
                        }
                    }
                    if let error = manager.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("操作") {
                    Button(manager.isStreaming ? "配信を停止" : "配信を開始") {
                        if manager.isStreaming {
                            manager.stop()
                        } else {
                            manager.start()
                        }
                    }
                }

                Section("使い方") {
                    Text("1. iPhoneでkonomitvを開く\n2. この画面で「配信を開始」をタップ(初回は画面録画の許可が必要)\n3. すぐにkonomitvへ画面を切り替える\n4. Apple Watchアプリを開くと自動検出して再生が始まる\n5. 終了時はこの画面で「配信を停止」")
                        .font(.caption)
                }
            }
            .navigationTitle("Watchkonomi")
        }
    }
}

#Preview {
    ContentView()
}
