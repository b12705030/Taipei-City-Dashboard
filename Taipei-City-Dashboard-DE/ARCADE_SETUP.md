# 騎樓整平模組 — 環境建置說明

> 適用分支：`feature/arcase`
> 包含組件：**騎樓整平累積量**、**騎樓整平涵蓋率**

---

## 前置條件

確認以下環境已就緒（與專案其他模組相同）：

- Docker Desktop 運行中
- 已完成專案基礎 Docker 環境建置（`docker-compose-db.yaml` + `docker-compose.yaml`）
- 以下 container 均在運行：

```
dashboard-fe     ← Node.js 前端開發伺服器
dashboard-be     ← Go 後端
postgres-data    ← 資料 DB（port 5433）
postgres-manager ← 組件設定 DB（port 5432）
nginx
redis
```

驗證 container 狀態：

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

---

## Step 1：切換到 feature/arcase 分支

```bash
git fetch origin
git checkout feature/arcase
git pull origin feature/arcase
```

---

## Step 2：建立資料表並匯入資料（postgres-data）

> `postgres-data` 是存放實際查詢資料的 DB（`dashboard` 資料庫）

```bash
# 複製並執行建表腳本
docker cp Taipei-City-Dashboard-DE/setup_arcade_tables.sql postgres-data:/tmp/
docker exec postgres-data psql -U postgres -d dashboard -f /tmp/setup_arcade_tables.sql

# 複製並匯入騎樓整平資料
docker cp Taipei-City-Dashboard-DE/arcade_all_utf8.sql postgres-data:/tmp/
docker exec postgres-data psql -U postgres -d dashboard -f /tmp/arcade_all_utf8.sql
```

**匯入後應有以下資料表與筆數：**

| 資料表 | 筆數 | 說明 |
|---|---|---|
| `arcade_total_by_district` | 32 | 雙北各行政區累積整平長度 |
| `arcade_yearly_by_city` | 24 | 各縣市逐年整平量 |
| `arcade_yearly_by_district` | 371 | 各行政區逐年整平量 |
| `pedestrian_length_by_district` | 41 | 雙北各行政區人行道總長度（OSM） |

驗證：

```bash
docker exec postgres-data psql -U postgres -d dashboard -c "
SELECT 'arcade_total_by_district' AS t, COUNT(*) FROM public.arcade_total_by_district
UNION ALL
SELECT 'pedestrian_length_by_district', COUNT(*) FROM public.pedestrian_length_by_district;"
```

---

## Step 3：註冊組件設定（postgres-manager）

> `postgres-manager` 是存放儀表板組件設定的 DB（`dashboardmanager` 資料庫）

```bash
docker cp Taipei-City-Dashboard-DE/setup_arcade_components.sql postgres-manager:/tmp/
docker exec postgres-manager psql -U postgres -d dashboardmanager -f /tmp/setup_arcade_components.sql
```

**執行後建立以下組件：**

| index | 名稱 | 圖表類型 |
|---|---|---|
| `arcade_total_district` | 騎樓整平累積量 | 行政區圖 / 橫向長條圖 / 圓餅圖 / 圖例 |
| `arcade_leveling_ratio` | 騎樓整平涵蓋率 | 行政區圖 / 橫向長條圖 |

三個城市版本（taipei / newtaipei / metrotaipei）各自有獨立查詢。

驗證：

```bash
docker exec postgres-manager psql -U postgres -d dashboardmanager -c "
SELECT c.index, c.name, cc.types, qc.city, qc.query_type
FROM public.components c
JOIN public.component_charts cc ON c.index = cc.index
JOIN public.query_charts qc ON c.index = qc.index
WHERE c.index LIKE 'arcade_%'
ORDER BY c.index, qc.city;"
```

預期 **9 筆**（3 組件 × 3 cities）。

---

## Step 4：重啟服務

```bash
docker restart dashboard-fe dashboard-be
```

等待約 10–20 秒後，開啟瀏覽器：`http://localhost`（或 `http://localhost:8080`）

---

## Step 5：確認儀表板

1. 登入後，進入儀表板列表
2. 找到「**騎樓整平指標**」（dashboard index: `arcade-leveling`）
3. 應可看到兩個組件卡片：
   - **騎樓整平累積量**：行政區圖顯示雙北各區整平熱區（台北核心明顯較深）
   - **騎樓整平涵蓋率**：行政區圖顯示涵蓋率，上限 100%

---

## 檔案一覽

### DE（資料工程 / 資料庫）

| 檔案 | 用途 |
|---|---|
| `setup_arcade_tables.sql` | 在 postgres-data 建立 4 個資料表 |
| `arcade_all_utf8.sql` | 匯入雙北騎樓整平及人行道資料 |
| `setup_arcade_components.sql` | 在 postgres-manager 建立組件、圖表、地圖圖層設定 |

### FE（前端）

| 檔案 | 用途 |
|---|---|
| `public/mapData/arcade_total_district.geojson` | 雙北 32 行政區質心點（地圖比例符號） |
| `public/mapData/arcade_total_district_taipei.geojson` | 台北 12 行政區質心點 |
| `public/mapData/arcade_total_by_district.csv` | 原始騎樓整平資料（參考用） |
| `public/mapData/pedestrian_length_by_district.csv` | 雙北各行政區人行道長度（OSM） |
| `src/dashboardComponent/components/DistrictChart.vue` | 修改：unit 為 % 時隱藏總合顯示 |
| `src/dashboardComponent/components/MapLegend.vue` | 修改：支援從 map paint 自動生成圖例 |
| `src/assets/configs/apexcharts/chartTypes.js` | 修改：MapLegend 加入 two_d 支援，標籤改為「圖例」 |

---

## 常見問題

**Q：postgres-data 的 DB 名稱是什麼？**
A：`dashboard`（環境變數 `DB_DASHBOARD_DBNAME`，通常為 `dashboard`）

**Q：postgres-manager 的 DB 名稱是什麼？**
A：`dashboardmanager`（環境變數 `DB_MANAGER_DBNAME`）

**Q：兩個 DB 的連線資訊？**

| | postgres-data | postgres-manager |
|---|---|---|
| host（本機）| `localhost` | `localhost` |
| port（本機）| `5433` | `5432` |
| user | `postgres` | `postgres` |
| DB | `dashboard` | `dashboardmanager` |

**Q：執行 SQL 後儀表板沒有更新？**
A：執行 `docker restart dashboard-be` 清除後端快取。

**Q：組件資訊點擊沒反應？**
A：`setup_arcade_components.sql` 已包含將 `b12705030` 新增至 `contributors` 表的語句，重新執行 Step 3 即可。
