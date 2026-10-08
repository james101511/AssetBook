# AssetBook 資產簿

把「每週在試算表新增一欄、手動 key 數字」的流程，改成原生的 iOS / iPadOS / macOS App（SwiftUI）。

## 從試算表到 App 的對應

| 試算表 | App |
| --- | --- |
| 每一欄（9/12、9/19…） | 一筆 **快照（Snapshot）**，在「歷史紀錄」 |
| 每一列（各銀行、券商、交易所） | 一個 **帳戶（Account）**，依分類分組 |
| cro price、BTC price、美金、日幣匯率 | **市場報價（Quote）**，每次更新時一起填 |
| total cro usd = 數量 × 價格 | 帳戶設定為「持有數量」，App 自動相乘 |
| 各種 Total、總台幣 | 全部自動計算，不必再寫公式 |
| 信用卡費（負數） | 「負債」分類，輸入正數，自動扣除 |

## 主要畫面

- **總覽**：淨資產＋與上次比較、距離上次更新幾天（超過 7 天會提醒）、淨值／分類趨勢圖（可點選資料點）、資產配置圓環圖、本期變動最大的帳戶、幣別分布、報價變化。
- **帳戶**：依分類分組，每列顯示台幣價值、原幣金額與本期漲跌；點進去有該帳戶的歷史圖表。
- **歷史紀錄**：每次更新一列，點進去可看當時的完整明細與報價。
- **更新資產**（⌘U）：取代「新增一欄」。所有欄位預先帶入上次的數字，只改有變動的；Return 跳下一格、改過的欄位有藍點與漲跌％、可一鍵還原，下方即時顯示更新後的淨資產。

其他細節：隱藏金額（⇧⌘H，適合公共場合）、紅漲綠跌／綠漲紅跌可切換、iPhone 用底部分頁，iPad 與 Mac 自動變成側邊欄。

## 在 Xcode 執行（iOS + macOS）

1. 安裝 Xcode 16 以上。
2. File › New › Project › **Multiplatform › App**，名稱 `AssetBook`。
3. 刪除 Xcode 產生的 `ContentView.swift` 與 `AssetBookApp.swift`。
4. 把 `Sources/AssetBook/` 裡所有 `.swift` 拖進專案（勾選 Copy items）。
5. Deployment target 設為 iOS 18 / macOS 15，選 iPhone 模擬器或 My Mac 執行。


## 安裝成 Mac App（不需要 Xcode）

```bash
./build-app.sh
```

會編譯、打包成 `AssetBook.app`、做本機簽章，安裝到「應用程式」並打開。之後就從 Launchpad / Spotlight 開啟，改完程式碼再跑一次即可更新。只想產生 App 不安裝：`./build-app.sh --no-install`（輸出在 `build/`）。

腳本會自動處理部分 Command Line Tools 版本的 `redefinition of module 'SwiftBridging'` 錯誤。

圖示由 `scripts/make-icon.swift` 產生，存成 `Resources/AppIcon.icns`。

## 即時估值與持股

- **總覽預設顯示「即時」**：最新紀錄的餘額與持有數量 × 現在的匯率、幣價、股價。每 5 分鐘自動更新，並拆解變化來源（股價／幣價／匯率）。切到「紀錄」可看當時存下的數字。即時估值只用來看，不會自動存檔。
- **股票帳戶可改成「持股明細」**：記錄每檔代號與股數，市值自動計算；只有買賣時才需要改股數。到「帳戶」編輯股票帳戶即可切換，過去的紀錄不受影響。
- **股價來源**：Yahoo Finance 為主（台股、美股、ETF）。Yahoo 拒絕連線時（例如回傳 429），10 分鐘內自動改用證交所即時資訊（台股上市、上櫃）與 CNBC（美股）。搜尋支援代號與中文名稱（證交所／櫃買中心名錄）。
- 每筆紀錄會一起存下當時的持股與股價，歷史數字不會因之後股價變動而改變。

## 資料存在哪裡

所有變更自動存到 JSON 檔，不需要按儲存：

- 資料：`~/Library/Application Support/AssetBook/data.json`
- 備份：同資料夾的 `backups/`，每次存檔前保留舊版，最多 30 份
- 第一次開啟時會載入虛構的示範資料，可直接修改或刪除帳戶
- 檔案若損壞，會改名為 `data.broken-….json` 保留，不會被覆蓋
- 選單「檔案 › 匯出備份／匯入備份」（⇧⌘E）可手動備份或搬到別台電腦；「在 Finder 中顯示資料檔」可直接打開資料夾

測試時可用環境變數 `ASSETBOOK_DATA_DIR` 指定其他資料夾，避免動到真實資料。

## 下一步

- 上 iPhone 後改用 SwiftData + iCloud 同步（可匯入現在的 JSON）。
- 自動抓取匯率與 BTC / CRO 價格，只需填數量與餘額。
- 匯入原本試算表的 CSV。
- 桌面小工具（Widget）顯示淨資產。
