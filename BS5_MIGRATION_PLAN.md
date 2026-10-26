# Tailwind CSS v4 → Bootstrap 5 遷移計畫

**建立日期**：2026-10-26  
**前提**：移除阿拉伯語 RTL 佈局支援（i18n 翻譯文字保留，僅移除 `dir="rtl"` 相關邏輯）  
**目標**：降低協作者上手門檻，全面替換為 Bootstrap 5  

---

## 一、全域 Class 對照表

### 1-1 核心設計系統元件（`style.css` → BS5 對應）

| 自訂 class（現在） | Bootstrap 5 對應 | 說明 |
|------------------|-----------------|------|
| `card` | `card` + 加入 `rounded-3 border border-light shadow-sm p-3` | BS5 的 `.card` 需搭配 `.card-body` |
| `btn-primary` | `btn btn-primary` | 需 SCSS override 品牌色 |
| `btn-secondary` | `btn btn-outline-secondary` | 白底灰框 |
| `btn-danger` | `btn btn-danger` | 直接對應 |
| `btn-ghost` | `btn btn-link text-secondary` | 無背景文字按鈕 |
| `field` | `form-control` | BS5 表單輸入框 |
| `label` | `form-label` | BS5 表單標籤 |
| `badge` | `badge` | BS5 有對應，顏色需調整 |
| `table-wrap` | `table-responsive` | 可水平滾動的表格容器 |
| `table` | `table table-sm table-bordered` | BS5 表格 |

---

### 1-2 版型與間距（最高頻使用）

| Tailwind | Bootstrap 5 | 說明 |
|----------|------------|------|
| `flex` | `d-flex` | |
| `flex-col` | `flex-column` | |
| `flex-1` | `flex-fill` | |
| `flex-wrap` | `flex-wrap` | 相同 |
| `items-center` | `align-items-center` | |
| `items-start` | `align-items-start` | |
| `items-end` | `align-items-end` | |
| `justify-between` | `justify-content-between` | |
| `justify-center` | `justify-content-center` | |
| `gap-2` | `gap-2` | BS5 有內建 gap（需 Bootstrap ≥ 5.1） |
| `gap-3` | `gap-3` | |
| `grid` | `row` | BS5 用 row/col 格線 |
| `grid-cols-2` | `row` + `col-6` | |
| `sm:grid-cols-2` | `row` + `col-12 col-sm-6` | 響應式 col |
| `w-full` | `w-100` | |
| `mx-auto` | `mx-auto` | 相同 |
| `min-w-0` | `mw-0` (少用) 或 `overflow-hidden` | |
| `hidden` | `d-none` | |
| `hidden md:flex` | `d-none d-md-flex` | |
| `hidden sm:inline-flex` | `d-none d-sm-inline-flex` | |
| `block` | `d-block` | |
| `inline-flex` | `d-inline-flex` | |
| `relative` | `position-relative` | |
| `absolute` | `position-absolute` | |
| `fixed` | `position-fixed` | |
| `sticky` | `sticky-top` | |
| `inset-x-0` | `start-0 end-0` | |
| `bottom-0` | `bottom-0` | |
| `top-0` | `top-0` | |
| `z-30` | `z-3` (或自訂 CSS) | |
| `overflow-x-auto` | `overflow-x-auto` | 相同 |
| `overflow-hidden` | `overflow-hidden` | 相同 |
| `truncate` | `text-truncate` | |

---

### 1-3 間距（Tailwind → BS5 數值對應）

| Tailwind | BS5 | px 值 |
|----------|-----|-------|
| `mt-1` / `mb-1` | `mt-1` / `mb-1` | 4px |
| `mt-2` / `mb-2` | `mt-2` / `mb-2` | 8px |
| `mt-3` / `mb-3` | `mt-3` / `mb-3` | 16px |
| `mt-4` / `mb-4` | `mt-4` / `mb-4` | 24px（BS5 約 1.5rem） |
| `mt-5` | `mt-5` | 48px（BS5 約 3rem） |
| `mt-6` | 需補 `.mt-6 { margin-top: 1.5rem }` 或用 `mt-4` | 無直接對應 |
| `p-3` | `p-2` / `p-3` | 視設計 |
| `p-4` | `p-3` | |
| `px-3 py-2` | `px-3 py-2` | 相同 |
| `px-4 py-2.5` | `px-3 py-2` | 約略 |
| `space-y-3` | ❌ 無對應 → 改 `d-flex flex-column gap-3` | 需重構 |
| `space-y-4` | ❌ 無對應 → 改 `d-flex flex-column gap-3` | 需重構 |
| `space-y-5` | ❌ 無對應 → 改 `d-flex flex-column gap-4` | 需重構 |

> ⚠️ `space-y-*` 是最常出現的 Tailwind 特有語法（共 37 行），改法是把父 `<div>` 加上 `d-flex flex-column gap-N`。

---

### 1-4 文字樣式

| Tailwind | Bootstrap 5 |
|----------|------------|
| `text-xs` | `small` 或 `fs-7`（需補 SCSS） |
| `text-sm` | `small` 或 `fs-6` |
| `text-base` | `fs-6`（預設） |
| `text-lg` | `fs-5` |
| `text-xl` | `fs-4` |
| `font-medium` | `fw-medium` |
| `font-semibold` | `fw-semibold` |
| `font-bold` | `fw-bold` |
| `text-center` | `text-center` | 相同 |
| `text-slate-500` | `text-muted` | |
| `text-slate-600` | `text-secondary` | |
| `text-slate-700` | `text-dark` 或 `text-body` | |
| `text-slate-900` | `text-body` | |
| `text-red-700` | `text-danger` | |
| `text-brand-700` | `text-primary` | 需 SCSS override |
| `text-amber-700` | `text-warning` | |
| `text-violet-700` | 需補 `.text-violet { color: #6d28d9 }` | 無對應 |
| `text-[10px]` / `text-[11px]` | 需補 `.fs-xxs { font-size: 10px }` 等 | 任意值 |

---

### 1-5 顏色與背景

| Tailwind | Bootstrap 5 |
|----------|------------|
| `bg-white` | `bg-white` | 相同 |
| `bg-slate-50` | `bg-light` | |
| `bg-slate-100` | `bg-light` | |
| `bg-slate-200` | 需補自訂 CSS | |
| `bg-brand-50` | `bg-primary bg-opacity-10` | 或補 `.bg-brand-light` |
| `bg-brand-700` | `bg-primary` | 需 SCSS override |
| `bg-red-600` | `bg-danger` | |
| `bg-amber-50` | `bg-warning bg-opacity-10` | 或補 `.bg-amber-light` |
| `bg-white/95` | 補 CSS `background: rgba(255,255,255,.95)` | 任意值，無對應 |
| `border` | `border` | 相同 |
| `border-slate-200` | `border-light` | |
| `border-slate-300` | `border` | |
| `border-amber-300` | 補 CSS `border-color: #fcd34d !important` | |
| `border-t` | `border-top` | |
| `border-b` | `border-bottom` | |
| `hover:border-brand-600` | 補 `.hover-border-primary:hover { border-color: var(--bs-primary) }` | |

---

### 1-6 需自行補充的 SCSS 工具 class

以下 Tailwind 特性在 BS5 完全沒有對應，需在自訂 `_utilities.scss` 補充：

```scss
// 任意字體大小
.fs-xxs  { font-size: 10px; }
.fs-xs   { font-size: 11px; }

// 動畫（AsyncSection skeleton）
@keyframes pulse {
  0%, 100% { opacity: 1; }
  50%       { opacity: .4; }
}
.animate-pulse { animation: pulse 2s cubic-bezier(0.4,0,0.6,1) infinite; }

// 背景半透明
.bg-white-95 { background: rgba(255,255,255,.95); }

// min-height viewport
.min-h-dvh { min-height: 100dvh; }

// 行動版底部導覽高度補償
.pb-bottom-nav { padding-bottom: 5rem; }

// 品牌色 text/border hover
.hover-border-primary:hover { border-color: var(--bs-primary) !important; }
.bg-brand-light { background-color: rgba(var(--bs-primary-rgb), .1); }
```

---

## 二、分頁遷移優先順序

總計 **34 個 Vue 元件**，依複雜度與影響範圍排序：

### Phase 1：基礎設定（約 0.5 天）⚙️

| 步驟 | 工作 | 說明 |
|------|------|------|
| 1 | 安裝 `bootstrap` + `sass` | `npm install bootstrap sass` |
| 2 | 移除 `@tailwindcss/vite` + `tailwindcss` | 從 `package.json` 移除 |
| 3 | 修改 `vite.config.ts` | 移除 Tailwind plugin |
| 4 | 新增 `src/app/scss/_variables.scss` | 品牌色 override |
| 5 | 新增 `src/app/scss/_utilities.scss` | 補充自訂工具 class |
| 6 | 新增 `src/app/scss/main.scss` | import BS5 + 自訂 SCSS |
| 7 | 修改 `src/app/style.css` → 改為 `main.scss` 入口 |  |
| 8 | 移除 `App.vue` 的 RTL 邏輯（`dir` binding） | 維持 `dir="ltr"` 固定 |

**SCSS 變數設定範例：**
```scss
// src/app/scss/_variables.scss
$primary:   #0f766e;   // brand-700
$secondary: #64748b;   // slate-500
$body-bg:   #f8fafc;   // slate-50
$border-radius-lg: .75rem;
$font-size-base: .9375rem;

// 讓 BS5 用這些變數編譯
@import "bootstrap/scss/bootstrap";
```

---

### Phase 2：共用元件（約 1 天）🧩

優先改這些，因為它們被所有頁面引用：

| 檔案 | 複雜度 | 主要改動 |
|------|--------|---------|
| `src/app/style.css` | ⭐⭐⭐ | 整個重寫為 SCSS import |
| `src/layouts/AuthLayout.vue` | ⭐ | 簡單，`flex min-h-dvh` → `d-flex flex-column min-h-dvh` |
| `src/layouts/AppLayout.vue` | ⭐⭐⭐ | 頂部 Navbar + 底部行動版 Tab Bar |
| `src/components/AsyncSection.vue` | ⭐⭐ | skeleton + card + btn |
| `src/components/StatusBadge.vue` | ⭐ | badge class |
| `src/components/ConfirmDialog.vue` | ⭐⭐ | Modal（可用 BS5 Modal 元件替換） |
| `src/components/ToastHost.vue` | ⭐⭐ | Toast（可用 BS5 Toast 元件替換） |
| `src/components/LanguageSwitcher.vue` | ⭐ | 簡單 |
| `src/components/DataTable.vue` | ⭐⭐ | table → `table table-sm` |
| `src/components/SeatStepper.vue` | ⭐ | input-group |
| `src/components/PlaceAutocomplete.vue` | ⭐⭐ | form-control + dropdown |
| `src/components/MapView.vue` | ⭐ | 容器 class，地圖本身不受影響 |

> 💡 **ConfirmDialog** 和 **ToastHost** 可直接換成 Bootstrap 5 的官方 Modal / Toast JS 元件，視覺更統一。

---

### Phase 3：認證頁面（約 0.5 天）🔑

最簡單的頁面，適合練手：

| 檔案 | 複雜度 | 主要改動 |
|------|--------|---------|
| `src/features/auth/LoginPage.vue` | ⭐ | card + form-label + form-control + btn |
| `src/features/auth/RegisterPage.vue` | ⭐⭐ | 同上 + fieldset radio 樣式 |
| `src/features/auth/ForgotPasswordPage.vue` | ⭐ | 簡單表單 |
| `src/features/auth/ResetPasswordPage.vue` | ⭐ | 簡單表單 |

---

### Phase 4：主要功能頁面（約 1.5 天）📄

| 檔案 | 複雜度 | 主要改動 |
|------|--------|---------|
| `src/pages/HomePage.vue` | ⭐⭐ | card grid |
| `src/pages/NotFoundPage.vue` | ⭐ | 簡單 |
| `src/features/trips/SearchPage.vue` | ⭐⭐ | card form + 搜尋結果列表 |
| `src/features/trips/TripDetailsPage.vue` | ⭐⭐⭐ | 複雜，多個 card + dl grid |
| `src/features/bookings/BookingsPage.vue` | ⭐⭐ | 列表 |
| `src/features/bookings/BookingDetailsPage.vue` | ⭐⭐⭐ | dl grid + 多個 section card |
| `src/features/payments/CheckoutPage.vue` | ⭐⭐ | |
| `src/features/profile/ProfilePage.vue` | ⭐⭐⭐ | 表單 + 文件上傳 |
| `src/features/notifications/NotificationsPage.vue` | ⭐⭐ | 列表 |
| `src/features/resale/MarketplacePage.vue` | ⭐⭐ | 列表 |
| `src/features/resale/CreateResaleForm.vue` | ⭐⭐ | 表單 |
| `src/features/ratings/RatingForm.vue` | ⭐⭐ | 表單 |
| `src/features/transfers/TransferDialog.vue` | ⭐⭐ | Dialog |

---

### Phase 5：司機功能頁面（約 1 天）🚗

| 檔案 | 複雜度 | 主要改動 |
|------|--------|---------|
| `src/features/trips/DriverHomePage.vue` | ⭐⭐ | |
| `src/features/trips/DriverTripsPage.vue` | ⭐⭐ | |
| `src/features/trips/DriverTripDetailsPage.vue` | ⭐⭐⭐ | 複雜，有多狀態操作 |
| `src/features/trips/CreateTripPage.vue` | ⭐⭐⭐ | 多步驟表單 + checkpoints |

---

### Phase 6：管理後台（約 1 天）⚙️

| 檔案 | 複雜度 | 主要改動 |
|------|--------|---------|
| `src/features/admin/AdminPage.vue` | ⭐⭐⭐⭐ | 最複雜，含 DataTable、多個管理面板 |

---

## 三、AppLayout 行動版底部導覽改法

這是最需要客製的部分（BS5 沒有 bottom tab bar）：

```html
<!-- 現在的 Tailwind 寫法 -->
<nav class="fixed inset-x-0 bottom-0 z-30 border-t border-slate-200 bg-white md:hidden">

<!-- 改成 BS5 + 補充 CSS -->
<nav class="bottom-nav d-flex d-md-none position-fixed bottom-0 start-0 end-0 bg-white border-top">
```

```scss
// _utilities.scss
.bottom-nav {
  z-index: 1030;
  ul { list-style: none; margin: 0; padding: 0; display: flex; }
  li { flex: 1; }
  a {
    display: flex; flex-direction: column; align-items: center;
    padding: .625rem .5rem; font-size: .6875rem; font-weight: 500;
    color: var(--bs-secondary); text-decoration: none;
    &.active { color: var(--bs-primary); }
  }
}

// main 內容區補 padding，避免被底部 nav 遮住
@media (max-width: 767.98px) {
  .main-content { padding-bottom: 5rem; }
}
```

---

## 四、安裝指令（Phase 1 執行）

```bash
# 安裝 Bootstrap 5 與 SCSS 編譯器
npm install bootstrap
npm install --save-dev sass

# 移除 Tailwind
npm uninstall tailwindcss @tailwindcss/vite
```

**`vite.config.ts` 修改：**
```typescript
// 移除這行
import tailwindcss from '@tailwindcss/vite'

// plugins 中移除 tailwindcss()
```

**`src/app/main.scss`（新增）：**
```scss
@use './scss/variables' as *;  // 品牌色 override（必須在 BS5 import 前）
@use 'bootstrap/scss/bootstrap';
@use './scss/utilities';
```

---

## 五、遷移完成驗收清單

### 功能測試
- [ ] 登入 / 登出 / 忘記密碼 流程正常
- [ ] 搜尋行程、進入詳情、預訂、結帳
- [ ] 預訂詳情：取消、二手票、轉讓
- [ ] 司機：建立行程、管理、批准/拒絕預訂
- [ ] 管理後台：用戶管理、審核文件

### 視覺測試
- [ ] 手機（375px）：底部導覽顯示正確
- [ ] 平板（768px）：版面切換正確
- [ ] 桌機（1280px）：頂部導覽顯示
- [ ] 法語、阿拉伯語（無 RTL 佈局）文字顯示正確
- [ ] 品牌色（Teal #0f766e）正確套用在按鈕、連結、badge

### 效能
- [ ] `npm run build` 成功，無 TypeScript 錯誤
- [ ] Bundle 大小合理（Bootstrap ≈ 30KB gzip）

---

## 六、工時總估計

| Phase | 工作內容 | 預估工時 |
|-------|---------|---------|
| 1 | 基礎設定（BS5 安裝、SCSS 架設） | 0.5 天 |
| 2 | 共用元件（12 個） | 1.0 天 |
| 3 | 認證頁面（4 個） | 0.5 天 |
| 4 | 主要功能頁面（13 個） | 1.5 天 |
| 5 | 司機功能頁面（4 個） | 1.0 天 |
| 6 | 管理後台（1 個，最複雜） | 1.0 天 |
| — | 視覺調整 + 測試 | 0.5 天 |
| **合計** | | **約 6 工作天** |

