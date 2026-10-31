# LINE Login + LINE Mini App 整合計畫清單（Unified）

更新日期：2026-10-31  
適用專案：vue-booking（Vue 3 + Vite + Supabase）  
整合目標：在不破壞既有 Web 的前提下，完成 LINE Login（Web OAuth）與 LIFF（LINE Mini App）MVP 主流程。

---

## 1. 目標與成功條件

- 保留既有 email/password 流程，不替換現有登入。
- 新增 LINE Login（Web OAuth）作為增量登入方式。
- 新增 LIFF 自動登入能力，打通 MVP 主流程：登入 -> 搜尋 -> 預約 -> 結帳。
- 維持既有 RLS 與角色/權限模型不退化。
- 地圖與定位在 WebView 可用，失敗時有 fallback。

成功條件（Definition of Done）：
- 在一般瀏覽器可用 LINE 按鈕登入並建立有效 session。
- 在 LIFF 環境可自動登入或靜默導流後登入成功。
- 受保護路由導轉正確，既有登入/註冊/忘記密碼不退化。
- 完整走通一次：開啟 LIFF -> 登入 -> 搜尋 -> 預約 -> 結帳。

---

## 2. 範圍與非範圍

### 2.1 本輪範圍（MVP）

- LINE Login（OAuth）前後端整合。
- LIFF 環境偵測、初始化、token 交換 session。
- Login 頁導流與 callback 路由。
- profiles 欄位擴充與索引（line_user_id/auth_provider/line_linked_at）。
- 支付回流在 WebView 的可用性驗證。

### 2.2 不在本輪範圍

- admin 功能 LIFF 化。
- LINE Pay 原生整合。
- driver 進階即時追蹤擴充。

---

## 3. 先決條件（Blocking）

- [ ] 已有 LINE Login Channel，且可設定 Callback URL。
- [ ] 已建立 LIFF App 並取得 LIFF ID。
- [ ] Edge Function secrets 已設定：`supabase secrets set LINE_CHANNEL_ID=... LINE_CHANNEL_SECRET=...`（方案 B；Supabase 內建 SDK 不支援 LINE provider，已不適用「啟用 LINE Provider」）。
- [ ] 已執行 migration 0021_line_auth.sql，並部署 `supabase functions deploy line-auth`。
- [ ] LINE Login Channel 的 Callback URL 已包含 `<站點>/auth/line-callback`（含 localhost:5173）。
- [ ] 決策確認：LINE 登入預設角色為 client。

---

## 4. 實作清單（依賴順序）

## Phase 0 - 版本與來源管理

- [ ] 建立分支：feat/line-login-liff-mvp。
- [ ] 將外部 skill 倉庫引入專案子目錄（建議 external/line-api-skill）。
- [ ] 固定外部 skill 版本，記錄來源與更新策略。
- [ ] 確認 external 內含 line-login 規格與簽章/驗證工具。

交付物：
- external/line-api-skill（可追蹤來源）
- 文件註記外部版本

## Phase 1 - 環境變數與設定

- [ ] 更新 .env.example 新增：VITE_LINE_CHANNEL_ID、VITE_LIFF_ID。
- [ ] 規範 secret 僅放後端（不得進 VITE_）。
- [ ] 定義 redirect URI（Web OAuth callback + LIFF endpoint）。
- [ ] 校驗 LINE Console 與 Supabase Dashboard 設定一致。

交付物：
- .env.example 更新
- 設定檢查清單

## Phase 2 - 前端登入入口與路由

- [ ] 在 src/features/auth/LoginPage.vue 新增「使用 LINE 登入」按鈕。
- [ ] 非 LIFF 環境維持既有登入流程。
- [ ] 新增 callback 路由（建議 /auth/line-callback）。
- [ ] 新增 callback 頁元件：解析 code/state，呼叫後端交換 token，處理成功/失敗導頁。
- [ ] 調整路由守衛：補 LIFF 首次進入導轉策略。

交付物：
- Login 頁 + callback 路由 + callback 頁

## Phase 3 - LIFF 啟動層與初始化

- [ ] 新增 LIFF service（環境偵測、init、isLoggedIn、getIDToken）。
- [ ] 在 app 啟動層（main.ts 或 App 啟動流程）加入 LIFF 初始化。
- [ ] LIFF 未登入時執行登入導流；已登入時走 token 交換。
- [ ] 防止重複初始化與重入。

交付物：
- LIFF 初始化模組與啟動串接

## Phase 4 - 後端 token 交換與驗證

- [ ] 新增或擴充 Supabase Function（建議 liff-auth / line-callback handler）。
- [ ] 驗證 LINE ID Token/簽章（重用 external/line-api-skill 方法）。
- [ ] 首次登入建立本地資料，後續登入綁定既有帳戶策略。
- [ ] 回傳前端可用 session token（access/refresh）或等價授權資訊。
- [ ] 加入錯誤碼與訊息映射（供前端顯示）。

交付物：
- supabase/functions 內相關 function
- 驗證與錯誤映射規格

## Phase 5 - 資料庫 migration

- [ ] 新增 migration（例如 0021_line_auth.sql）。
- [ ] profiles 新增：line_user_id、auth_provider、line_linked_at。
- [ ] 建立 line_user_id 條件索引。
- [ ] 補上欄位用途註解與資料一致性約束。

交付物：
- supabase/migrations/0021_line_auth.sql

## Phase 6 - Auth Store 與狀態一致性

- [ ] 在 src/stores/auth.ts 新增 signInWithLine（Web OAuth）。
- [ ] 新增 signInWithLiff（setSession 或等價流程）。
- [ ] 重用 init/loadProfile，確保 user/session/profile/role 一致。
- [ ] 將 LINE 錯誤映射到既有 AppError 體系。

交付物：
- auth store 擴充完成
- 錯誤流程與 UI 顯示一致

## Phase 7 - 地圖定位與支付回流相容

- [ ] WebView 定位拒絕時提供手動選點 fallback。
- [ ] 地圖策略以 OSM 優先，必要時降級方案可用。
- [ ] 驗證支付重導與回流，避免依賴 window.open。
- [ ] 驗證回流後 session 與路由狀態正確。

交付物：
- 相容性處理與驗證紀錄

## Phase 8 - 測試、回歸、文件

- [ ] 單元測試：callback 參數解析、state 驗證、導頁邏輯。
- [ ] 整合測試：token 交換成功、無效/過期 token 拒絕。
- [ ] 回歸測試：email/password、註冊、忘記/重設密碼。
- [ ] E2E：LIFF -> 登入 -> 搜尋 -> 預約 -> 結帳。
- [ ] 更新 README/部署文件與 troubleshooting。

交付物：
- 測試報告（登入、搜尋、預約、支付、RLS）
- 維運手冊（設定、排錯、升版）

---

## 5. 關鍵檔案清單

- src/features/auth/LoginPage.vue
- src/router/index.ts
- src/stores/auth.ts
- src/types/errors.ts
- src/main.ts（或等效啟動層）
- src/services/liff/index.ts（新增）
- .env.example
- supabase/functions（新增/擴充 line callback, liff-auth）
- supabase/migrations/0021_line_auth.sql（新增）
- external/line-api-skill（外部 skill 來源）

---

## 6. 風險與對策

- 定位權限被拒：提供手動地點輸入與預設區域。
- 支付回流割裂：先保證可回流再談原生 LINE Pay。
- WebView 限制：避免 window.open，改同頁導轉與可回流 URL。
- 帳號重複風險：採 email/sub 綁定策略與人工合併預案。
- state/CSRF 風險：state 存 sessionStorage，callback 嚴格校驗。

---

## 7. 驗證清單（最終驗收）

- [ ] LINE OAuth（Web）可建立有效 session。
- [ ] LIFF 可完成自動登入或靜默導流後登入。
- [ ] 受保護路由放行與攔截正確。
- [ ] 主流程可完成：登入 -> 搜尋 -> 預約 -> 結帳。
- [ ] RLS 與資料可見性無退化。
- [ ] 地圖/定位在允許與拒絕情境都可使用。

---

## 8. 時程建議

- Phase 1（MVP）：2 到 3 週
- Phase 2（擴展，視需求）：4 到 6 週

---

## 9. 決策紀錄（固定）

- 在現有專案內整合，不另開工作區。
- 保留既有 auth 流程，LINE 為增量登入方式。
- Admin 暫不納入 LIFF。
- 外部 skill 先固定版本，里程碑再同步上游。