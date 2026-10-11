# Wassalni - 本地開發環境設置指南

## 概述

本文檔說明如何在本地開發機上設置和運行 Wassalni 項目進行開發和測試。

**專案名稱**: Wassalni - 阿爾及利亞乘車共享平台  
**前端框架**: Vue 3 + TypeScript + Vite  
**後端**: Supabase (PostgreSQL + PostGIS)  
**最後更新**: 2026-10-11

---

## 系統需求

### 最低配置
| 項目 | 最低要求 | 推薦 |
|-----|---------|------|
| **OS** | Windows 10 / macOS 10.15 / Ubuntu 20.04 | Windows 11 / macOS 12+ / Ubuntu 22.04 |
| **CPU** | 雙核 2GHz | 四核 2.5GHz+ |
| **RAM** | 4GB | 8GB+ |
| **磁碟空間** | 2GB | 5GB+ |
| **網路** | 10Mbps 穩定連接 | 30Mbps+ |

### 作業系統兼容性
✅ **Windows 10/11** (PowerShell 或 CMD)  
✅ **macOS 10.15+** (Terminal)  
✅ **Ubuntu 20.04+** (Bash)  

---

## 必需開發工具

### 1. Git (版本控制)
**用途**: 克隆和管理項目代碼

**安裝步驟**:

**Windows**:
```powershell
# 使用 Chocolatey
choco install git

# 或直接下載
# https://git-scm.com/download/win
```

**macOS**:
```bash
# 使用 Homebrew
brew install git

# 或使用 Xcode Command Line Tools
xcode-select --install
```

**Linux (Ubuntu)**:
```bash
sudo apt update
sudo apt install git
```

**驗證安裝**:
```bash
git --version
# 預期輸出: git version 2.x.x
```

---

### 2. Node.js 和 npm (JavaScript 運行時)
**用途**: 運行 Vue 應用和包管理

**推薦版本**: Node.js v18.0.0 或以上  
**當前項目版本**: v24.14.0

**安裝步驟**:

**Windows**:
```powershell
# 使用 Chocolatey
choco install nodejs

# 或從官方網站下載
# https://nodejs.org/
```

**macOS**:
```bash
# 使用 Homebrew
brew install node

# 或使用 nvm (推薦)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 18
```

**Linux (Ubuntu)**:
```bash
# 使用 NodeSource
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# 或使用 nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 18
```

**驗證安裝**:
```bash
node --version
# 預期輸出: v18.x.x 或以上

npm --version
# 預期輸出: 9.x.x 或以上
```

---

### 3. Visual Studio Code (IDE)
**用途**: 代碼編輯和開發

**下載**: https://code.visualstudio.com/

**安裝步驟**:

**Windows**:
```powershell
# 使用 Chocolatey
choco install vscode

# 或使用安裝程序
# https://code.visualstudio.com/Download
```

**macOS**:
```bash
brew install --cask visual-studio-code
```

**Linux (Ubuntu)**:
```bash
sudo snap install --classic code
```

**推薦 VS Code 擴展** (在 VS Code 中安裝):
- **Vue - Official** (Vue 3 支持)
- **Vite** (Vite 編譯器支持)
- **Tailwind CSS IntelliSense** (CSS 自動完成)
- **TypeScript Vue Plugin** (TypeScript 支持)
- **Eslint** (代碼檢查)
- **Prettier** (代碼格式化)
- **Thunder Client** 或 **REST Client** (API 測試)

---

## 可選開發工具

### 4. Supabase CLI (數據庫管理)
**用途**: 本地 Supabase 開發堆棧管理

**安裝步驟**:

**Windows**:
```powershell
# 使用 Chocolatey
choco install supabase

# 或使用 npm
npm install -g supabase
```

**macOS**:
```bash
brew install supabase/tap/supabase

# 或使用 npm
npm install -g supabase
```

**Linux (Ubuntu)**:
```bash
# 使用 npm
npm install -g supabase
```

**驗證安裝**:
```bash
supabase --version
```

---

### 5. Docker (容器化 - 用於本地 Supabase)
**用途**: 運行本地 Supabase PostgreSQL 實例

**下載**: https://www.docker.com/products/docker-desktop/

**安裝步驟**:

**Windows**:
- 下載 Docker Desktop for Windows
- 運行安裝程序並完成設置
- 重啟電腦

**macOS**:
```bash
brew install --cask docker
# 或下載 Docker Desktop
```

**Linux (Ubuntu)**:
```bash
sudo apt update
sudo apt install docker.io docker-compose
sudo usermod -aG docker $USER
```

**驗證安裝**:
```bash
docker --version
docker-compose --version
```

---

### 6. Postman 或 Thunder Client (API 測試)
**用途**: 測試後端 API 和 Supabase RPC

**Postman** (完整版):
- 下載: https://www.postman.com/downloads/

**Thunder Client** (VS Code 擴展 - 推薦):
```
在 VS Code 中搜索 "Thunder Client" 安裝
```

---

## 本地項目設置

### 步驟 1: 克隆項目代碼

```bash
# 打開終端/PowerShell
cd ~
git clone https://github.com/wassalni/vue-booking.git
cd vue-booking
```

### 步驟 2: 配置 npm (可選 - 如遇連接問題)

如果 npm 安裝出現超時或連接錯誤，切換到國內鏡像：

```bash
# 查看當前 registry
npm config get registry

# 切換到 Taobao 鏡像 (中國用戶推薦)
npm config set registry https://registry.npmmirror.com

# 或切換回官方源
npm config set registry https://registry.npmjs.org/
```

### 步驟 3: 安裝項目依賴

```bash
npm install
```

**預期輸出**:
```
added 211 packages in X seconds
```

**常見問題**:
- 如遇 `peer dependencies` 警告，執行:
  ```bash
  npm install --legacy-peer-deps
  ```

### 步驟 4: 配置環境變量

複製環境變量模板並編輯:

```bash
# 複製模板
cp .env.example .env

# 編輯 .env 文件 (使用 VS Code)
code .env
```

**編輯 `.env` 文件內容**:

```env
# Supabase 配置 (使用遠程項目或本地實例)
VITE_SUPABASE_URL=https://pabhnvaglqdivysdduzx.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_B7RQDC4groafI8zanEt42A_vUq0mwfs

# 地圖提供商 (OSM 無需 API 密鑰)
VITE_MAP_PROVIDER=osm

# 支付提供商 (開發模式使用 mock)
VITE_PAYMENT_PROVIDER=mock

# 默認語言
VITE_DEFAULT_LOCALE=fr
```

### 步驟 5: 啟動開發服務器

```bash
npm run dev
```

**預期輸出**:
```
  VITE v7.3.7  ready in XXX ms

  ➜  Local:   http://localhost:5173/
  ➜  press h + enter to show help
```

**訪問應用**:
打開瀏覽器並訪問: http://localhost:5173

---

## 數據庫設置選項

### 選項 A: 使用遠程 Supabase 項目 (推薦用於開發)

**優點**:
- 無需本地 Docker/PostgreSQL
- 快速設置
- 易於分享進度

**步驟**:
1. 確保 `.env` 中的 Supabase 認證信息正確
2. 訪問 https://app.supabase.com 查看數據庫
3. 數據已預先初始化，可直接使用

---

### 選項 B: 本地 Supabase 堆棧 (高級)

**前置條件**:
- Docker 已安裝
- 至少 4GB RAM 可用

**步驟**:

```bash
# 啟動本地 Supabase
supabase start

# 初始化數據庫 (應用所有遷移)
supabase db reset

# 種植演示數據
psql "$SUPABASE_DB_URL" -f supabase/seed_dev.sql

# 停止本地 Supabase
supabase stop
```

**預期輸出**:
```
Supabase local development setup is running.

API URL: http://127.0.0.1:54321
DB URL: postgresql://postgres:postgres@127.0.0.1:5432/postgres
Anon Key: eyJ...
Service Role Key: eyJ...
```

更新 `.env`:
```env
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_ANON_KEY=<your_anon_key>
```

---

## 項目運行命令

```bash
# 開發模式 (推薦)
npm run dev

# 生產構建
npm run build

# 預覽生產構建
npm run preview

# 執行單元測試
npm test

# 檢查代碼質量 (TypeScript 檢查)
npm run vue-tsc

# 格式化代碼 (Prettier)
npm run format
```

---

## 演示賬戶登錄

項目已預先配置演示用戶，可直接登錄測試:

| 郵箱 | 密碼 | 角色 | 用途 |
|-----|------|------|------|
| `client@demo.test` | `Passw0rd!` | 客戶 | 訂票測試 |
| `driver@demo.test` | `Passw0rd!` | 駕駛員 | 發布行程測試 |
| `admin@demo.test` | `Passw0rd!` | 管理員 | 系統管理測試 |

---

## 項目目錄結構

```
vue-booking/
├── src/                           # 源代碼
│   ├── components/               # Vue 組件
│   ├── features/                 # 功能模塊
│   ├── services/                 # API 服務
│   ├── stores/                   # Pinia 狀態管理
│   ├── types/                    # TypeScript 型別
│   ├── i18n/                     # 國際化文件
│   └── router/                   # Vue Router 路由
├── supabase/                      # 數據庫配置
│   ├── migrations/               # SQL 遷移文件
│   ├── functions/                # Edge Functions
│   └── seed_dev.sql              # 演示數據
├── tests/                        # 測試文件
├── .env.example                  # 環境變量模板
├── package.json                  # 依賴配置
├── tsconfig.json                 # TypeScript 配置
├── vite.config.ts                # Vite 配置
└── README.md                      # 項目說明
```

---

## 常見問題排查

### 問題 1: npm install 超時或失敗

**症狀**: `ECONNRESET` 或 `ERR_SOCKET_TIMEOUT`

**解決方案**:
```bash
# 清除 npm 快取
npm cache clean --force

# 切換到國內鏡像
npm config set registry https://registry.npmmirror.com

# 重新安裝
npm install
```

### 問題 2: 開發服務器無法啟動

**症狀**: `EADDRINUSE` 或 "Port 5173 already in use"

**解決方案**:
```bash
# 找到占用端口的進程 (Windows)
netstat -ano | findstr "5173"

# 殺死進程 (Windows PowerShell)
taskkill /PID <PID> /F

# macOS/Linux
lsof -i :5173
kill -9 <PID>
```

### 問題 3: Supabase 連接失敗

**症狀**: "Something went wrong" 或連接超時

**排查步驟**:
1. 驗證 `.env` 中的 Supabase URL 和密鑰
2. 檢查網路連接
3. 確認 Supabase 項目狀態: https://app.supabase.com
4. 清除瀏覽器快取 (Ctrl+Shift+Delete)

### 問題 4: 搜尋功能返回錯誤

**症狀**: 搜尋頁面顯示 "Something went wrong"

**解決方案**:
1. 確認 SQL 遷移已在 Supabase 成功執行
2. 檢查 Supabase 中 `search_trips` 函數是否存在
3. 查看瀏覽器控制台 (F12) 查看詳細錯誤信息

---

## 開發工作流

### 1. 創建新分支

```bash
git checkout -b feature/your-feature-name
```

### 2. 進行開發

```bash
# 編輯文件並開發功能
# Vite 會自動熱重載

npm run dev
```

### 3. 測試代碼

```bash
# 執行單元測試
npm test

# TypeScript 檢查
npm run vue-tsc
```

### 4. 提交變更

```bash
git add .
git commit -m "feat: description of your changes"
git push origin feature/your-feature-name
```

---

## 性能優化技巧

### 開發中的快速刷新

```bash
# Vite 支持快速模塊熱重載 (HMR)
# 編輯文件後自動刷新瀏覽器
npm run dev
```

### 生產構建優化

```bash
# 生成優化的生產包
npm run build

# 查看構建文件大小
npm run preview
```

---

## 支援和文檔

| 資源 | 連結 |
|-----|------|
| **Vue 3 官方文檔** | https://vuejs.org/ |
| **Vite 官方文檔** | https://vitejs.dev/ |
| **Supabase 文檔** | https://supabase.com/docs |
| **TypeScript 手冊** | https://www.typescriptlang.org/docs/ |
| **Tailwind CSS** | https://tailwindcss.com/docs |

---

## 設置檢查清單

在開始開發前，確保已完成以下步驟:

- [ ] Git 已安裝 (`git --version`)
- [ ] Node.js v18+ 已安裝 (`node --version`)
- [ ] npm 已安裝 (`npm --version`)
- [ ] VS Code 已安裝並配置 Vue/TypeScript 擴展
- [ ] 項目已克隆: `git clone ...`
- [ ] 依賴已安裝: `npm install`
- [ ] `.env` 文件已配置
- [ ] 開發服務器可啟動: `npm run dev`
- [ ] 瀏覽器可訪問 http://localhost:5173
- [ ] 演示賬戶能正常登錄

---

## 版本歷史

| 日期 | 版本 | 更新內容 |
|-----|------|---------|
| 2026-10-11 | 1.0 | 初始本地開發指南 |

---

## 反饋和支援

如遇問題，請檢查:
1. 本文檔的「常見問題排查」部分
2. VS Code 開發者工具 (F12)
3. 瀏覽器控制台錯誤信息
4. Supabase 儀表板日誌

祝開發順利! 🚀
