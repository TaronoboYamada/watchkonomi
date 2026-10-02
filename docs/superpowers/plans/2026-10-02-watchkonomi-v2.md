# Watchkonomi v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apple Watch単体でKonomiTVサーバー(v0.14.1)に直接接続し、チャンネルリストからライブ(MPEG-TS)をAVPlayerで再生できるwatchOSアプリを `v2/` に新規作成する。

**Architecture:** Watchアプリが `/api/channels` でチャンネル一覧+番組情報を取得し(`/tv/` 風のダークUIで表示)、再生時に `/api/streams/live/{ch}/{quality}/mpegts` のMPEG-TSをHTTPストリーム受信。アプリ内でMPEG-TSを2秒単位のセグメントに分割(再エンコードなしのパススルー)し、ループバックHTTPサーバー(127.0.0.1)経由でライブHLSプレイリストとしてAVPlayerに渡す。

**Tech Stack:** Swift 6 / SwiftUI (watchOS 10.0+) / AVKit (VideoPlayer) / Network.framework (NWListener) / XcodeGen / GitHub Actions (macos-26) / XCTest(純粋ロジックのみ)

**Spec:** 2026-10-02にユーザー承認済みのv2計画(チャット内)。要点は Global Constraints に転記済み。

## Global Constraints

- ターゲットは **watchOSアプリ1個のみ**(iOSアプリ・拡張は作らない)。deployment target **watchOS 10.0**
- 依存ライブラリなし(SPM/CocoaPods不使用)。プロジェクト生成は **XcodeGen**(`v2/project.yml`)。生成物 `v2/*.xcodeproj` は `.gitignore` 対象
- KonomiTV API パス(完全一致): `GET /api/channels`、`GET /api/channels/{id}/logo`、`GET /api/streams/live/{display_channel_id}/{quality}/mpegts`。認証不要
- 画質値(完全一致): `240p` `360p` `480p` `540p` `720p` `810p` `1080p` `1080p-60fps`。デフォルト **240p**
- 既定サーバーURL: `https://100-111-2-73.local.konomi.tv:7000`。Bundle ID: `com.example.watchkonomi.watch`
- サーバーは自己署名証明書のため **TLS検証をスキップ**(個人利用前提)。ATS許可のため Info.plist に `NSAppTransportSecurity.NSAllowsArbitraryLoads = true`
- 映像は再エンコードしない。TSパススルー分割: 目標セグメント長 **2.0秒**、ウィンドウ **8** セグメント、**3** セグメント揃うまで配信開始しない
- デザイン: 黒背景、アクセント **#E64F97**(KonomiTV pink)
- 既存コード(`v2/` 以外)は **一切変更しない**(ルート `.github/workflows/build.yml` と `README.md`・`INSTALL-NOMAC.txt`・`.gitignore` を除く)
- CI: `macos-26` ランナー、`brew install xcodegen` → `xcodegen generate` → watchOSシミュレータでXCTest実行 → generic watchOS 実機ビルド(非署名) → **watch IPA のみ**アーティファクト化
- Mac無しで開発するため、ローカル検証は `swiftc -parse`(Windows Swiftツールチェーン)+ push後のCIが正。全タスクの最終検証はCIグリーン
- 純粋Foundationロジックのタスク(2〜5)は、WindowsのSwiftツールチェーンでXCTestを実実行できる: `$env:TEMP\opencode\wktest` にSwiftPMパッケージ(`swiftLanguageModes: [.v5]`、`targets` が `swiftLanguageModes` より前)を作り、`v2/Watchkonomi/**` の該当ソース+`v2/Tests/**` をコピーして `swift test`。SwiftUI/Networkを使うファイルはローカルから除外(`swiftc -parse` のみ)

## Review Focus

1. **サーバーURL入力が不正**(スキーム無し・末尾スラッシュ・空文字)→ 正規化して https 補完/スラッシュ除去、不正ならnilでエラー表示。Task 3でpin。
2. **TS先頭がパケット境界から始まらない/PTSが暫く来ない**→ 0x47同期で再同期し、未完成パケット尾部は保留、PTS不在でも1500パケット(282KB)で強制切断しクラッシュしない。Task 4・5でpin。
3. **`program_present: null` のチャンネル**(放送休止・サブチャンネル)→ 行が「番組情報なし」を表示しデコードもUIも落ちない。Task 2・7bでpin。
4. **mpegts接続の途切れ**(サーバーOffline・Wi-Fi断)→ pumpがthrowし、プレイヤーは失敗表示で停止、無限再接続しない。Task 7cでmanual確認(checklist)。
5. **自己署名証明書のサーバーへの全リクエスト**(JSON/ロゴ/ストリーム)→ 共通のTLS全許可 `URLSession` を必ず経由し、素の `URLSession.shared` / `AsyncImage` を使わない。Task 6・7bでpin(7bはmanual確認)。

---

### Task 1: プロジェクト雛形 + XcodeGen + CI

**Files:**
- Create: `v2/project.yml`
- Create: `v2/Watchkonomi/WatchkonomiApp.swift`(仮実装: `Text("Watchkonomi")` のみ)
- Create: `v2/Tests/SmokeTests.swift`( `XCTAssertTrue(true)` のみ)
- Modify: `.gitignore`(`v2/*.xcodeproj` 追加)
- Modify: `.github/workflows/build.yml`(全置換)

**Interfaces:**
- Produces: スキーム名 `Watchkonomi`(build+test両対応)。以降の全タスクのファイルは `v2/Watchkonomi/` 配下に置けば自動でビルド・テスト対象になる

- [ ] **Step 1: `v2/project.yml` を書く**

```yaml
name: Watchkonomi
options:
  bundleIdPrefix: com.example.watchkonomi
  deploymentTarget:
    watchOS: "10.0"
targets:
  Watchkonomi:
    type: application
    platform: watchOS
    sources: [Watchkonomi]
    info:
      path: Watchkonomi/Info.plist
      properties:
        WKApplication: true
        CFBundleDisplayName: Watchkonomi
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.watchkonomi.watch
  WatchkonomiTests:
    type: bundle.unit-test
    platform: watchOS
    sources: [Tests]
    dependencies:
      - target: Watchkonomi
schemes:
  Watchkonomi:
    build:
      targets: { Watchkonomi: all }
    test:
      targets: [WatchkonomiTests]
```

- [ ] **Step 2: 最小アプリとテストを置く**

`WatchkonomiApp.swift`:
```swift
import SwiftUI

@main
struct WatchkonomiApp: App {
    var body: some Scene {
        WindowGroup { Text("Watchkonomi") }
    }
}
```
`Tests/SmokeTests.swift`:
```swift
import XCTest

final class SmokeTests: XCTestCase {
    func testSmoke() { XCTAssertTrue(true) }
}
```

- [ ] **Step 3: `.gitignore` に `v2/*.xcodeproj` を追加**

- [ ] **Step 4: `.github/workflows/build.yml` を全置換**

```yaml
name: Build
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Generate project
        run: xcodegen generate
        working-directory: v2
      - name: List available simulators
        run: xcrun simctl list devices available
      - name: Run unit tests
        working-directory: v2
        run: |
          set -o pipefail
          UDID=$(xcrun simctl list devices available -j | jq -r '.devices | to_entries[] | select(.key | contains("watchOS")) | .value[] | select(.isAvailable) | .udid' | head -n 1)
          echo "Using simulator UDID: $UDID"
          xcodebuild test -project Watchkonomi.xcodeproj -scheme Watchkonomi \
            -destination "platform=watchOS Simulator,id=$UDID" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -n 60
      - name: Build watch app for device (unsigned)
        working-directory: v2
        run: xcodebuild build -project Watchkonomi.xcodeproj -scheme Watchkonomi \
          -configuration Debug -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -n 30
      - name: Package watch IPA
        run: |
          APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -type d -path "*Debug-watchos/Watchkonomi.app" | head -n 1)
          mkdir -p ipa-watch/Payload && cp -R "$APP" ipa-watch/Payload/
          (cd ipa-watch && zip -qr ../Watchkonomi-watch.ipa Payload)
      - uses: actions/upload-artifact@v4
        with:
          name: ipas
          path: Watchkonomi-watch.ipa
```

- [ ] **Step 5: ローカル構文チェック(Windows)**

Run: `swiftc -parse v2/Watchkonomi/WatchkonomiApp.swift v2/Tests/SmokeTests.swift`
Expected: エラー0件

- [ ] **Step 6: Commit & push & CI確認**

```bash
git add v2 .gitignore .github/workflows/build.yml
git commit -m "v2: watchOS app skeleton with XcodeGen and CI"
git push
```
Expected: GitHub Actions の Build ワークフローが緑、artifact `ipas` に `Watchkonomi-watch.ipa`

---

### Task 2: チャンネルモデル+デコード

**Files:**
- Create: `v2/Watchkonomi/Models/Channel.swift`
- Test: `v2/Tests/ChannelTests.swift`

**Interfaces:**
- Produces:
  - `struct LiveChannel: Codable, Identifiable, Hashable` — `id: String, displayChannelID: String, channelNumber: String, type: String, name: String, isRadiochannel: Bool, isDisplay: Bool, programPresent: LiveProgram?`
  - `struct LiveProgram: Codable, Hashable` — `title: String, description: String?, startTime: String, endTime: String`(+計算プロパティ `var timeText: String` → `"19:00-20:00"`)
  - `struct LiveChannelsResponse: Codable` — `gr, bs, cs, catv, sky, bs4k: [LiveChannel]`(JSONキー `GR/BS/CS/CATV/SKY/BS4K`)
  - `struct ChannelGroup: Hashable` — `label: String, channels: [LiveChannel]`
  - `extension LiveChannelsResponse { var groups: [ChannelGroup] }` — ラベル順 `[地デジ(GR), BS, CS, CATV, SKY, BS4K]`、**`isDisplay == true` のみ**収める
  - `extension LiveProgram.timeText` — `startTime.dropFirst(11).prefix(5)` + `"-"` + `endTime` 同様(ISO文字列を直接スライス、パースしない)

- [ ] **Step 1: 失敗するテストを書く**(`ChannelTests.swift`)

フィクスチャ(正確にこれを使う):
```swift
let fixture = """
{"GR":[{"id":"NID32736-SID1024","display_channel_id":"gr011","channel_number":"011","type":"GR",
"name":"NHK総合","jikkyo_force":10,"is_subchannel":false,"is_radiochannel":false,"is_watchable":true,
"terrestrial_regions":["東京"],"is_display":true,"viewer_count":2,
"program_present":{"title":"ニュース","description":null,"detail":{},
"start_time":"2026-10-02T19:00:00+09:00","end_time":"2026-10-02T20:00:00+09:00","is_free":true,"genres":[]},
"program_following":null}],
"BS":[],"CS":[],"CATV":[],"SKY":[],"BS4K":[]}
"""
```
- `testDecodeLiveChannelsResponse`: デコード成功、`gr[0].displayChannelID == "gr011"`、`gr[0].programPresent?.title == "ニュース"`、`gr[0].programPresent?.timeText == "19:00-20:00"`
- `testDecodeNullProgramPresent`: `program_present` を `null` に変えた同一フィクスチャ → デコード成功、`programPresent == nil`
- `testGroupsFiltersHiddenAndLabels`: `is_display:false` のBSチャンネルを1つ足す → `groups` は `[地デジ, BS]` で地デジのみ1件、BSは空(空グループは残す)

- [ ] **Step 2: テスト失敗を確認(ローカル型エラー=未実装、CIでFAIL)** — 実装前にcommitしない

- [ ] **Step 3: `Channel.swift` を実装** — CodingKeysで snake_case(`display_channel_id` 等)を対応付け。`groups` のラベル: `GR→"地デジ"`、`BS→"BS"`、`CS→"CS"`、`CATV→"CATV"`、`SKY→"SKY"`、`BS4K→"BS4K"`

- [ ] **Step 4: CIでテストPASS確認**

Run: push後 GitHub Actions「Run unit tests」
Expected: PASS(3件)

- [ ] **Step 5: Commit**

```bash
git add v2/Watchkonomi/Models/Channel.swift v2/Tests/ChannelTests.swift
git commit -m "v2: channel models and LiveChannels decoding"
```

---

### Task 3: URL組み立て+正規化

**Files:**
- Create: `v2/Watchkonomi/Services/KonomiTVClient.swift`(このタスクでは純粋関数のみ。通信はTask 6)
- Test: `v2/Tests/KonomiTVClientURLTests.swift`

**Interfaces:**
- Consumes: Task 2 の `LiveChannel`
- Produces:
  - `struct KonomiTVClient` — `let baseURL: URL` / `init(baseURL: URL)`
  - `static func sanitizedBaseURL(from text: String) -> URL?` — 前後空白除去・末尾`/`除去。スキーム無しは `https://` を補完。schemeがhttp/https以外、host空なら `nil`
  - `var channelsURL: URL` → `{base}/api/channels`
  - `func logoURL(for channel: LiveChannel) -> URL` → `{base}/api/channels/{channel.id}/logo`
  - `func streamURL(displayChannelID: String, quality: String) -> URL` → `{base}/api/streams/live/{id}/{quality}/mpegts`

- [ ] **Step 1: 失敗するテストを書く**

- `testSanitizeTrimsTrailingSlash`: `"https://h:7000/"` → `https://h:7000`
- `testSanitizeAddsHTTPS`: `"100-111-2-73.local.konomi.tv:7000"` → `https://100-111-2-73.local.konomi.tv:7000`
- `testSanitizeRejectsFTP`: `"ftp://h"` → `nil`、`""` → `nil`
- `testStreamURL`: `streamURL(displayChannelID: "gr011", quality: "1080p-60fps")` のabsoluteString == `https://h:7000/api/streams/live/gr011/1080p-60fps/mpegts`
- `testLogoURL`: `logoURL(for:)` のabsoluteString == `https://h:7000/api/channels/NID32736-SID1024/logo`

- [ ] **Step 2: テスト失敗を確認**

- [ ] **Step 3: 実装** — 正規化は `Foundation.URLComponents` を使用。通信系プロパティはまだ書かない

- [ ] **Step 4: CI PASS確認** / **Step 5: Commit**

```bash
git add v2/Watchkonomi/Services/KonomiTVClient.swift v2/Tests/KonomiTVClientURLTests.swift
git commit -m "v2: KonomiTV URL building and base URL sanitization"
```

---

### Task 4: TSパケット解析+PTS抽出

**Files:**
- Create: `v2/Watchkonomi/Services/TSPacket.swift`
- Create: `v2/Tests/Helpers/TSTestPacketFactory.swift`(テスト専用)
- Test: `v2/Tests/TSParserTests.swift`

**Interfaces:**
- Produces:
  - `enum TSParser` — `static let packetSize = 188` / `static func extractPackets(pending: inout Data) -> [Data]`(完了パケット列を返し、`pending` に未完成尾部を残す。先頭が0x47でなければ1バイト捨てて再同期) / `static func extractPTS(from packet: Data) -> Double?`(秒。PES無しやAF内データは `nil`)
  - `enum TSTestPacketFactory` — `static func packet(pid: UInt16 = 0x100, continuity: UInt8 = 0, pusi: Bool = false, pts: Double? = nil) -> Data`(188バイト固定。以下のビット構成をそのまま実装)

**テストヘルパーの正確な仕様**(実装者が選択余地のない箇所):
- ヘッダ: `b0=0x47`、`b1=(pusi ? 0x40 : 0x00) | ((pid >> 8) & 0x1F)`、`b2=pid & 0xFF`、`b3=0x10 | (continuity & 0x0F)`(payload-only, AFC=01)
- PES(pusi==true かつ pts != nil のとき): payload先頭に `[0x00,0x00,0x01,0xE0, 0x00,0x00, 0xA0, 0x05, PTS5バイト]`、残り `0xFF` 埋め(`0xA0` = marker 0x80 + PTS_DTS_flags「PTS only」0x20)
- PTS5バイト: `p = UInt64((pts * 90000).rounded())`(33bit) とし、
  `b0 = 0x21 | (UInt8((p >> 30) & 0x07) << 1)`、`b1 = UInt8((p >> 22) & 0xFF)`、`b2 = 0x01 | (UInt8((p >> 15) & 0x7F) << 1)`、`b3 = UInt8((p >> 7) & 0xFF)`、`b4 = 0x01 | (UInt8(p & 0x7F) << 1)`

- [ ] **Step 1: 失敗するテストを書く**

- `testExtractPTSFromPESPacket`: `packet(pusi: true, pts: 123.456)` → `extractPTS` が `123.456` と `0.001` 以内で一致
- `testExtractPTSNilForNonPES`: `packet(pusi: false, pts: nil)` → `nil`。`packet(pusi: true, pts: nil)`(PES無しpayload-only)→ `nil`
- `testExtractPacketsAlignsAfterJunk`: 先頭に7バイトのゴミ + 3パケット分を連結 → 3パケット取得、`pending` がゴミを含まない
- `testExtractPacketsHoldsPartialTail`: 2.5パケット分 → 2パケット、`pending.count == 94`

- [ ] **Step 2: テスト失敗を確認**

- [ ] **Step 3: 実装** — `extractPTS` はパケットを走査: ヘッダ4バイト→flagsのAFC bits(5-4)が 2/3 なら adaptation field長分スキップ→payloadが `00 00 01` で始まり PTS_DTS_flags(bits5-4)==0x2(PTS only)または0x3(両方)、header_len(第8バイト)>=5 なら PTS 5バイトを逆変換: `raw = (UInt64((b0 & 0x0E) >> 1) << 30) | (UInt64(b1) << 22) | (UInt64(b2 >> 1) << 15) | (UInt64(b3) << 7) | (UInt64(b4) >> 1)`、`return Double(raw) / 90000.0`
- **実行時メモ(実装済み)**: Windows Swift 6.4 ツールチェーンでは `Data.removeFirst()` 後のサブスクリプト読み(`d[0]`)がクラッシュする(c000001d)。`extractPackets` は `removeSubrange(0..<n)` を使うこと。また Data スライスのインデックスはリベースされないため、パケット先頭を参照する際は `Data(slice)` でコピーすること

- [ ] **Step 4: CI PASS確認** / **Step 5: Commit**

```bash
git add v2/Watchkonomi/Services/TSPacket.swift v2/Tests/Helpers/TSTestPacketFactory.swift v2/Tests/TSParserTests.swift
git commit -m "v2: MPEG-TS packet extraction and PES PTS parsing"
```

---

### Task 5: セグメント化+HLSプレイリスト生成

**Files:**
- Create: `v2/Watchkonomi/Services/StreamMuxer.swift`
- Test: `v2/Tests/StreamMuxerTests.swift`

**Interfaces:**
- Consumes: Task 4 の `TSParser`
- Produces:
  - `final class StreamMuxer: ObservableObject`
    - `enum MuxerState: Equatable { case idle, connecting, onair, failed(String) }`
    - `init(targetSegmentSeconds: Double = 2.0, windowSize: Int = 8, readySegments: Int = 3)`
    - `@Published private(set) var state: MuxerState`(初期 `.idle`。`beginConnection()` で `.connecting`、最初のセグメント完成で `.onair`、`fail(_:)` で `.failed`)
    - `func beginConnection()` / `func fail(_ message: String)` / `func ingest(_ data: Data)` / `func stop()`
    - `var isReady: Bool`(`segments.count >= readySegments`)
    - `var firstMediaSequence: Int` / `func playlist() -> String?`(未readyは `nil`)/ `func segmentData(index: Int) -> Data?`(絶対シーケンス番号)
    - 実装メモ: 全パブリックメソッドは `NSLock` で保護(pumpタスク/ループバックサーバー/UI が同時アクセスするため)。state 変更はメインスレッドで反映

**切断規則(正確な仕様)：**
1. `ingest` は受信チャンクを内部 `pending` に足し、`TSParser.extractPackets` で完了パケットごとに処理
2. パケットごとに `extractPTS`。`pts != nil` なら: セグメント開始PTSが未設定なら設定し、`pts - 開始PTS >= targetSegmentSeconds` ならバッファを確定(持続時間 = `最後のPTS - 開始PTS`)して次のセグメントへ。`lastPTS` を更新
3. PTSが一切来ないまま **1500パケット** 蓄積したら強制確定(duration 0.0)
4. ウィンドウ: `segments.count > windowSize` の間 `removeFirst()` し `firstMediaSequence += 1`
5. `playlist()` のテキスト(この形式そのまま)：
   ```
   #EXTM3U
   #EXT-X-VERSION:3
   #EXT-X-TARGETDURATION:{Int(ceil(最大セグメントduration)), 最小1}
   #EXT-X-MEDIA-SEQUENCE:{firstMediaSequence}
   #EXTINF:{duration:.3f},   ← セグメントごとに1行
   ```

- [ ] **Step 1: 失敗するテストを書く**(ヘルパーはTask 4の `TSTestPacketFactory` を使用。PTSが0.25秒ずつ進むパケットを8個=2秒で1セグメント)

- `testIngestCutsSegmentByPTS`: pts=0.0〜2.25の10パケット(0.25秒間隔)を `ingest` → セグメント1個確定、`state == .onair`
- `testPlaylistFormat`: 3セグメント分ingest → `isReady == true`、`playlist()` が `#EXTM3U` で始まり `#EXT-X-MEDIA-SEQUENCE:0` を含み `#EXTINF:2.000,` を含む
- `testPlaylistNilBeforeReady`: 1セグメントのみ → `playlist() == nil`
- `testWindowSlidesMediaSequence`: 10セグメント分ingest(windowSize=8, readySegments=3)→ `firstMediaSequence == 2`、playlistに `#EXT-X-MEDIA-SEQUENCE:2`
- `testSegmentDataLookup`: 10セグメント後 → `segmentData(index: 0) == nil`(slided out)、`segmentData(index: 2)` は非nil、`segmentData(index: 99) == nil`
- `testHoldsPartialTail`: パケット1個+188バイト未満の追加分 → まだ確定しない(`isReady == false`)

- [ ] **Step 2: テスト失敗を確認** / **Step 3: 実装** / **Step 4: CI PASS確認**

- [ ] **Step 5: Commit**

```bash
git add v2/Watchkonomi/Services/StreamMuxer.swift v2/Tests/StreamMuxerTests.swift
git commit -m "v2: TS segmenter with live HLS playlist generation"
```

---

### Task 6: ストリーム受信+ループバックHTTPサーバー

**Files:**
- Create: `v2/Watchkonomi/Services/StreamTransport.swift`(TLS許可セッション+pump)
- Create: `v2/Watchkonomi/Services/LoopbackServer.swift`
- Test: なし(Network/Socketは実機検証。CIのビルド成功をゲートにする)

**Interfaces:**
- Consumes: Task 3 `KonomiTVClient.streamURL`, Task 5 `StreamMuxer`
- Produces:
  - `extension KonomiTVClient { static let streamSession: URLSession }` — `URLSessionDelegate` で `didReceive challenge` に対し常に `.useCredential(URLCredential(trust: serverTrust))`(Review Focus #5)。`timeoutIntervalForRequest = 30`、`timeoutIntervalForResource = 3600`
  - `enum StreamPump { static func run(url: URL, muxer: StreamMuxer, session: URLSession) async throws }` — `session.bytes(for:)` を回し、**64KBバッファにまとめて** `muxer.ingest`。終端/エラーはthrow
  - `final class LoopbackServer`
    - `func start(muxer: StreamMuxer) async throws` — `NWListener`(TCP, `requiredLocalEndpoint = hostPort(host:"127.0.0.1", port:.any)`)。`.ready` で `port` 確定までawait
    - `func stop()`
    - `private(set) var playlistURL: URL?`(`http://127.0.0.1:{port}/live.m3u8`)
    - ルーティング: `GET /live.m3u8` → `muxer.playlist()`(nilなら `503`) / `GET /seg{n}.ts` → `muxer.segmentData(index: n)`(nilなら `404`)/ その他 `404`
    - レスポンスヘッダ: `Content-Type: application/vnd.apple.mpegurl | video/mp2t`、`Content-Length`、`Cache-Control: no-store`、`Connection: close`

- [ ] **Step 1: `StreamTransport.swift` を実装**(HTTPではなくURLSessionのTCP/TLS部分のみの委譲クラス `InsecureTrustDelegate: NSObject, URLSessionDelegate` を含む)
- [ ] **Step 2: `LoopbackServer.swift` を実装** — リクエストは `\r\n\r\n` まで読む(上限8KB)。HTTP処理は旧 `Streamer/StreamServer.swift` の `NWConnection` 取扱いを参考にしてよいがコードは新規に書く(旧コードは変更しない)
- [ ] **Step 3: ローカル構文チェック**

Run: `swiftc -parse v2/Watchkonomi/Services/StreamTransport.swift v2/Watchkonomi/Services/LoopbackServer.swift`
Expected: エラー0件

- [ ] **Step 4: CIビルド緑確認** / **Step 5: Commit**

```bash
git add v2/Watchkonomi/Services/StreamTransport.swift v2/Watchkonomi/Services/LoopbackServer.swift
git commit -m "v2: TLS-tolerant stream session, pump, and loopback HLS server"
```

---

### Task 7a: 画質設定+設定画面

**Files:**
- Create: `v2/Watchkonomi/Models/StreamQuality.swift`
- Create: `v2/Watchkonomi/Views/SettingsView.swift`
- Modify: `v2/Watchkonomi/WatchkonomiApp.swift`(RootViewへ差し替え)
- Create: `v2/Watchkonomi/Views/RootView.swift`(仮: 設定ボタンのみ。Task 7cで本体実装)
- Test: `v2/Tests/StreamQualityTests.swift`

**Interfaces:**
- Consumes: Task 3 `KonomiTVClient.sanitizedBaseURL`, Task 2 `ChannelGroup`
- Produces:
  - `enum StreamQuality: String, CaseIterable, Identifiable` — rawValueは `240p, 360p, 480p, 540p, 720p, 810p, 1080p, 1080p-60fps`(Global Constraintsの並び順)。`var id: String { rawValue }`、`var label: String`(例: `"1080p-60fps"` → `"1080p (60fps)"`、他はそのまま)
  - AppStorageキー(全UI共通・この文字列そのまま)： `"serverURLText"`(既定 `https://100-111-2-73.local.konomi.tv:7000`)、`"streamQuality"`(既定 `"240p"`)

- [ ] **Step 1: 失敗するテストを書く**

- `testQualityRawValuesMatchAPI`: `StreamQuality.allCases.map(\.rawValue)` == `["240p","360p","480p","540p","720p","810p","1080p","1080p-60fps"]`
- `testQualityLabel`: `StreamQuality(rawValue: "1080p-60fps")!.label == "1080p (60fps)"`、`"240p"` → `"240p"`

- [ ] **Step 2: 失敗確認** / **Step 3: `StreamQuality.swift` 実装** / **Step 4: CI PASS確認**

- [ ] **Step 5: `SettingsView` 実装** — List + `TextField`(`serverURLText`, キーボード `.URL`)、`Picker`(label表示、`streamQuality`)、「接続テスト」ボタン: `sanitizedBaseURL` → `KonomiTVClient(baseURL:).fetchChannels()` はTask 7cまで未実装のため、**このタスクではボタン無し**のコメント行 `// TODO(Task 7c): 接続テストボタン` を置く。`sanitizedBaseURL(from:)` がnilを返す入力のときはピンクで「URLが不正です」を表示
- [ ] **Step 6: CIビルド緑確認** / **Step 7: Commit**

```bash
git add v2/Watchkonomi/Models/StreamQuality.swift v2/Watchkonomi/Views/SettingsView.swift v2/Watchkonomi/Views/RootView.swift v2/Watchkonomi/WatchkonomiApp.swift v2/Tests/StreamQualityTests.swift
git commit -m "v2: quality selection and settings screen"
```

---

### Task 7b: チャンネルリストUI(/tv/ 風)

**Files:**
- Create: `v2/Watchkonomi/Views/ChannelListView.swift`(+同ファイル内に `ChannelRowView` と `LogoView`)
- Modify: `v2/Watchkonomi/Views/RootView.swift`(本体実装)
- Test: なし(UI。CIビルド+Task 8のmanualチェックリスト)

**Interfaces:**
- Consumes: Task 2 `ChannelGroup`/`LiveChannel`, Task 3 `KonomiTVClient`, Task 7a AppStorageキー
- Produces:
  - `struct ChannelListView: View` — `@AppStorage("serverURLText")`。`.task(id: serverURLText)` で `fetchChannels()`(→ `[ChannelGroup]`)。失敗時はピンクでエラーメッセージ+「再読み込み」ボタン。`navigationDestination(for: LiveChannel.self)` → `PlayerView`(Task 7cが提供、本タスクでは `// TODO(Task 7c)` プレースホルダViewを一時定義してビルドを通す)
  - `struct ChannelRowView: View` — `init(channel: LiveChannel, baseURL: URL)`。HStack: `LogoView`(32x32)+VStack(`channelNumber + " " + name` / program: `programPresent` があれば `timeText + " " + title`、nilなら「番組情報なし」— Review Focus #3)。フォアグラウンド白、背景黒
  - `struct LogoView: View` — `init(url: URL)`。`KonomiTVClient.streamSession.data(from:)` で取得(素の `AsyncImage` 禁止 — Review Focus #5)。失敗時は `tv` システムアイコン
  - `extension KonomiTVClient { func fetchChannels() async throws -> [ChannelGroup] }` — `streamSession` で `channelsURL` をGETし `LiveChannelsResponse` をデコード→ `groups`
  - RootView本体： `NavigationStack { ChannelListView() }` + toolbar(設定ギア → sheet `SettingsView`)

- [ ] **Step 1: 実装**(KonomiTV行スタイル: セクションヘッダーにグループlabel、アクセント#E64F97はエラー/選択色)
- [ ] **Step 2: ローカル `swiftc -parse` エラー0件**
- [ ] **Step 3: CIビルド緑確認** / **Step 4: Commit**

```bash
git add v2/Watchkonomi/Views/ChannelListView.swift v2/Watchkonomi/Views/RootView.swift
git commit -m "v2: channel list UI with logos and program info"
```

---

### Task 7c: 再生+PlaybackModel

**Files:**
- Create: `v2/Watchkonomi/ViewModels/PlaybackModel.swift`
- Create: `v2/Watchkonomi/Views/PlayerView.swift`
- Modify: `v2/Watchkonomi/Views/ChannelListView.swift`(プレースホルダ削除、実PlayerViewへ)
- Modify: `v2/Watchkonomi/Views/SettingsView.swift`(`TODO(Task 7c)` に「接続テスト」ボタン実装)

**Interfaces:**
- Consumes: Task 5 `StreamMuxer`, Task 6 `LoopbackServer`/`StreamPump`/`streamSession`, Task 3 `streamURL`, Task 7a `StreamQuality`
- Produces:
  - `@MainActor final class PlaybackModel: ObservableObject` — `let player = AVPlayer()` / `@Published private(set) var muxerState: StreamMuxer.MuxerState = .idle` / `func start(baseURL: URL, channel: LiveChannel, quality: String) async` / `func stop()`
  - `start` の手順(この順序で)： ①`stop()` ②muxer/server生成、`try await server.start(muxer:)` ③`StreamPump.run` を別Taskで起動(catchで `muxerState = .failed(String(describing:))`) ④`muxer.isReady` を0.2秒間隔で最大30秒待つ(タイムアウトで `.failed("タイムアウト")`) ⑤`AVPlayerItem(url: server.playlistURL!)` をセットし `play()`
  - `struct PlayerView: View` — `init(channel: LiveChannel, baseURL: URL, quality: String)`。全面 `VideoPlayer(player:)`、オーバーレイ: 左上 閉じる(`xmark`, `dismiss()`+`model.stop()`)、右上 ミュートトグル(`speaker.wave.2`/`speaker.slash`)、下部 `channelNumber name`+program title。`.connecting` 中は `ProgressView`+「接続中…」、`.failed` はメッセージ+「閉じる」。`.onDisappear { model.stop() }`
  - `SettingsView` 接続テスト： `fetchChannels()` 成功 →「接続OK(チャンネルN件)」、失敗 → エラー文言

- [ ] **Step 1: 実装**(`channel_type == "GR"` かつ `isRadiochannel` のチャンネルもそのまま再生してよい。特別扱いしない)
- [ ] **Step 2: ローカル `swiftc -parse` エラー0件**
- [ ] **Step 3: CIビルド緑+IPA artifact確認** / **Step 4: Commit**

```bash
git add v2/Watchkonomi/ViewModels/PlaybackModel.swift v2/Watchkonomi/Views/PlayerView.swift v2/Watchkonomi/Views/ChannelListView.swift v2/Watchkonomi/Views/SettingsView.swift
git commit -m "v2: live playback via loopback HLS and player UI"
```

---

### Task 8: ドキュメント+最終検証

**Files:**
- Modify: `README.md`(先頭付近に「v2(新)」節を追加: 直接接続方式・使い方・遅延10〜20秒の注記・旧(v1)は `Streamer/` ほか現状維持)
- Modify: `INSTALL-NOMAC.txt`(手順2をwatch IPAのみ: `Watchkonomi-watch.ipa` 1ファイル、iOS IPAインストール手順の削除)

**Interfaces:**
- Consumes: 全Task。マニュアル検証チェックリスト(実機、お手元環境):
  1. WatchをiPhoneと同じWi-Fi(またはiPhone経由Tailscale)に置き、起動→チャンネル一覧が出る
  2. ロゴ画像が表示される(=TLS許可がロゴでも効いている/Review Focus #5)
  3. `program_present: null` の行でクラッシュしない(#3)
  4. チャンネルタップ→「接続中…」→映像+音声が再生される
  5. 再生中にサーバー側KonomiTVを止める→失敗表示で止まる(無限再接続しない/#4)
  6. 設定で画質を変える→次回再生がその画質で要求される

- [ ] **Step 1: README/INSTALL-NOMAC更新**
- [ ] **Step 2: push → CI緑 → IPA artifactをAltStoreで実機インストール→上記チェックリスト実施**(結果をユーザーに報告してもらう)
- [ ] **Step 3: Commit**

```bash
git add README.md INSTALL-NOMAC.txt
git commit -m "v2: docs for standalone watch app"
```
