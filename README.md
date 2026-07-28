# Perfect Collage

`Perfect Collage` 是一套用來快速製作多格拼貼的 macOS 桌面工具。  
它同時支援 `photo` 與 `video`，可輸出成圖片拼貼或影片拼貼，適合做比較畫面、素材排列、社群內容與多段影片展示。

## 產品重點

- 支援 `photo` and `video`，可製作圖片或影片的 collage。
- 支援 `label`，做 compare、before/after 或多素材對照時可直接標記。
- 多個 video 可同時播放，也可接續播放。

## 功能總覽

- 支援匯入多段影片與照片，並可輸出成 `MP4` 或 `JPG`。
- 支援拖拉匯入，整個 app 視窗都可接收檔案。
- 可將媒體切換為 active / non-active，控制哪些內容進入拼貼。
- 可直接拖曳調整 Preview 格子的內容順序。
- 單一檔案拖到指定格子時，會直接 replace 該格內容。
- 可設定畫面比例、列數、欄數、邊框、圓角、背景色、邊框色。
- 可顯示 clip label，並調整字級與是否顯示編號，方便 compare 與標記。
- 內建 Preview 播放控制: play / pause / reset。
- 會顯示目前播放進度 `current position / total position`。
- 可選擇 `Together` 或 `One by one` 播放模式。
- 可設定音訊模式、輸出時長規則、輸出解析度、檔名時間戳。
- 內建匯出進度、取消匯出、最近匯出紀錄、開啟最後輸出檔案。

## 適用情境

- 短影音拼貼
- 多鏡頭同時播放畫面
- 多張照片排版輸出
- 社群直式、方形、橫式內容製作
- 快速做比較畫面、before/after、素材排列稿

## 支援格式

選檔匯入支援:

- 影片: `mp4`, `mov`, `m4v`, `avi`, `mkv`, `webm`
- 圖片: `jpg`, `jpeg`, `png`, `webp`, `heic`, `heif`

拖拉匯入支援常見影片與圖片格式；若個別格式在系統解碼或拖拉流程中無法預覽，仍建議優先使用 `Add Media` 選檔匯入測試。

## 介面結構

畫面主要分成兩區:

- 左側控制面板
  - `Media`
  - `Layout`
  - `Output`
- 右側預覽區
  - `Preview`
  - `Auto Layout`
  - 播放控制與進度顯示
  - 拼貼格子預覽

## 基本使用流程

1. 按 `Add Media`，或直接把檔案拖進 app。
2. 在 `Media` 區確認素材列表。
3. 點擊 media item，決定它是否要成為 active 素材。
4. 在 `Layout` 區調整畫面比例、格數與樣式。
5. 在右側 `Preview` 檢查排列結果，必要時拖曳交換格子內容。
6. 在 `Output` 區設定播放模式、音訊、時長與解析度。
7. 按 `Export` 輸出成影片或圖片。

## Media 區功能

### Add Media

- 可一次加入多個影片或圖片。
- 新加入的素材會進入媒體列表，並依可用空格自動加入 Preview。

### 點擊 item 切換 active 狀態

- 當 item 已經是 active:
  - 再點一次會切回 non-active，並從 Preview 移除。
- 當 item 是 non-active:
  - 如果 Preview 還有空格，會加入成 active。
  - 如果沒有空格，會顯示 toast 提示已滿。

active 數量上限由目前 grid 容量決定，也就是 `rows × columns`。

### 編輯 clip label

- 每個 media item 的標題右邊都有 edit icon。
- 點下去會開啟 `Edit clip label`。
- 你可以修改輸出與預覽上顯示的片段名稱。

### 移除單一素材

- 每個 media item 右邊都有刪除按鈕。
- 刪除後會同步從媒體列表與 Preview 移除。

### Reset media

- `Reset media` 會清空目前所有載入素材與 Preview 指派。
- 執行前會先跳出 confirm dialog，避免誤清除。

### 拖拉匯入規則

- 整個 app 都可以接收外部拖進來的檔案，不只 Preview 區。
- 如果拖入多個檔案:
  - 會依順序加入可用位置。
- 如果只拖入一個檔案，且落點在指定格子上:
  - 會直接 replace 那一格。
- 如果拖入位置不在特定格子上:
  - 會當成一般新增素材處理。

## Preview 區功能

### Auto Layout

- `Auto Layout` 會根據目前 active 素材，自動安排 Preview 格子。
- 適合快速重整版面，避免手動逐格調整。

### 播放控制

Preview 區有兩顆按鈕:

- `Play / Pause`
  - 同一顆按鈕切換播放與暫停。
  - `Pause` 會停在目前 `current position`。
  - 再按 `Play` 會從暫停位置繼續 resume。
- `Reset`
  - 作用是回到開頭，相當於 seek to start。
  - 只有不在開頭時才會 enable。

### 播放進度顯示

- 右上方會顯示 `current position / total position`。
- 播放時狀態每秒更新一次。
- 方便你確認目前播放到哪裡，以及總長度是多少。

### Preview 播放模式

#### Together

- 所有 active 影片會一起從頭開始播放。
- 結束條件由 `Duration` 設定決定:
  - `Longest clip`
  - `Shortest clip`
- 播放結束後，狀態會自動回到 stop。

#### One by one

- 影片會依序一段一段播放。
- 總長度為所有 active 影片時長總和。
- 播放結束後，狀態也會自動回到 stop。

### Preview 拖曳排序

- 可直接把一格拖到另一格。
- 如果目標格已有內容，會進行交換。
- 適合快速調整每個素材在拼貼中的位置。

### 照片預覽說明

- 如果 active 素材全部都是照片，Preview 不會有動態播放。
- 這種情況下仍然可以正常輸出。

## Layout 區功能

### Aspect Ratio

內建比例:

- `9:21`
- `9:16`
- `4:5`
- `3:4`
- `1:1`
- `5:4`
- `4:3`
- `16:9`
- `21:9`

### Rows / Columns

- 可調整拼貼列數與欄數。
- Grid 容量會跟著改變。
- active 素材可放入的上限也會同步改變。

### Border Thickness

- 調整每格之間的邊框粗細。

### Tile Corner Radius

- 調整每格畫面的圓角程度。

### Clip Label Font Size

- 調整片段標籤字級。

### Border Color / Background Color

- 可設定拼貼邊框色與背景色。

### Show clip labels

- 控制輸出與預覽是否顯示片段名稱。

### Show label index

- 控制 label 前面是否加上編號。

### Reset layout defaults

- 將 Layout 區所有設定還原成預設值。

## Output 區功能

### Play mode

可選:

- `Together`
- `One by one`

這個設定會影響 Preview 播放方式，也會影響最終匯出邏輯。

### Audio

在 `Together` 模式下可設定音訊規則:

- `First clip audio`
- `Mix all audios`
- `Longest clip audio`
- `Mute`

### Duration

在 `Together` 模式下可設定輸出長度規則:

- `Longest clip`
- `Shortest clip`

### Resolution

內建解析度預設:

- `HD 720`
- `Full HD 1080`
- `2K 1440`
- `4K 2160`

也可以直接調整輸出寬高。

### Add datetime to filename

- 開啟後，輸出檔名會自動附加日期時間，方便版本管理。

### Reset output defaults

- 將 Output 區設定還原為預設值。

## 匯出規則

### 會輸出哪些素材

- 只有 active 素材會進入輸出。
- non-active 素材只會留在媒體列表，不會出現在成品裡。

### 匯出格式判斷

- 如果 active 素材全部都是照片:
  - 匯出為 `JPG`
- 只要 active 素材中包含任一影片:
  - 匯出為 `MP4`

### Together 模式的輸出長度

- `Longest clip`: 以最長的 active clip 當輸出總長。
- `Shortest clip`: 以最短的 active clip 當輸出總長。

### One by one 模式的輸出長度

- 依序播放所有 active 影片。
- 總長度為各段影片時長相加。

### 匯出過程

- 匯出時會顯示進度百分比與處理時間。
- 匯出中可取消。
- 匯出完成後可直接開啟檔案或資料夾。

### Recent Exports / Open Last Export

- 可查看最近匯出紀錄。
- 可快速重新開啟最後一次輸出的檔案。

## 狀態列

- app 會在底部顯示目前狀態訊息。
- 包含載入、播放、匯出、錯誤與完成等狀態。
- 點擊狀態文字可複製目前訊息到剪貼簿。

## 使用建議

- 先決定輸出比例，再安排 rows / columns，會比較不容易反覆調整。
- 如果想快速對齊版面，先用 `Auto Layout`，再手動拖曳微調。
- 如果只想替換某個格子，直接把單一檔案拖到那個格子上即可。
- 如果要做靜態拼圖，全部使用照片即可，系統會直接輸出 `JPG`。
- 如果想做多段影片同步比較，請使用 `Together`。
- 如果想做依序播放的 montage，請使用 `One by one`。

## 常見情況

### 點 non-active item 沒反應

通常代表目前 grid 已滿。  
這時候 app 會顯示提示，請先:

- 把某些 active item 切回 non-active
- 或增加 rows / columns

### Preview 不能播放

如果目前 active 內容全部都是照片，Preview 不提供動態播放，這是正常行為。  
你仍然可以正常輸出成圖片。

### 某素材預覽失敗

如果個別素材解碼失敗，Preview 可能顯示失敗訊息；但在某些情況下仍可嘗試匯出。  
建議優先確認素材格式、編碼與檔案是否完整。

## 本機開發與執行

這個專案使用 Flutter 建置，目前目標平台為 macOS。

### 環境需求

- Flutter SDK
- Xcode
- macOS 開發環境

### 安裝依賴

```bash
flutter pub get
```

### 執行 app

```bash
flutter run -d macos
```

### 建置 macOS 版本

```bash
flutter build macos
```

## Release 流程

專案已包含 GitHub Release 自動打包流程。

- 當你在 GitHub 發布一個新的 Release 時，GitHub Actions 會自動:
  - 驗證 release tag 是否對應 `pubspec.yaml` 版本
  - 建置 macOS release app
  - 打包成 `.dmg`
  - 產生 `.sha256`
  - 上傳回該 GitHub Release 當成 asset

本機也可直接產生 release 檔案:

```bash
./scripts/build_release_artifacts.sh
```

若要直接在本機從指定 tag 建置並上傳 GitHub Release:

```bash
./scripts/release_macos.sh v1.3.0
```

更完整的 release 說明請看 [docs/releasing.md](/Users/rdapp/git/video_collage/docs/releasing.md)。

## 專案定位

`Perfect Collage` 適合做為一個快速、直覺、可視化的拼貼編輯工具。  
它不是時間軸型的完整剪輯軟體，而是偏向「把多個素材放進統一版面，快速預覽並輸出」的工作流。
