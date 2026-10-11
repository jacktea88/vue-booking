# 手動設置 Supabase 數據庫指南

## 步驟 1：打開 Supabase 控制台

1. 訪問 https://app.supabase.com
2. 登入您的帳戶
3. 選擇專案 **pabhnvaglqdivysdduzx**
4. 點選左側邊欄的 **SQL Editor**

## 步驟 2：執行遷移文件

按照以下順序，將每個遷移文件的內容複製並粘貼到 SQL Editor 中執行：

### 2.1 - 0001_extensions.sql
創建 PostGIS 擴展和基礎函數。

### 2.2 - 0002_enums.sql
創建所有的 PostgreSQL 枚舉類型（user_role、booking_status 等）。

### 2.3 - 0003_profiles.sql
創建用戶配置表和駕駛員配置表。

### 2.4 - 0004_verification.sql
創建身份驗證文件表和車輛表。

### 2.5 - 0005_places.sql
創建地點表（機場、車站、城市等）。

### 2.6 - 0006_trips.sql
創建行程表、檢查點表和段表。

### 2.7 - 0007_bookings.sql
創建預訂表。

### 2.8 - 0008_payments.sql
創建支付表。

### 2.9 - 0009_resale.sql
創建轉售列表表。

### 2.10 - 0010_transfer.sql
創建轉移請求表。

### 2.11 - 0011_notifications.sql
創建通知表。

### 2.12 - 0012_ratings.sql
創建評分表。

### 2.13 - 0013_settings.sql
創建系統設置表。

### 2.14 - 0014_audit.sql
創建審計日誌表。

### 2.15 - 0015_security_helpers.sql
創建安全和設置幫助函數。

### 2.16 - 0016_rls.sql
啟用行級安全 (RLS) 策略。

### 2.17 - 0017_functions_trips.sql
創建行程相關的 RPC 函數。

### 2.18 - 0018_functions_booking.sql
創建預訂相關的 RPC 函數。

### 2.19 - 0019_storage.sql
設置 Supabase Storage bucket。

### 2.20 - 0020_seed.sql
創建初始演示數據（可選）。

## 步驟 3：執行種子數據

完成所有遷移後，執行 `supabase/seed_dev.sql` 中的內容來創建演示帳戶：

- `client@demo.test` (密碼: Passw0rd!)
- `client2@demo.test` (密碼: Passw0rd!)
- `driver@demo.test` (密碼: Passw0rd!)
- `admin@demo.test` (密碼: Passw0rd!)

## 快速執行方法

### 使用 Supabase CLI（推薦）

```bash
# 如果已安裝 Supabase CLI
supabase link --project-ref pabhnvaglqdivysdduzx
supabase db push

# 執行種子文件（需要 psql）
psql "postgresql://[user]:[password]@db.pabhnvaglqdivysdduzx.supabase.co:5432/postgres" \
  -f supabase/seed_dev.sql
```

### 使用 psql 命令行

```powershell
# 設置環境變數（從 Supabase 控制台 Settings → Database 獲取連接字符串）
$env:SUPABASE_DB_URL = "postgresql://postgres:[password]@db.pabhnvaglqdivysdduzx.supabase.co:5432/postgres"

# 執行所有遷移
Get-ChildItem supabase/migrations/*.sql -File | ForEach-Object {
    psql "$env:SUPABASE_DB_URL" -f $_.FullName
    Write-Host "✓ Executed $($_.Name)"
}

# 執行種子文件
psql "$env:SUPABASE_DB_URL" -f supabase/seed_dev.sql
Write-Host "✓ Seed data loaded"
```

## 故障排除

### 登錄失敗
- 確保已執行 `0003_profiles.sql` 和 `seed_dev.sql`
- 檢查 auth.users 表是否包含演示帳戶

### 缺少表或函數
- 確認已按順序執行所有遷移
- 檢查 SQL Editor 中的錯誤訊息

### 權限問題
- 使用 Supabase 控制台的 SQL Editor（具有自動權限）
- 或確保使用的 psql 連接具有管理員權限

## 下一步

執行完所有遷移和種子數據後：

1. 返回瀏覽器並刷新 `http://localhost:5173`
2. 嘗試使用 `client@demo.test` / `Passw0rd!` 登錄
3. 應該能夠訪問應用

