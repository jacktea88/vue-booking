# Wassalni - 搜尋功能日期可選部署指南

## 概述

本文檔說明如何修改搜尋功能，使用戶可以**僅按日期搜尋，地點可選**（而不是強制要求輸入出發地和目的地）。

**修改日期**: 2026-10-11  
**受影響檔案**:
- `supabase/migrations/0017_functions_trips.sql` - SQL 函數
- `src/services/domain/tripService.ts` - 後端服務
- `src/features/trips/SearchPage.vue` - 前端頁面

---

## 問題描述

### 原始行為
- 搜尋要求必須輸入 **出發地** 和 **目的地**
- 搜尋按鈕在地點未填時被禁用
- 無法只按日期進行寬泛搜尋

### 新增功能
- 地點參數變為 **可選**
- 用戶可以僅選擇日期進行搜尋
- 返回該日期所有可用旅程
- 如果提供地點，則按地理距離排序

---

## 修改內容

### 1. SQL 函數修改 (`0017_functions_trips.sql`)

#### 參數變更
**舊版本**:
```sql
create or replace function public.search_trips(
  p_from_lat float8, p_from_lng float8,
  p_to_lat float8, p_to_lng float8,
  p_date date, p_seats int default 1,
  ...
```

**新版本**:
```sql
create or replace function public.search_trips(
  p_date date,
  p_from_lat float8 default null, p_from_lng float8 default null,
  p_to_lat float8 default null, p_to_lng float8 default null,
  p_seats int default 1,
  p_tolerance_m int default null,
  p_limit int default 20, p_offset int default 0
)
```

#### 關鍵變更
1. **參數順序重新排列**
   - `p_date` 移到第一位（必需參數）
   - 所有地點參數變為可選（`default null`）

2. **地理檢查改為條件式**
   ```sql
   src as (select case when p_from_lat is not null and p_from_lng is not null 
                   then st_setsrid(st_makepoint(p_from_lng,p_from_lat),4326)::geography 
                   else null end g),
   dst as (select case when p_to_lat is not null and p_to_lng is not null 
                   then st_setsrid(st_makepoint(p_to_lng,p_to_lat),4326)::geography 
                   else null end g),
   ```

3. **距離計算條件式**
   ```sql
   case when (select g from src) is not null and (select g from dst) is not null
     then st_distance(a.location,(select g from src)) + st_distance(b.location,(select g from dst))
     else 0 end as detour
   ```

4. **地理範圍檢查條件式**
   ```sql
   and (case when (select g from src) is not null 
          then st_dwithin(a.location, (select g from src), tol.m) 
          else true end)
   and (case when (select g from dst) is not null 
          then st_dwithin(b.location, (select g from dst), tol.m) 
          else true end)
   ```

### 2. 後端服務修改 (`tripService.ts`)

#### SearchParams 型別變更
```typescript
export interface SearchParams {
  from?: GeoPoint | null      // 從 from: GeoPoint 改為可選
  to?: GeoPoint | null        // 從 to: GeoPoint 改為可選
  date: string                // 保持必需
  seats: number
  limit?: number
  offset?: number
}
```

#### search() 方法更新
```typescript
search(p: SearchParams): Promise<SearchTripRow[]> {
  return rpc<SearchTripRow[]>('search_trips', {
    p_date: p.date,                                    // 先傳日期
    p_from_lat: p.from?.lat ?? null,
    p_from_lng: p.from?.lng ?? null,
    p_to_lat: p.to?.lat ?? null,
    p_to_lng: p.to?.lng ?? null,
    p_seats: p.seats,
    p_limit: p.limit ?? 20, p_offset: p.offset ?? 0,
  })
}
```

### 3. 前端頁面修改 (`SearchPage.vue`)

#### 搜尋邏輯更新
```typescript
const results = useAsync<SearchTripRow[]>(async () => {
  return tripService.search({ 
    from: from.value?.point ?? null,      // 可選
    to: to.value?.point ?? null,          // 可選
    date: date.value, 
    seats: seats.value 
  })
})
```

#### 搜尋按鈕啟用
```html
<!-- 舊版本 -->
<button class="btn-primary w-full" type="submit" :disabled="!from || !to">
  {{ t('common.search') }}
</button>

<!-- 新版本 -->
<button class="btn-primary w-full" type="submit">
  {{ t('common.search') }}
</button>
```

---

## 部署步驟

### 步驟 1: 備份現有函數（可選）

在 Supabase SQL Editor 中：
```sql
-- 檢查現有函數版本
SELECT routine_name, routine_definition 
FROM information_schema.routines 
WHERE routine_name = 'search_trips' 
AND routine_schema = 'public';
```

### 步驟 2: 移除舊版本（如果存在多個）

```sql
-- 刪除舊版本（參數順序不正確的版本）
DROP FUNCTION IF EXISTS public.search_trips(
  float8, float8, float8, float8, date, int, int, int, int
) CASCADE;
```

### 步驟 3: 執行新版本函數

在 Supabase SQL Editor 中：
1. 點擊 **"New Query"**
2. 複製下方完整的 SQL 代碼
3. 粘貼到編輯器
4. 點擊 **"Run"** 按鈕

```sql
create or replace function public.search_trips(
  p_date date,
  p_from_lat float8 default null, p_from_lng float8 default null,
  p_to_lat float8 default null, p_to_lng float8 default null,
  p_seats int default 1,
  p_tolerance_m int default null,
  p_limit int default 20, p_offset int default 0
) returns table (
  trip_id uuid, driver_id uuid, driver_name text, driver_rating numeric,
  vehicle_brand text, vehicle_model text, vehicle_color text,
  departure_at timestamptz, booking_mode booking_mode,
  pickup_checkpoint_id uuid, pickup_name text, pickup_eta timestamptz,
  dropoff_checkpoint_id uuid, dropoff_name text, dropoff_eta timestamptz,
  price_per_seat numeric, available_seats int, total_distance_km numeric
) language sql stable security definer set search_path = public, app as $$
  with tol as (select coalesce(p_tolerance_m, app.setting_int('search_tolerance_meters',15000))::float8 m),
  src as (select case when p_from_lat is not null and p_from_lng is not null 
                  then st_setsrid(st_makepoint(p_from_lng,p_from_lat),4326)::geography 
                  else null end g),
  dst as (select case when p_to_lat is not null and p_to_lng is not null 
                  then st_setsrid(st_makepoint(p_to_lng,p_to_lat),4326)::geography 
                  else null end g),
  cand as (
    select t.id as trip_id, t.driver_id, t.departure_at, t.booking_mode, t.vehicle_id,
           a.id a_id, a.name a_name, a.sequence a_seq, a.estimated_arrival a_eta,
           b.id b_id, b.name b_name, b.sequence b_seq, b.estimated_arrival b_eta,
           case when (select g from src) is not null and (select g from dst) is not null
             then st_distance(a.location,(select g from src)) + st_distance(b.location,(select g from dst))
             else 0 end as detour
    from public.trips t
    join public.trip_checkpoints a on a.trip_id = t.id
    join public.trip_checkpoints b on b.trip_id = t.id
    cross join tol
    where t.status = 'published'
      and t.departure_at >= greatest(now(), p_date::timestamptz)
      and t.departure_at < (p_date + 1)::timestamptz
      and a.sequence < b.sequence
      and (case when (select g from src) is not null 
             then st_dwithin(a.location, (select g from src), tol.m) 
             else true end)
      and (case when (select g from dst) is not null 
             then st_dwithin(b.location, (select g from dst), tol.m) 
             else true end)
  ),
  best as (
    select distinct on (trip_id) * from cand order by trip_id, detour asc
  )
  select c.trip_id, c.driver_id, pr.full_name, pr.rating_avg,
         v.brand, v.model, v.color,
         c.departure_at, c.booking_mode,
         c.a_id, c.a_name, c.a_eta,
         c.b_id, c.b_name, c.b_eta,
         app.segment_price_sum(c.trip_id, c.a_id, c.b_id) as price_per_seat,
         (select min(g.capacity - g.reserved_seats)::int from public.trip_segments g
            where g.id in (select segment_id from app.covered_segment_ids(c.trip_id, c.a_id, c.b_id))) as available_seats,
         (select round(sum(g.distance_km),2) from public.trip_segments g
            where g.id in (select segment_id from app.covered_segment_ids(c.trip_id, c.a_id, c.b_id))) as total_distance_km
  from best c
  join public.public_profiles pr on pr.id = c.driver_id
  join public.vehicles v on v.id = c.vehicle_id
  where (select min(g.capacity - g.reserved_seats) from public.trip_segments g
          where g.id in (select segment_id from app.covered_segment_ids(c.trip_id, c.a_id, c.b_id))) >= greatest(p_seats,1)
  order by c.departure_at
  limit greatest(p_limit,1) offset greatest(p_offset,0);
$$;
```

### 步驟 4: 驗證部署

執行此查詢確認函數已更新：
```sql
-- 驗證函數存在且包含新邏輯
SELECT routine_definition 
FROM information_schema.routines 
WHERE routine_name = 'search_trips' 
AND routine_schema = 'public'
LIMIT 1;

-- 檢查輸出是否包含 "case when p_from_lat is not null"
```

預期輸出包含 `case when p_from_lat is not null` 文本。

### 步驟 5: 重新載入前端

在瀏覽器中：
- **強制刷新**: `Ctrl+Shift+R` (Windows) 或 `Cmd+Shift+R` (Mac)
- 或清除瀏覽器快取後重新載入

### 步驟 6: 測試功能

1. **使用演示賬戶登入**
   - 郵箱: `client@demo.test`
   - 密碼: `Passw0rd!`

2. **測試場景 A: 僅日期搜尋**
   - 不填出發地和目的地
   - 選擇日期
   - 點擊搜尋
   - 應顯示該日期所有可用旅程

3. **測試場景 B: 日期 + 地點搜尋**
   - 填入出發地
   - 填入目的地
   - 選擇日期
   - 點擊搜尋
   - 應顯示符合地點的旅程（按距離排序）

---

## 故障排查

### 錯誤 1: "Something went wrong" 訊息

**原因**: 可能存在多個函數版本

**解決方案**:
```sql
-- 查詢所有 search_trips 函數版本
SELECT proname, pronargs, proargtypes 
FROM pg_proc 
WHERE proname = 'search_trips' 
AND pronamespace = 'public'::regnamespace;

-- 如果有多於一個版本，刪除舊版本
DROP FUNCTION IF EXISTS public.search_trips(
  float8, float8, float8, float8, date, int, int, int, int
) CASCADE;
```

### 錯誤 2: "input parameters after one with a default value must also have defaults"

**原因**: 參數順序不正確（有默認值的參數在無默認值的參數之前）

**解決方案**: 確保 `p_date date` 是第一個參數（無默認值），所有其他參數都有 `default` 值

### 錯誤 3: 搜尋返回空結果

**檢查清單**:
1. ✅ 確認已有已發佈的旅程 (`trips.status = 'published'`)
2. ✅ 確認旅程出發時間在選定日期內
3. ✅ 確認旅程有足夠座位
4. ✅ 檢查 Supabase 日誌查看 RPC 錯誤

### 錯誤 4: 登入後自動登出

**原因**: Supabase 連線或認證問題

**解決方案**:
- 清除瀏覽器快取
- 檢查 `.env` 檔案中的 Supabase 認證資訊
- 確認網路連線正常

---

## 測試清單

- [ ] SQL 函數已在 Supabase 成功執行
- [ ] 函數包含新的條件邏輯（`case when`）
- [ ] 前端代碼已同步更新
- [ ] 瀏覽器已強制刷新（Ctrl+Shift+R）
- [ ] 能夠使用演示賬戶登入
- [ ] 僅日期搜尋返回結果
- [ ] 日期 + 地點搜尋返回結果
- [ ] 搜尋按鈕不再禁用
- [ ] 移動設備上搜尋功能正常

---

## 相關檔案

| 檔案 | 用途 |
|-----|-----|
| `supabase/migrations/0017_functions_trips.sql` | SQL 函數定義 |
| `src/services/domain/tripService.ts` | 後端 RPC 呼叫 |
| `src/features/trips/SearchPage.vue` | 前端搜尋頁面 |
| `src/types/index.ts` | TypeScript 型別定義 |

---

## 版本歷史

| 日期 | 版本 | 變更 |
|-----|------|-----|
| 2026-10-11 | 1.0 | 初始部署 - 支援可選地點搜尋 |

---

## 支援聯絡

如有問題，請檢查：
1. Supabase 專案日誌 (`Logs` → `Database` 或 `Edge Functions`)
2. 瀏覽器開發者工具 (`F12` → `Console`)
3. 本文檔的「故障排查」部分
