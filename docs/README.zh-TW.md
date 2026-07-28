<p align="center">
  <img src="../assets_app_icon_128.png" width="112" height="112" alt="Perfect Collage app icon">
</p>

# 🎬 Perfect Collage

> 快速、直覺的 macOS 圖片與影片拼貼工具。

[English README](../README.md)

Perfect Collage 適合製作比較畫面、社群貼文、多鏡頭畫面與簡單 montage。把素材放進格子、確認 Preview，接著直接輸出，不需要操作複雜的影片時間軸。

## ✨ 主要功能

- 一次加入多張圖片與多段影片，也支援拖拉匯入。
- 自訂拼貼格數與素材順序，或交給 Auto Layout 快速排版。
- 編輯 clip label，並調整位置、大小、padding 與視覺樣式。
- 多段影片可一起播放，也可選擇依序播放。
- 自訂比例、解析度、邊框、圓角、顏色、音訊與輸出長度。
- 全部為圖片時輸出 `JPG`；包含影片時輸出 `MP4`。
- 查看最近匯出紀錄，快速開啟檔案或在 Finder 中顯示。
- 可重設單一設定區，或使用 **Reset All** 全部重新開始。

## 🚀 快速上手

1. 點擊 **Add Media**，或直接把素材拖進 app。
2. 選擇格數與輸出比例。
3. 在 Preview 排列素材並設定 labels。
4. 選擇 **Together** 或 **One by one**，再調整音訊與長度。
5. 點擊 **Export JPG** 或 **Export MP4**。

## 📦 支援格式

- 影片：`mp4`、`mov`、`m4v`、`avi`、`mkv`、`webm`
- 圖片：`jpg`、`jpeg`、`png`、`webp`、`heic`、`heif`

實際可用格式仍可能受到 macOS 系統編解碼器影響。

## 🛠 本機開發

需要 macOS、Flutter 與 Xcode。

```bash
flutter pub get
flutter run -d macos
```

執行檢查：

```bash
flutter analyze
flutter test
```

建置 macOS app：

```bash
flutter build macos
```

打包與發布方式請參考 [Release 說明](releasing.md)。

## 🎯 產品定位

Perfect Collage 是專注於拼貼工作流的工具，不是完整的時間軸影片剪輯器。它要解決的事情很簡單：快速排列多個素材、清楚預覽，然後輸出成品。
