# 語系刪減評估與執行計畫（只留中文）

更新日期：2026-10-31  
適用範圍：vue-booking（Vue 3 + TypeScript + vue-i18n）

---

## 1. 結論摘要

可行，建議採用「單語系化（繁中 zh-TW）」方案。  
目前專案 i18n 架構集中，主要影響點有限，刪減其他語系的風險可控。

預估工期：
- 實作 + 測試：0.5 到 1 天
- 文件與回歸：0.5 天

---

## 2. 現況盤點（已確認）

### 2.1 目前語系

- 現有語系檔：ar、fr、en（無中文檔）
- 預設語系：en（來自 .env.example）
- fallback 語系：fr
- RTL 支援：ar

### 2.2 影響檔案

核心 i18n：
- [src/i18n/index.ts](src/i18n/index.ts)
- [src/i18n/en.ts](src/i18n/en.ts)
- [src/i18n/fr.ts](src/i18n/fr.ts)
- [src/i18n/ar.ts](src/i18n/ar.ts)

語言切換與狀態：
- [src/components/LanguageSwitcher.vue](src/components/LanguageSwitcher.vue)
- [src/stores/locale.ts](src/stores/locale.ts)
- [src/layouts/AppLayout.vue](src/layouts/AppLayout.vue)
- [src/layouts/AuthLayout.vue](src/layouts/AuthLayout.vue)
- [src/app/App.vue](src/app/App.vue)

格式化與地區碼：
- [src/utils/format.ts](src/utils/format.ts)

測試與設定：
- [tests/i18n.spec.ts](tests/i18n.spec.ts)
- [.env.example](.env.example)
- [README.md](README.md)

---

## 3. 刪減策略（建議）

目標：只保留繁體中文（zh-TW），移除 ar/fr/en 多語切換能力。

策略重點：
- 保留 i18n 介面（t(...) 不改），僅收斂成單一 messages。
- 移除 LanguageSwitcher UI，避免提供不存在語言選項。
- 移除 RTL 分支與 ar/fr/en 的 locale 特判。
- 調整測試從「語言覆蓋」改為「中文完整性」與關鍵鍵值存在檢查。

---

## 4. 執行清單（Checklist）

## Phase 0：準備

- [ ] 建立分支：feat/i18n-chinese-only
- [ ] 備份目前 i18n 檔案（或以 Git 歷史可回復）
- [ ] 決議中文語系代碼：zh-TW（建議）

## Phase 1：新增中文語系並切換核心設定

- [ ] 新增 [src/i18n/zh-TW.ts](src/i18n/zh-TW.ts)
- [ ] 以現有 en 作為 key 基底，完成中文文案（至少先完整覆蓋 key）
- [ ] 調整 [src/i18n/index.ts](src/i18n/index.ts)

目標狀態：
- SUPPORTED_LOCALES = ['zh-TW']
- LOCALE_LABELS 僅保留 zh-TW
- initialLocale/fallbackLocale 都固定 zh-TW
- messages 僅載入 zh-TW
- RTL_LOCALES 清空或移除

## Phase 2：移除語言切換 UI 與多語分支

- [ ] 移除 [src/layouts/AppLayout.vue](src/layouts/AppLayout.vue) 的 LanguageSwitcher 掛載
- [ ] 移除 [src/layouts/AuthLayout.vue](src/layouts/AuthLayout.vue) 的 LanguageSwitcher 掛載
- [ ] 刪除 [src/components/LanguageSwitcher.vue](src/components/LanguageSwitcher.vue)（若無其他用途）
- [ ] 精簡 [src/stores/locale.ts](src/stores/locale.ts)

建議保留：
- locale store 仍保留 current（固定 zh-TW），避免大量呼叫點重構

## Phase 3：格式化函式單語系化

- [ ] 調整 [src/utils/format.ts](src/utils/format.ts)

目標狀態：
- 預設 locale 從 fr 改為 zh-TW
- 金額/日期格式改用 zh-TW（或 zh-Hant-TW）
- 移除 ar/fr/en 分支判斷

## Phase 4：測試更新

- [ ] 重寫 [tests/i18n.spec.ts](tests/i18n.spec.ts)

由：
- 比對 fr/ar 是否覆蓋 en

改為：
- 驗證 zh-TW 對 APP_ERROR_CODES 都有對應翻譯
- 驗證關鍵 namespace（common/nav/errors/...）存在

## Phase 5：設定與文件同步

- [ ] 更新 [.env.example](.env.example)：VITE_DEFAULT_LOCALE=zh-TW
- [ ] 更新 [README.md](README.md) i18n 段落（改為中文單語系）
- [ ] 若有部署文件提及 ar/fr/en，一併改為 zh-TW

## Phase 6：清理與刪檔

- [ ] 刪除 [src/i18n/ar.ts](src/i18n/ar.ts)
- [ ] 刪除 [src/i18n/fr.ts](src/i18n/fr.ts)
- [ ] 視需求刪除 [src/i18n/en.ts](src/i18n/en.ts)（若不作 fallback 基底）
- [ ] 搜尋殘留字串：ar、fr、en、RTL_LOCALES、LanguageSwitcher

---

## 5. 驗收標準

- [ ] 專案可正常啟動與建置（dev/build/test 全通過）
- [ ] 全站文案為中文，無語言切換入口
- [ ] 日期/金額顯示符合 zh-TW 格式預期
- [ ] 無 ar/fr/en 殘留 import 或 runtime 錯誤
- [ ] i18n 測試改版後通過

---

## 6. 風險與對策

1. 風險：中文翻譯 key 不完整，造成畫面顯示 key 字串  
對策：先用 en key 自動比對產生缺漏報表，再補齊 zh-TW。

2. 風險：刪除 LanguageSwitcher 後有殘留引用導致編譯錯誤  
對策：刪除前先全域搜尋引用並一次清理。

3. 風險：格式化改 zh-TW 造成時間/貨幣顯示變動引發認知落差  
對策：針對關鍵頁面（訂單、付款、行程時間）做人工回歸比對。

4. 風險：未來需要恢復多語會增加回復成本  
對策：以 Git tag 保留切換前版本，並在文件註記回復步驟。

---

## 7. 回滾方案

- 回滾粒度：
1. 僅回滾 UI（LanguageSwitcher）
2. 回滾 i18n 設定（index.ts + locale store）
3. 完整回滾至多語版本（git revert 整個 PR）

- 回滾前提：
1. 已保留刪除檔案於 Git 歷史
2. 測試可在回滾後立即重跑驗證

---

## 8. 建議執行順序（最小風險）

1. 先新增 zh-TW 並切換為唯一來源（不立刻刪檔）
2. 跑測試與手動驗證主流程
3. 再移除 LanguageSwitcher 與其他語系檔
4. 最後更新文件與環境範例

此順序可降低一次性大改造成的排錯成本。