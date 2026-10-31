# AssetBook 資產簿

**English** · [繁體中文](#assetbook-資產簿-繁體中文)

A native Mac app that replaces the "add a new column to a spreadsheet every week" routine. Log your bank accounts, stocks, crypto and credit cards, let the app fill in exchange rates and prices, and watch your net worth over time. Everything is stored on your own computer: no account, no upload.

> There is also SwiftUI code for iPhone / iPad. It needs Xcode to build; see the bottom of this page.

## Install (Mac, about 3 minutes)

Requires **macOS 15 (Sequoia) or later**. You don't need Xcode, only Apple's command line tools.

**1. Install the command line tools** (if already installed it says so; skip to the next step)

```bash
xcode-select --install
```

**2. Download and install**

```bash
git clone https://github.com/james101511/AssetBook.git
cd AssetBook
./build-app.sh
```

After about a minute the app is installed in Applications and opens automatically. Later you can launch it from Launchpad or Spotlight (search "資產簿"). The first launch has a set of fictional sample data you can edit or delete.

> This repository is currently private. Ask the author to add you as a collaborator and sign in with `gh auth login` before cloning.

**Update to a new version**

```bash
cd AssetBook
git pull
./build-app.sh
```

Your data is not affected.

### If someone sent you a .zip

Unzip it and drag `AssetBook.app` into Applications. **The first time, right-click › Open** (don't double-click), then click Open again. The app isn't signed with a paid Apple developer certificate, so macOS blocks a normal launch.

If it still won't open, run this in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/AssetBook.app
```

To package a copy for a friend: `./build-app.sh --zip` writes `build/AssetBook.zip`.

## First use

1. Under **Accounts** in the sidebar, create your accounts with the ＋ button at top right and pick a category (cash & deposits, stocks, crypto, liabilities).
   - Banks and exchanges: enter the balance.
   - Crypto: enter the quantity held; the app multiplies by the coin price.
   - Stocks: choose "holdings", enter ticker and shares; market value follows live prices.
   - Credit cards: put them under liabilities and enter the amount due each time.
2. Press **Update** (⌘U) to record your first set of numbers. Exchange rates, coin prices and stock prices are filled in automatically; other fields are prefilled with last time's numbers, so change only what moved.
3. Repeat step 2 each week and the overview, history and category pages grow their trend lines.

Accounts in the sample data can be edited, archived or deleted.

## Features

- **Overview**: net worth (shown "live" by default: latest record × current exchange rates, coin prices and stock prices), a scrubbable trend chart (7 days / 1 month / 3 months / 1 year / all), an animated allocation donut (by category or currency), exchange rates, coin prices and current stock prices.
- **History**: a calendar view showing net worth and change on each recorded day; click a day for the full breakdown. You can also switch to a list.
- **Auto-record**: if you open the app on a day without a manual record, it saves a valuation point for that day (latest manual record × live prices). It appears as a faint dot on the chart and a faint "自動" (auto) cell on the calendar. A manual record on the same day replaces it, and it never affects comparisons or exports. Turn it off or clear it under Settings › Quotes.
- **Accounts**: browse by category. Cash & deposits is split into bank deposits, exchanges & stablecoins, and cash & stored value; stocks expand into Taiwan and US holdings; every account has its own history chart.
- **Update** (⌘U): replaces "add a column" in the spreadsheet, and you can add accounts while updating.
- **Export to spreadsheet**: export all records as CSV or copy to the clipboard and paste into Google Sheets. Dates run across columns, items go down, with subtotals and totals.
- **Settings**: appearance (auto / light / dark), red-up/green-down or green-up/red-down, hide amounts (⇧⌘H, handy in public), backup and import.

## Data and privacy

- Data: `~/Library/Application Support/AssetBook/data.json`, saved automatically on every change.
- Backups: the `backups/` folder next to it keeps the previous version before each save, up to 30.
- Moving: File › Export backup / Import backup (⇧⌘E) lets you back up by hand or move to another computer.
- A damaged file is renamed to `data.broken-….json` and kept, never overwritten.
- The app only fetches public quotes from the internet and sends no personal data.
- Uninstall: drag `/Applications/AssetBook.app` to the Trash. Your data lives in the folder above; delete that too if you want it gone.

## Quote sources

| Item | Primary source | Fallback |
| --- | --- | --- |
| Exchange rates (USD, JPY) | Yahoo Finance (intraday) | ExchangeRate-API (daily) |
| Crypto (BTC, CRO) | Yahoo Finance | CoinGecko (free tier is easily rate limited) |
| Stocks (Taiwan, US, ETFs) | Yahoo Finance | TWSE (Taiwan), CNBC (US) |

When Yahoo rate limits, the app switches to the fallback for 10 minutes. Stock search works with tickers and Chinese names. Each record stores the holdings and stock prices at that time, so historical numbers don't change when prices move later.

## FAQ

**"Can't be opened because the developer cannot be verified"**: see "If someone sent you a .zip" above; right-click › Open.

**`./build-app.sh` says it can't find the Swift compiler**: run `xcode-select --install` and retry.

**`redefinition of module 'SwiftBridging'` while building**: the script handles this automatically; if it still appears, update the command line tools.

**Exchange rates or stock prices don't show**: check your connection. Sources are occasionally rate limited; wait a few minutes and press Refresh at the top right of the overview.

## For developers

```
Sources/AssetBook/
  AssetBookApp.swift    entry point, Mac sidebar / iPhone tabs, settings
  PortfolioStore.swift  data and calculations (@Observable)
  Models.swift          accounts, records, quotes
  Persistence.swift     JSON storage, backups
  QuoteService.swift    exchange rates, crypto
  StockService.swift    stock prices (Yahoo, TWSE, CNBC)
  DashboardView.swift   overview
  HistoryView.swift     history (calendar)
  AccountsView.swift    accounts pages and editor
  UpdateSheet.swift     update
  SheetExport.swift     spreadsheet export
```

- The icon is generated by `scripts/make-icon.swift` into `Resources/AppIcon.icns`.
- Set the `ASSETBOOK_DATA_DIR` environment variable to use another data folder when testing, so your real data stays untouched.
- `swift run` gives a quick preview on a Mac.

### Build in Xcode (iOS + macOS)

1. Install Xcode 16 or later.
2. File › New › Project › **Multiplatform › App**, named `AssetBook`.
3. Delete the generated `ContentView.swift` and `AssetBookApp.swift`.
4. Drag all `.swift` files in `Sources/AssetBook/` into the project (check Copy items).
5. Set the deployment target to iOS 18 / macOS 15, then run on an iPhone simulator or My Mac.

## Ideas for later

- iCloud sync for iPhone (SwiftData).
- Import the CSV from your old spreadsheet.
- A desktop widget showing net worth.

---

## AssetBook 資產簿 (繁體中文)

把「每週在試算表新增一欄、手動 key 數字」的流程，換成一個原生的 Mac App：記下每週的銀行、股票、加密貨幣與信用卡，自動帶入匯率和股價，看淨資產怎麼變化。資料全部存在你自己的電腦上，沒有帳號、不上傳。

> 另外也有 iPhone / iPad 版本的程式碼（SwiftUI），需要用 Xcode 建置，見最下面。

## 安裝（Mac，約 3 分鐘）

需要 **macOS 15 (Sequoia) 以上**。不需要安裝 Xcode，只要有 Apple 的命令列工具。

**1. 安裝命令列工具**（如果已經裝過會顯示「已安裝」，直接跳下一步）

```bash
xcode-select --install
```

**2. 下載並安裝**

```bash
git clone https://github.com/james101511/AssetBook.git
cd AssetBook
./build-app.sh
```

大約一分鐘後，App 會安裝到「應用程式」並自動打開，之後可以從 Launchpad 或 Spotlight 搜尋「資產簿」開啟。第一次打開會有一組虛構的示範資料，可以直接修改或刪除。

> 這個專案目前是私人儲存庫，要先請作者把你加為協作者，並用 GitHub 帳號登入（`gh auth login`）後才能 clone。

**更新到新版**

```bash
cd AssetBook
git pull
./build-app.sh
```

你的資料不會受影響。

### 拿到 .zip 的人

如果有人直接傳 `AssetBook.zip` 給你：解壓縮後把 `AssetBook.app` 拖進「應用程式」，**第一次要按右鍵 › 打開**（不是直接點兩下），再按一次「打開」。這是因為 App 沒有付費的 Apple 開發者簽章，macOS 會擋下來。

如果還是打不開，在終端機執行：

```bash
xattr -dr com.apple.quarantine /Applications/AssetBook.app
```

想自己打包一份給朋友：`./build-app.sh --zip`，會輸出 `build/AssetBook.zip`。

## 第一次使用

1. 左邊的 **帳戶** 先建立你的帳戶：按右上角的 ＋，選分類（現金與存款、股票、加密貨幣、負債）。
   - 銀行、交易所：輸入餘額。
   - 加密貨幣：輸入持有數量，App 自動乘上幣價。
   - 股票：選「持股明細」，輸入股票代號與股數，市值會依即時股價計算。
   - 信用卡：放在「負債」，每次輸入本期應繳金額。
2. 按 **更新資產**（⌘U）記下第一筆數字。匯率、幣價與股價會自動帶入，其他欄位預先填好上次的數字，只改有變動的。
3. 之後每週重複第 2 步，總覽、歷史紀錄和分類頁就會慢慢長出走勢。

示範資料裡的帳戶可以直接編輯、封存或刪除。

## 主要功能

- **總覽**：淨資產（預設顯示「即時」：最新紀錄 × 現在的匯率、幣價、股價）、可拖曳的走勢圖（7 天 / 1 個月 / 3 個月 / 1 年 / 全部）、資產組成動畫圓餅圖（分類或幣別）、匯率、幣價與持股現價。
- **歷史紀錄**：日曆檢視，有紀錄的日子顯示當天淨資產與變動，點進去看完整明細；也可切成列表。
- **自動記錄**：當天打開 App 但還沒手動記錄時，會自動存一個當日估值點（最新手動紀錄 × 即時報價），在走勢圖和日曆上以淡色小點標示「自動」；手動記錄會取代它，不影響比較基準與匯出。可在設定 › 報價關閉或清除。
- **帳戶**：依分類查看。現金與存款分成「銀行存款」「交易所與穩定幣」「現鈔與儲值」三組；股票依台股、美股展開持股；每個帳戶有自己的歷史圖表。
- **更新資產**（⌘U）：取代試算表的「新增一欄」，可以在更新時直接新增帳戶。
- **匯出成試算表**：把所有紀錄匯出成 CSV 或複製到剪貼簿，貼到 Google 試算表，格式是日期為欄、項目往下排，並附小計與總計。
- **設定**：外觀（自動 / 淺色 / 深色）、紅漲綠跌或綠漲紅跌、隱藏金額（⇧⌘H，適合公共場合）、備份與匯入。

## 資料與隱私

- 資料：`~/Library/Application Support/AssetBook/data.json`，每次變更自動存檔。
- 備份：同資料夾的 `backups/`，每次存檔前保留舊版，最多 30 份。
- 搬家：選單「檔案 › 匯出備份／匯入備份」（⇧⌘E）可手動備份，或搬到另一台電腦。
- 檔案若損壞，會改名為 `data.broken-….json` 保留，不會被覆蓋。
- App 只會上網抓公開的報價，不會送出任何個人資料。
- 解除安裝：把 `/Applications/AssetBook.app` 丟進垃圾桶即可；資料在上面的資料夾，想一併清掉再刪那個資料夾。

## 報價來源

| 項目 | 主要來源 | 備援 |
| --- | --- | --- |
| 匯率（美元、日圓） | Yahoo Finance（盤中即時） | ExchangeRate-API（每日更新） |
| 幣價（BTC、CRO） | Yahoo Finance | CoinGecko（免費額度容易被限流） |
| 股價（台股、美股、ETF） | Yahoo Finance | 證交所（台股）、CNBC（美股） |

Yahoo 回傳限流時，10 分鐘內會自動改用備援來源。股票搜尋支援代號與中文名稱。每筆紀錄會一起存下當時的持股與股價，歷史數字不會因之後股價變動而改變。

## 常見問題

**打開時說「無法打開，因為無法確認開發者」**：見上面「拿到 .zip 的人」，右鍵 › 打開即可。

**`./build-app.sh` 顯示找不到 Swift 編譯器**：先跑 `xcode-select --install`，裝好再重試。

**編譯時出現 `redefinition of module 'SwiftBridging'`**：腳本已自動處理，若還出現請更新命令列工具。

**匯率或股價顯示不出來**：確認網路連線；偶爾來源被限流，過幾分鐘按總覽右上角的「重新整理」。

## 給開發者

```
Sources/AssetBook/
  AssetBookApp.swift    入口、Mac 側邊欄／iPhone 分頁、設定頁
  PortfolioStore.swift  資料與計算（@Observable）
  Models.swift          帳戶、紀錄、報價
  Persistence.swift     JSON 存檔、備份
  QuoteService.swift    匯率、幣價
  StockService.swift    股價（Yahoo、證交所、CNBC）
  DashboardView.swift   總覽
  HistoryView.swift     歷史紀錄（日曆）
  AccountsView.swift    帳戶頁與編輯
  UpdateSheet.swift     更新資產
  SheetExport.swift     匯出成試算表
```

- 圖示由 `scripts/make-icon.swift` 產生，存成 `Resources/AppIcon.icns`。
- 測試時可設定環境變數 `ASSETBOOK_DATA_DIR` 指定其他資料夾，避免動到真實資料。
- `swift run` 可以在 Mac 上快速預覽。

### 在 Xcode 建置（iOS + macOS）

1. 安裝 Xcode 16 以上。
2. File › New › Project › **Multiplatform › App**，名稱 `AssetBook`。
3. 刪除 Xcode 產生的 `ContentView.swift` 與 `AssetBookApp.swift`。
4. 把 `Sources/AssetBook/` 裡所有 `.swift` 拖進專案（勾選 Copy items）。
5. Deployment target 設為 iOS 18 / macOS 15，選 iPhone 模擬器或 My Mac 執行。

## 之後可能做的

- iPhone 版加上 iCloud 同步（SwiftData）。
- 匯入原本試算表的 CSV。
- 桌面小工具顯示淨資產。
