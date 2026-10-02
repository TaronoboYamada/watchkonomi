# Watchkonomi

Apple WatchでKonomiTVの1segを再生するプロジェクト。

## v2(新・Watch単体版)

`v2/` フォルダには、**Apple WatchからKonomiTVサーバーに直接接続する**新バージョンがあります。
iPhoneアプリや画面キャプチャは不要です。

### 仕組み

```
Apple Watch
  ├ GET /api/channels → チャンネル一覧(KonomiTV /tv/ 風UI)
  └ 再生時: GET /api/streams/live/{ch}/{画質}/mpegts (MPEG-TS受信)
     → アプリ内で2秒単位のセグメントに分割(再エンコードなし)
     → ループバックHTTPサーバー(127.0.0.1)でライブHLS配信
     → AVPlayerで再生
```

- WatchはKonomiTVサーバーに到達できること(同一Wi-Fi、またはiPhoneのTailscale経由)
- 再生遅延はHLSの性質上 約10〜20秒
- 画質は設定画面で変更可能(既定 240p)
- サーバーURLは設定画面で変更可能(既定 `https://100-111-2-73.local.konomi.tv:7000`)

### ビルド

pushすると `Build` ワークフローが自動でビルドします(XcodeGen生成 → watchOSシミュレータでユニットテスト → watch IPA)。
生成された `Watchkonomi-watch.ipa` をAltStoreでインストール(INSTALL-NOMAC.txt 参照)。

---

## v1(旧・iPhone中継版)

Apple Watchで、iPhoneのkonomitvから受信した1segの映像・音声を再生するプロジェクト。

## 仕組み

Apple Watchには1segチューナーがなく、konomitvはサードパーティ製アプリのため、
**iPhone側でkonomitvの画面をReplayKit(broadcast拡張)でキャプチャ → H.264+AACに编码 →
同一Wi-FiでHLS配信 → Watch側でAVPlayerが再生** という構成です。

```
iPhone: konomitv(前面表示)
   │ ReplayKit broadcast拡張(画面+音声キャプチャ)
   ▼
H.264 + AAC-LC 编码 → TSセグメント(4秒) + m3u8
   │ ローカルHTTPサーバー(NWListener) + Bonjour(_watchkonomi._tcp)
   ▼ 同一Wi-Fi
Apple Watch: Bonjour発見 → AVPlayerで映像+音声再生
```

## 構成

| ターゲット | 種類 | 役割 |
| --- | --- | --- |
| `WatchApp` | watchOSアプリ(コンテナ) | Watchアプリ本体 |
| `WatchApp Extension` | watchOS App Extension | BonjourでiPhoneを検出しAVPlayerで再生 |
| `Watchkonomi iOS` | iOSアプリ | 配信の開始/停止(`RPBroadcastController`)、状態表示 |
| `Streamer` | Broadcast Upload Extension | 画面+音声キャプチャ → HLS配信(HTTPサーバー+Bonjour) |

- 映像: 540p(高さ)に縮小、H.264(約800kbps、30fpsに間引き)
- 音声: AAC-LC(約96kbps)
- 遅延: HLSの性質上、数秒程度

## ビルド

watchOS/iOSのビルドはmacOS(Xcode)でのみ可能です(Xcode 27はmacOS専用)。

### Macがある場合

1. `Watchkonomi.xcodeproj` をXcodeで開く
2. Signing & Capabilitiesで自分のチームを設定(Bundle Identifierも必要に応じて変更)
3. iPhone実機+Apple Watchを接続し、`Watchkonomi iOS`スキームでRun

### Macがない場合

GitHub Actions(`.github/workflows/build.yml`)がmacOSランナーで自動ビルドします。
リポジトリをGitHubにpushするとwatchOS・iOS両方のシミュレータ向けビルドが実行されます。

## 使い方

1. iPhoneでkonomitvを開く
2. iOSアプリ(Watchkonomi)で「配信を開始」をタップ(初回は画面録画の許可を求められる)
3. すぐにkonomitvへ画面を切り替える(配信は画面全体をキャプチャする)
4. Apple Watchアプリを開く(配信開始前は開いておいてもよい)。同一Wi-Fi内なら自動検出して再生開始
5. 終了時はiOSアプリで「配信を停止」

配信の開始はControl Centerの画面録画ボタンから`Watchkonomi Streamer`を選択してもよい
(この場合、konomitvを前面に保ったまま開始できる)。

## 必要条件・制約

- iPhoneとApple Watchが**同一Wi-Fi**にいること(WatchはiPhoneのネットワークを利用)
- 初回にiOSアプリ・Watchアプリそれぞれで「ローカルネットワーク」の許可が必要
- 再生中はkonomitvが**前面表示**であること(画面キャプチャ方式のため)
- Broadcast拡張は**シミュレータでは動作しない**(実機iPhoneで検証すること)
- 常時キャプチャ+编码+配信のため電池消耗が大きい
- 配信サーバーはローカルWi-Fi内の誰でもアクセスできる(ポートはランダム)。自宅ネットワークで利用することを前提とする

## 開発環境(このPC: Windows)

- Swift 6.4ツールチェーン(winget `Swift.Toolchain`)— Swiftの編集・構文チェック用
- watchOS/iOSのビルド自体はmacOS必須(Windows版Xcodeは存在しない)

## 始める前に

- Bundle Identifier(`com.example.watchkonomi`等)を自分用に置き換えてください
  - 拡張のBundle IDは`com.example.watchkonomi.ios.streamer`
  - `Watchkonomi iOS/BroadcastManager.swift`内の`broadcastExtensionBundleID`も合わせて変更
- AppIcon(`WatchApp Extension/Assets.xcassets/AppIcon.appiconset`)に1024x1024のアイコンを追加してください
