## LINE Mini App 導入方案（MVP）

### 目標
在不破壞既有 Web 版本的前提下，為專案新增 LINE Mini App（LIFF）可用路徑，優先打通「登入、搜尋、預約、結帳」主流程。

### 策略
- 採用 Hybrid：LIFF + Web 雙軌。
- LIFF 先覆蓋 client/driver 核心流程。
- admin 後台先保留 Web，不在 MVP 納入 LIFF。

### 範圍（MVP）
- 進入 LIFF 後可自動登入（或靜默登入導流）。
- 可完成搜尋行程、建立預約、進入結帳。
- 保持既有 RLS 與權限模型不退化。
- 地圖與定位在 webview 中可運作（含失敗 fallback）。

### 不在本輪範圍
- admin 功能 LIFF 化。
- LINE Pay 原生整合（先保留既有支付流程並驗證回流）。
- driver 進階即時追蹤功能擴充。

### 實作步驟
1. 啟動層加入 LIFF 環境偵測與初始化。
2. 擴充認證 store，新增 LINE 登入分支並保留既有帳密流程。
3. 調整登入頁：LIFF 環境自動導流，非 LIFF 維持原流程。
4. 新增資料庫 migration：profiles 增加 line_user_id、auth_method、line_linked_at 與索引。
5. 新增或擴充 Supabase Function：驗證 LINE 身分並交換為可用 session。
6. 調整路由守衛：補上 LIFF 首次進入導轉策略。
7. 地圖與定位相容補強：OSM 優先、定位失敗可手動選點。
8. 驗證支付在 webview 的重導與回流行為。
9. 執行 E2E 驗證：開啟 LIFF → 登入 → 搜尋 → 預約 → 結帳。

### 風險與對策
- 定位權限被拒：提供手動地點輸入 fallback。
- 支付重導割裂：先確保可回流，再評估導入 LINE Pay。
- WebView 限制：避免依賴 window.open，改用可回流策略。

### 驗證清單
- LIFF 中可成功建立有效 session。
- 受保護路由導轉與放行正確。
- 一條完整預約支付主流程可完成。
- RLS 與資料可見性不退化。
- 地圖/定位在允許與拒絕兩種情境都可使用。

### 時程建議
- Phase 1（MVP）：2 到 3 週
- Phase 2（擴展）：4 到 6 週（視是否導入 LINE Pay 與 LIFF 推播）

### 交付成果
- LIFF MVP 可運行版本
- DB migration 與 function 變更
- 測試報告（登入、搜尋、預約、支付、RLS）
