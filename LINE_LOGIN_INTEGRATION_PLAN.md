# LINE 登入 & LINE Mini App 整合計畫

**建立日期**：2026-10-26  
**適用版本**：Wassalni v1.0  
**狀態**：待實作

---

## 一、需求確認紀錄

| 問題 | 決策 |
|------|------|
| LINE Console 已有 Channel？ | ✅ 是，Channel 已建立 |
| 本地開發環境需支援 LINE 登入？ | ❌ 否，僅生產/測試環境支援 |
| LINE 用戶無 email 時的處理策略？ | ✅ 允許 email 為空，profile 照常建立 |
| LINE 登入後的角色設定？ | **一律為 `client`（乘客）**，不提供 LINE 登入升級為司機的流程 |
| 是否支援 LINE Mini App？ | ✅ 是，需同時支援 LIFF 環境 |

---

## 二、整體架構說明

本次整合分為兩層：

### 層 1：LINE Login（Web OAuth）
一般瀏覽器環境下，透過 Supabase OAuth 代理 LINE Login v2.1，讓用戶可在登入/註冊頁點擊「用 LINE 登入」完成驗證，適用於桌面瀏覽器與行動瀏覽器。

### 層 2：LINE Mini App（LIFF）
在 LINE App 內開啟的 LIFF WebView 環境，使用 LIFF SDK 取得 LINE ID Token，再透過 Supabase Edge Function 驗證並交換為 Supabase Session，實現「進入 LIFF 即自動登入」。

> **兩層共用同一套 Supabase Auth 與 RLS 機制**，僅登入取得 session 的方式不同。

---

## 三、登入流程圖

### 3-1：Web OAuth 流程（LINE Login）

```
使用者點擊「用 LINE 登入」
        │
        ▼
supabase.auth.signInWithOAuth({ provider: 'line' })
        │
        ▼
瀏覽器跳轉至 LINE 授權頁
        │
   使用者同意授權
        │
        ▼
LINE 回調至 Supabase Auth 端點
https://<project>.supabase.co/auth/v1/callback
        │
        ▼
Supabase 交換 access_token，建立/更新 auth.users
        │
        ▼
handle_new_user Trigger 自動建立 profiles (role='client')
        │
        ▼
瀏覽器跳回前端 /（或 redirect 目標）
        │
        ▼
onAuthStateChange 觸發 → loadProfile()
        │
        ▼
導向首頁
```

### 3-2：LIFF Mini App 流程

```
用戶在 LINE App 內點開 LIFF URL
        │
        ▼
前端啟動時呼叫 liff.init({ liffId })
        │
  liff.isLoggedIn() ?
    │           │
   Yes          No
    │           │
    │     liff.login() → LINE 授權
    │           │
    └─────┬─────┘
          │
          ▼
  liff.getIDToken() 取得 LINE ID Token
          │
          ▼
   POST /functions/v1/liff-auth
   { idToken, wantedRole: 'client' }  ← 一律 client
          │
          ▼
  Edge Function 驗證 ID Token
  (呼叫 LINE API: /oauth2/v2.1/verify)
          │
  找到或建立 auth.users（service role）
  填入 line_user_id、full_name、picture
          │
          ▼
  回傳 Supabase access_token + refresh_token
          │
          ▼
  前端 supabase.auth.setSession(tokens)
          │
          ▼
  onAuthStateChange → loadProfile()
          │
          ▼
  正常進入應用
```

---

## 四、後台設定步驟（手動操作，實作前請先完成）

### 4-1 LINE Developers Console

1. 進入已有的 LINE Login Channel。
2. 點選 **LINE Login** 分頁。
3. 在 **Callback URL** 欄位填入（**不需加 localhost**）：
   ```
   https://<your-project-ref>.supabase.co/auth/v1/callback
   ```
4. 若需支援 LIFF，在同一個 Channel 的 **LIFF** 分頁建立 LIFF App：
   - **Endpoint URL**：填入您的前端網址（例如 `https://wassalni.example.com`）
   - **Scope**：勾選 `profile`、`openid`、`email`
   - 記錄產生的 **LIFF ID**（格式：`1234567890-xxxxxxxx`）

### 4-2 Supabase Dashboard

1. 前往 **Authentication → Providers → LINE**：
   - 啟用（Enable）
   - 填入 **Channel ID** 與 **Channel Secret**
2. 前往 **Authentication → URL Configuration → Redirect URLs**，新增：
   ```
   https://wassalni.example.com/**
   ```
   （本地開發不需要支援，故不加 `http://localhost:5173/**`）

---

## 五、需修改/新增的檔案清單

### 5-1 環境變數

**`.env`** 與 **`.env.example`** 新增：

```dotenv
# LINE Login：啟用前端 LINE 登入按鈕（設 Channel ID 即啟用）
VITE_LINE_CHANNEL_ID=

# LINE Mini App (LIFF)：LIFF App ID（格式：1234567890-xxxxxxxx）
VITE_LIFF_ID=
```

> ⚠️ Channel Secret 絕對不能放這裡，僅存於 Supabase Dashboard Secrets。

---

### 5-2 新增：`src/services/liff/index.ts`

LIFF 環境偵測與初始化模組：

```typescript
// 負責：
// - 判斷當前是否為 LIFF 環境
// - 初始化 LIFF SDK（liff.init）
// - 提供 getIdToken()
// - 提供 isLiff() 布林值供全域使用
```

---

### 5-3 新增：`supabase/functions/liff-auth/index.ts`（Edge Function）

驗證 LINE ID Token 並交換為 Supabase Session：

```typescript
// 接收 POST { idToken: string }
// 1. 呼叫 LINE API 驗證 ID Token
// 2. 從 payload 取得 sub（LINE uid）、name、picture、email
// 3. 以 service_role 查找或建立 auth.users
// 4. 簽發 Supabase access_token + refresh_token
// 5. 回傳 tokens 給前端
```

---

### 5-4 新增資料庫 Migration：`supabase/migrations/0021_line_auth.sql`

為 `profiles` 表新增 LINE 相關欄位：

```sql
alter table public.profiles
  add column if not exists line_user_id text unique,
  add column if not exists auth_provider text not null default 'email',
  add column if not exists line_linked_at timestamptz;

create index if not exists profiles_line_user_id_idx
  on public.profiles(line_user_id)
  where line_user_id is not null;

comment on column public.profiles.auth_provider is
  'email | line_oauth | liff — 記錄首次登入方式';
comment on column public.profiles.line_user_id is
  'LINE sub（uid），LIFF 驗證後寫入';
```

---

### 5-5 修改：`src/stores/auth.ts`

新增兩個 action：

```typescript
// (A) Web OAuth — 跳轉到 LINE 授權頁
async function signInWithLine(): Promise<void> {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'line',
    options: {
      redirectTo: `${window.location.origin}/`,
      scopes: 'profile openid email',
    },
  })
  if (error) throw toAppError(error)
}

// (B) LIFF — 以 Edge Function 換取的 token 建立 session
async function signInWithLiff(accessToken: string, refreshToken: string): Promise<void> {
  loading.value = true
  try {
    const { error } = await supabase.auth.setSession({
      access_token: accessToken,
      refresh_token: refreshToken,
    })
    if (error) throw toAppError(error)
    await loadProfile()
  } finally {
    loading.value = false }
}
```

並加入 `isLineUser` computed（供 UI 判斷是否隱藏密碼修改等 email 相關功能）。

---

### 5-6 修改：`src/app/main.ts`（或 App.vue）

在應用啟動時偵測 LIFF 環境並初始化：

```typescript
import { initLiff, isLiff } from '@/services/liff'

// 若 VITE_LIFF_ID 有設定，先初始化 LIFF
if (import.meta.env.VITE_LIFF_ID) {
  await initLiff()
  if (isLiff()) {
    // 若 LIFF 未登入，觸發 liff.login()
    // 若已登入，取得 idToken → 呼叫 liff-auth Edge Function → setSession
  }
}
```

---

### 5-7 修改：`src/features/auth/LoginPage.vue`

在密碼登入表單下方加入分隔線與 LINE 按鈕：

```html
<!-- 僅在非 LIFF 環境且 VITE_LINE_CHANNEL_ID 有設定時顯示 -->
<template v-if="lineEnabled && !isLiff">
  <div class="relative my-4">
    <div class="absolute inset-0 flex items-center">
      <span class="w-full border-t border-slate-200" />
    </div>
    <div class="relative flex justify-center text-xs text-slate-400">
      {{ t('auth.orContinueWith') }}
    </div>
  </div>
  <button type="button" class="btn-line w-full" @click="signInLine">
    <LineIcon />
    {{ t('auth.loginWithLine') }}
  </button>
</template>
```

---

### 5-8 修改：`src/features/auth/RegisterPage.vue`

同 LoginPage，在「建立帳號」按鈕下方加入相同 LINE 按鈕。

> LINE OAuth 首次登入即等於用 LINE 完成註冊，role 一律為 `client`。

---

### 5-9 修改：`src/router/index.ts`

調整 `beforeEach` 路由守衛，支援 LIFF 首次進入時的等待初始化：

```typescript
router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.init()
  // LIFF 初始化期間等待（避免在 setSession 完成前就跳轉至 login）
  // ...現有邏輯不變
})
```

---

### 5-10 新增：`src/components/LineIcon.vue`

LINE 品牌 SVG 圖示元件（不依賴外部圖示庫）。

---

### 5-11 修改：`src/app/app.css`

新增 LINE 品牌按鈕樣式：

```css
.btn-line {
  @apply flex items-center justify-center gap-2
         bg-[#06C755] text-white font-semibold
         rounded-lg px-4 py-2
         hover:bg-[#05b34d] disabled:opacity-50
         transition-colors;
}
```

---

### 5-12 修改：i18n（`en.ts` / `fr.ts` / `ar.ts`）

在 `auth` 命名空間新增：

| Key | EN | FR | AR |
|-----|----|----|-----|
| `auth.loginWithLine` | `Continue with LINE` | `Continuer avec LINE` | `المتابعة عبر LINE` |
| `auth.orContinueWith` | `or continue with` | `ou continuer avec` | `أو تابع عبر` |

---

## 六、完整檔案異動摘要

```
新增：
  supabase/migrations/0021_line_auth.sql   ← profiles 加 line_user_id 等欄位
  supabase/functions/liff-auth/index.ts    ← LIFF ID Token 驗證 Edge Function
  src/services/liff/index.ts               ← LIFF SDK 初始化模組
  src/components/LineIcon.vue              ← LINE SVG 圖示

修改：
  .env                                     ← VITE_LINE_CHANNEL_ID, VITE_LIFF_ID
  .env.example                             ← 同上（含說明）
  src/stores/auth.ts                       ← signInWithLine(), signInWithLiff()
  src/app/main.ts (或 App.vue)             ← LIFF 初始化
  src/router/index.ts                      ← LIFF 等待初始化相容
  src/features/auth/LoginPage.vue          ← LINE 按鈕（非 LIFF 環境顯示）
  src/features/auth/RegisterPage.vue       ← LINE 按鈕（非 LIFF 環境顯示）
  src/app/app.css                          ← .btn-line 樣式
  src/i18n/en.ts                           ← 2 個新 key
  src/i18n/fr.ts                           ← 2 個新 key
  src/i18n/ar.ts                           ← 2 個新 key
```

---

## 七、實作順序

```
Step 1  後台設定（LINE Console Callback URL + Supabase Provider）
Step 2  .env / .env.example 加入新環境變數
Step 3  0021_line_auth.sql migration（本地 supabase db reset 驗證）
Step 4  src/services/liff/index.ts（LIFF SDK 初始化）
Step 5  supabase/functions/liff-auth/（Edge Function）
Step 6  src/stores/auth.ts（signInWithLine + signInWithLiff）
Step 7  LineIcon.vue + btn-line 樣式
Step 8  LoginPage.vue + RegisterPage.vue（LINE 按鈕）
Step 9  main.ts / App.vue（LIFF 啟動邏輯）
Step 10 router/index.ts（LIFF 相容守衛）
Step 11 i18n 三語系
Step 12 手動測試：Web OAuth 流程（LINE Login）
Step 13 手動測試：LIFF 流程（LINE Mini App）
```

---

## 八、注意事項與風險

### ⚠️ LINE 不保證回傳 email
LINE 用戶可選擇不授權 email，`auth.users.email` 可能為空字串或 null。
- **對策**：不在任何業務流程中強制要求 email 非空；UI 的「忘記密碼」功能對 `auth_provider='line'` 或 `auth_provider='liff'` 的用戶隱藏。

### ⚠️ LIFF WebView 的瀏覽器限制
- LINE 內建 WebView 不支援所有 Web API（如部分 Web Payment API）。
- 支付回調（Payment redirect）需確保能在 LIFF WebView 中回流，或導到外部瀏覽器。
- **對策**：先以既有 mock/edge 支付流程確認回流行為，再評估 LINE Pay 整合。

### ⚠️ LIFF SDK 為外部依賴
LIFF SDK（`@line/liff`）需透過 npm 安裝，會增加 bundle 體積。
- **對策**：以動態 import 方式僅在 VITE_LIFF_ID 有設定時才載入。

### ✅ RLS 安全模型不受影響
無論透過 Web OAuth 還是 LIFF 取得 session，Supabase 的 JWT 結構相同，所有 RLS 政策照常生效，不需要修改任何 RLS 規則。

---

## 九、驗收清單

### Web OAuth（LINE Login）
- [ ] 登入頁出現「用 LINE 登入」按鈕
- [ ] 點擊後成功跳轉至 LINE 授權頁
- [ ] 授權後成功跳回前端，並自動建立 `profiles`（role='client'）
- [ ] `auth_provider` 欄位正確寫入 `'line_oauth'`
- [ ] 沒有 email 的 LINE 帳號仍可成功登入

### LIFF（LINE Mini App）
- [ ] 在 LINE App 內開啟 LIFF URL，自動完成登入（不需手動按按鈕）
- [ ] `liff.getIDToken()` → Edge Function → `setSession` 流程無誤
- [ ] `line_user_id` 正確寫入 `profiles`
- [ ] `auth_provider` 欄位正確寫入 `'liff'`
- [ ] 搜尋、預訂、結帳主流程可在 LIFF 環境完成
- [ ] RLS 資料可見性不退化

### 共通
- [ ] 本地開發環境（localhost）的 email 登入不受影響
- [ ] admin 後台功能不受影響
- [ ] i18n 三語系（AR/FR/EN）均有對應翻譯

