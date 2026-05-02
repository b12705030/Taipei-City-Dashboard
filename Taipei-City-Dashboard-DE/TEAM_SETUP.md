# 行人安全 + 大眾運輸等時圈 + 人口流量 + 雙北人行道路網 — 環境設定指南

> 適用分支：`develop`
> 前提：已完成官方 Docker 環境設定（能跑起來基本 Dashboard，`localhost` 有畫面）

---

## 這個分支加了什麼

| 功能 | 說明 |
|------|------|
| 行人安全地圖 | 雙北行人事故熱區、時段分析、年度趨勢、高風險路口排名 |
| 行人事故圓餅圖 | 天氣分布 & 事故類型細項（A2類事故統計） |
| 大眾運輸步行等時圈 | 捷運／公車／台鐵站 5/10/15 分鐘步行覆蓋等時圈，可點圖例篩選，長條圖疊加顯示 |
| 人口流量（電信信令） | 雙北各行政區平日日間／夜間活動人數及差異，可捲動長條圖 |
| 雙北步行路網圖資 | 圖資資訊頁，金黃色為人行道、咖啡色為巷弄道路；等時圈以實際路網計算（OSM Dijkstra） |
| 人行道寬度指標 | 各行政區人行道寬度分布（紅／黃／綠）100% 疊加長條圖 |
| 最後一哩路儀表板 | 整合人口流量、等時圈、行人事故共 12 個組件的綜合儀表板 |

---

## 第一次設定（從來沒跑過這個分支）

> 注意：所有指令都在 **PowerShell** 執行。本文件使用 `docker cp` 而非 `<` 重導向，原因是 PowerShell 的 `<` 會造成中文亂碼。

### 步驟一：拉程式碼

```powershell
git fetch origin
git checkout develop
git pull origin develop
```

---

### 步驟二：匯入行人事故資料（約 12 MB）

> 這份 dump 會自動建表，**不需要**先跑 `setup_pedestrian_tables.sql`

```powershell
docker cp Taipei-City-Dashboard-DE/pedestrian_all.sql postgres-data:/tmp/pedestrian.sql
docker exec postgres-data psql -U postgres -d dashboard -f /tmp/pedestrian.sql
```

成功時最後會出現多行 `COPY xxx`；出現 `already exists` 警告可忽略。

---

### 步驟三：設定行人安全儀表板組件

```powershell
docker cp Taipei-City-Dashboard-DE/setup_pedestrian_components.sql postgres-manager:/tmp/setup_pedestrian.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_pedestrian.sql
```

---

### 步驟三之一：設定行人事故圓餅圖（天氣 & 事故類型）

> 需要 A2類事故 CSV（`data/NPA_TMA2_*.csv`），已隨 git 附上。

```powershell
pip install psycopg2-binary
python Taipei-City-Dashboard-DE/etl_pedestrian_pie.py
```

成功會看到「完成！」並寫入 `ped_accident_weather_stats` / `ped_accident_subtype_stats`。

```powershell
docker cp Taipei-City-Dashboard-DE/setup_pedestrian_pie_components.sql postgres-manager:/tmp/setup_pie.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_pie.sql
```

---

### 步驟四：設定大眾運輸等時圈組件

```powershell
docker cp Taipei-City-Dashboard-DE/setup_isochrone_components.sql postgres-manager:/tmp/setup_iso.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_iso.sql
```

接著計算各行政區覆蓋率（需要 Python）：

```powershell
pip install shapely pyproj psycopg2-binary
python Taipei-City-Dashboard-DE/compute_isochrone_coverage.py
```

成功會看到：
```
讀取行政區邊界...
  台北: 12 區，新北: 29 區
=== 公車 ===
  ...
共 123 筆，寫入 DB...
完成！
```

接著設定站點標記圓點圖層（捷運站 / 台鐵站，GeoJSON 已隨 git 附上）：

```powershell
docker cp Taipei-City-Dashboard-DE/setup_station_markers.sql postgres-manager:/tmp/setup_stations.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_stations.sql
```

---

### 步驟五：匯入人口流量資料

```powershell
docker cp db-sample-data/population_flow_migration.sql postgres-data:/tmp/pop_flow.sql
docker exec postgres-data psql -U postgres -d dashboard -f /tmp/pop_flow.sql

docker cp db-sample-data/population_flow_migration.sql postgres-manager:/tmp/pop_flow_mgr.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/pop_flow_mgr.sql
```

> 同一份 SQL 需要跑兩次：第一次匯入資料（`dashboard` DB），第二次設定組件（`dashboardmanager` DB）。  
> 兩個 DB 執行同一份 SQL 時，各自只會執行對應自己的 PART（另一個 PART 的 table 不存在時會報錯，可忽略）。

---

### 步驟六：設定雙北步行路網圖資組件

```powershell
docker cp Taipei-City-Dashboard-DE/setup_walkable_components.sql postgres-manager:/tmp/setup_walkable.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_walkable.sql
```

---

### 步驟七：設定人行道寬度組件

```powershell
docker cp Taipei-City-Dashboard-DE/setup_sidewalk_width_components.sql postgres-manager:/tmp/setup_sidewalk_width.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_sidewalk_width.sql
```

接著計算各行政區寬度分布統計（GeoJSON 已隨 git 附上）：

```powershell
python Taipei-City-Dashboard-DE/compute_sidewalk_stats.py
```

成功會看到：
```
共 41 個行政區，寫入 DB...
完成！
```

---

### 步驟八：重啟後端與前端

```powershell
docker restart dashboard-be
docker restart dashboard-fe
```

> **為什麼要重啟 `dashboard-fe`？**
> Vite dev server 在容器啟動時會掃描 `public/` 目錄。若 geojson 檔案在容器啟動前就已存在（透過 git pull 進來），Vite 有時會快取一個 404 fallback。重啟可強制 Vite 重新掃描，讓所有 GeoJSON 正常被識別。

---

### 步驟八：重新整理瀏覽器

按 **Ctrl+Shift+R**（強制清除快取重整，不是一般 F5）

---

## 已有舊設定，只需要更新

```powershell
git fetch origin
git checkout develop
git pull origin develop

docker cp Taipei-City-Dashboard-DE/setup_pedestrian_components.sql postgres-manager:/tmp/setup_pedestrian.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_pedestrian.sql

python Taipei-City-Dashboard-DE/etl_pedestrian_pie.py

docker cp Taipei-City-Dashboard-DE/setup_pedestrian_pie_components.sql postgres-manager:/tmp/setup_pie.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_pie.sql

docker cp Taipei-City-Dashboard-DE/setup_isochrone_components.sql postgres-manager:/tmp/setup_iso.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_iso.sql

docker cp Taipei-City-Dashboard-DE/setup_station_markers.sql postgres-manager:/tmp/setup_stations.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_stations.sql

docker cp Taipei-City-Dashboard-DE/setup_walkable_components.sql postgres-manager:/tmp/setup_walkable.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_walkable.sql

docker cp Taipei-City-Dashboard-DE/setup_sidewalk_width_components.sql postgres-manager:/tmp/setup_sidewalk_width.sql
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_sidewalk_width.sql

python Taipei-City-Dashboard-DE/compute_sidewalk_stats.py

docker restart dashboard-be
docker restart dashboard-fe
```

最後 **Ctrl+Shift+R** 重整瀏覽器。

---

## 確認功能

| 功能 | 網址 |
|------|------|
| 行人安全地圖 | `http://localhost/mapview?index=pedestrian-safety&city=metrotaipei` |
| 大眾運輸等時圈（地圖） | `http://localhost/mapview?index=transit-isochrone&city=metrotaipei` |
| 等時圈儀表板（圖表） | `http://localhost/dashboard?index=transit-isochrone&city=metrotaipei` |
| 最後一哩路儀表板 | `http://localhost/dashboard?index=last-mile&city=metrotaipei` |
| 人行道路網圖資 | `http://localhost/mapview?index=map-layers-metrotaipei&city=metrotaipei` |

---

## 快速驗證資料是否正確進入 DB

```powershell
# 行人事故資料
docker exec postgres-data psql -U postgres -d dashboard -c "SELECT COUNT(*) FROM public.traffic_pedestrian_accident_taipei;"
docker exec postgres-data psql -U postgres -d dashboard -c "SELECT COUNT(*) FROM public.traffic_pedestrian_accident_ntpc;"

# 等時圈覆蓋率
docker exec postgres-data psql -U postgres -d dashboard -c "SELECT COUNT(*) FROM public.isochrone_district_coverage;"

# 人口流量資料
docker exec postgres-data psql -U postgres -d dashboard -c "SELECT COUNT(*) FROM public.population_flow_daytime;"
docker exec postgres-data psql -U postgres -d dashboard -c "SELECT COUNT(*) FROM public.population_flow_nighttime;"

# 步行路網組件
docker exec postgres-manager psql -U postgres -d dashboardmanager -c "SELECT c.index, qc.city FROM public.components c JOIN public.query_charts qc ON c.index = qc.index WHERE c.index = 'walkable_osm_taipei' ORDER BY qc.city;"

# 人行道寬度統計
docker exec postgres-data psql -U postgres -d dashboard -c "SELECT COUNT(*) FROM public.sidewalk_width_stats;"

# 行人事故圓餅圖統計
docker exec postgres-data psql -U postgres -d dashboard -c "SELECT COUNT(*) FROM public.ped_accident_weather_stats;"
docker exec postgres-data psql -U postgres -d dashboard -c "SELECT COUNT(*) FROM public.ped_accident_subtype_stats;"

# component_charts 欄位確認（stacked / scrollable）
docker exec postgres-manager psql -U postgres -d dashboardmanager -c "SELECT index, stacked, scrollable FROM public.component_charts WHERE index LIKE '%isochrone%' OR index LIKE '%population_flow%' OR index = 'sidewalk_width';"
```

預期結果：
- `traffic_pedestrian_accident_taipei`：數千筆
- `traffic_pedestrian_accident_ntpc`：數千筆
- `isochrone_district_coverage`：123 筆（台北 12 區 × 3 交通工具 + 新北 29 區 × 3）
- `population_flow_daytime`：41 筆
- `population_flow_nighttime`：41 筆
- `walkable_osm_taipei`：應出現 2 列（metrotaipei 一個、taipei 一個）
- `sidewalk_width_stats`：41 筆（雙北 41 個行政區）
- `ped_accident_weather_stats`：7 筆、`ped_accident_subtype_stats`：18 筆
- 等時圈 `stacked = t`、人口流量 `scrollable = t`、人行道寬度 `stacked = t`

---

## 常見問題

**Q：跑步驟二出現 `already exists` 錯誤？**
- 正常，可忽略。確認最後有 `COPY xxx` 即代表資料成功匯入

**Q：行政區圖（DistrictChart）是空的？**
- 確認 `metro_district_boundaries` 有資料：
  ```powershell
  docker exec postgres-data psql -U postgres -d dashboard -c "SELECT COUNT(*) FROM public.metro_district_boundaries;"
  ```
  應該要是 41（台北 12 + 新北 29）。若是 0，重新跑步驟二

**Q：`compute_isochrone_coverage.py` 連不上 DB？**
- 確認 Docker 有在跑：`docker ps`
- 確認 `docker/.env` 裡有 `DB_DASHBOARD_PASSWORD`

**Q：等時圈長條圖沒有疊加（顯示為分組而非疊加）？**
- 確認有重新跑步驟四（`setup_isochrone_components.sql`），這個 SQL 會設定 `stacked = true`
- 確認有重啟 `dashboard-be`

**Q：人口流量長條圖沒有捲動工具列？**
- 確認有跑步驟五（`population_flow_migration.sql`），這個 SQL 會設定 `scrollable = true`
- 確認有重啟 `dashboard-be`

**Q：步行路網 toggle 打開後地圖沒有出現線條？**
- 確認有執行步驟六（`setup_walkable_components.sql`）
- 確認有重啟 `dashboard-fe`（`docker restart dashboard-fe`）
- 重整後等待約 3–10 秒讓 GeoJSON 載入完成

**Q：組件全部顯示問號（?????）或 400 錯誤？**
- SQL 中文字元損毀（PowerShell 直接 `<` 重導向會亂碼），重新用 `docker cp` 方式重跑對應步驟

**Q：跑 Python 腳本出現 `UnicodeDecodeError: 'cp950'`？**
- Windows 預設編碼問題。在 PowerShell 執行前先設定：
  ```powershell
  $env:PYTHONUTF8 = "1"
  python Taipei-City-Dashboard-DE/compute_sidewalk_stats.py
  ```

**Q：人行道寬度長條圖是空的？**
- 確認有跑 `compute_sidewalk_stats.py`（需在步驟七之後）
- 確認有重啟 `dashboard-be`

**Q：行人事故圓餅圖是空的？**
- 確認有跑 `etl_pedestrian_pie.py`（CSV 資料在 `data/NPA_TMA2_*.csv`）
- 確認有跑 `setup_pedestrian_pie_components.sql`

**Q：AI 分析按鈕沒有回應？**
- 確認 `docker/.env` 裡有設定 `ANTHROPIC_API_KEY`
