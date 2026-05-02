#!/usr/bin/env python3
"""
計算雙北各行政區對各交通工具等時圈的步行覆蓋率
輸出至 DB: public.isochrone_district_coverage

Usage:
    python compute_isochrone_coverage.py
"""

import json
import os
import psycopg2
from datetime import datetime, timezone
from pyproj import Transformer
from shapely.geometry import shape
from shapely.ops import unary_union, transform

def _load_env(path):
    """簡單讀取 .env 檔案"""
    env = {}
    if not os.path.exists(path):
        return env
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    return env

_ENV_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docker", ".env")
_ENV = _load_env(_ENV_PATH)
DB_PASSWORD = os.environ.get("DB_DASHBOARD_PASSWORD") or _ENV.get("DB_DASHBOARD_PASSWORD", "postgres")
DB_HOST     = os.environ.get("DB_HOST", "localhost")
DB_PORT     = int(os.environ.get("DB_PORT", "5433"))

# ── 路徑設定 ──────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MAPDATA_DIR = os.path.join(SCRIPT_DIR, "..", "Taipei-City-Dashboard-FE", "public", "mapData")

# ── 投影轉換器（WGS84 → EPSG:3826 用於面積計算）────────────────
_to_proj = Transformer.from_crs("EPSG:4326", "EPSG:3826", always_xy=True)

def to_projected(geom):
    return transform(lambda x, y: _to_proj.transform(x, y), geom)


def load_geojson(path):
    with open(path, "rb") as f:
        return json.loads(f.read().decode("utf-8"))


def load_districts():
    """讀取雙北行政區邊界，回傳 {city: [(name, eng, projected_polygon), ...]}"""
    d = load_geojson(os.path.join(MAPDATA_DIR, "metrotaipei_town.geojson"))
    taipei, newtaipei = [], []
    for feat in d["features"]:
        p = feat["properties"]
        geom = to_projected(shape(feat["geometry"]))
        entry = (p["TNAME"], p["TOWNENG"], geom)
        if p["COUNTYID"] == "A":
            taipei.append(entry)
        else:
            newtaipei.append(entry)
    print(f"  台北: {len(taipei)} 區，新北: {len(newtaipei)} 區")
    return {"taipei": taipei, "newtaipei": newtaipei, "metrotaipei": taipei + newtaipei}


def load_isochrone_by_time(path):
    """讀取等時圈 GeoJSON，回傳 {5: projected_geom, 10: ..., 15: ...}"""
    d = load_geojson(path)
    by_time = {}
    for feat in d["features"]:
        minutes = feat["properties"]["minutes"]
        geom = to_projected(shape(feat["geometry"]))
        by_time[minutes] = geom
    return by_time


TRANSPORT_CONFIGS = [
    ("bus", "公車"),
    ("mrt", "捷運"),
    ("tra", "台鐵"),
]

# city_key → (display_name, geojson_suffix)
# metrotaipei GeoJSON 的檔名不帶城市後綴（直接是 isochrone_xxx_walk.geojson）
CITY_MAP = {
    "taipei":      ("台北", "taipei"),
    "metrotaipei": ("雙北", ""),
}


def compute_coverage(district_geom, isochrone_by_time):
    """計算各時間帶的覆蓋率(%) 與 incremental 值"""
    district_area = district_geom.area
    if district_area == 0:
        return None

    results = {}
    for minutes in (5, 10, 15):
        iso = isochrone_by_time.get(minutes)
        if iso is None:
            results[minutes] = 0.0
            continue
        try:
            inter = district_geom.intersection(iso)
            results[minutes] = min(100.0, inter.area / district_area * 100)
        except Exception:
            results[minutes] = 0.0

    return {
        "coverage_5min":  round(results[5],  2),
        "coverage_10min": round(results[10], 2),
        "coverage_15min": round(results[15], 2),
        "incremental_5min":  round(results[5],  2),
        "incremental_10min": round(results[10] - results[5],  2),
        "incremental_15min": round(results[15] - results[10], 2),
    }


def main():
    print("讀取行政區邊界...")
    districts = load_districts()

    rows = []
    now = datetime.now(timezone.utc)

    for transport_type, transport_name in TRANSPORT_CONFIGS:
        print(f"\n=== {transport_name} ===")
        for city_key, (city_name, geojson_suffix) in CITY_MAP.items():
            suffix_part = f"_{geojson_suffix}" if geojson_suffix else ""
            geojson_path = os.path.join(
                MAPDATA_DIR, f"isochrone_{transport_type}_walk{suffix_part}.geojson"
            )
            if not os.path.exists(geojson_path):
                print(f"  [{city_name}] 找不到 {geojson_path}，跳過")
                continue

            print(f"  [{city_name}] 載入等時圈...")
            iso_by_time = load_isochrone_by_time(geojson_path)

            for dist_name, dist_eng, dist_geom in districts[city_key]:
                cov = compute_coverage(dist_geom, iso_by_time)
                if cov is None:
                    continue
                rows.append({
                    "data_time":       now,
                    "transport_type":  transport_type,
                    "city":            city_key,
                    "district_name":   dist_name,
                    "district_eng":    dist_eng,
                    **cov,
                })
                print(f"    {dist_name}: 5min={cov['coverage_5min']}% "
                      f"10min={cov['coverage_10min']}% "
                      f"15min={cov['coverage_15min']}%")

    print(f"\n共 {len(rows)} 筆，寫入 DB...")

    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT,
        dbname="dashboard", user="postgres", password=DB_PASSWORD
    )
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS public.isochrone_district_coverage (
            id               SERIAL PRIMARY KEY,
            data_time        TIMESTAMP WITH TIME ZONE,
            transport_type   VARCHAR(10),
            city             VARCHAR(20),
            district_name    VARCHAR(30),
            district_eng     VARCHAR(60),
            coverage_5min    FLOAT,
            coverage_10min   FLOAT,
            coverage_15min   FLOAT,
            incremental_5min  FLOAT,
            incremental_10min FLOAT,
            incremental_15min FLOAT
        );
    """)

    cur.execute("TRUNCATE public.isochrone_district_coverage;")

    cur.executemany("""
        INSERT INTO public.isochrone_district_coverage
            (data_time, transport_type, city, district_name, district_eng,
             coverage_5min, coverage_10min, coverage_15min,
             incremental_5min, incremental_10min, incremental_15min)
        VALUES
            (%(data_time)s, %(transport_type)s, %(city)s, %(district_name)s, %(district_eng)s,
             %(coverage_5min)s, %(coverage_10min)s, %(coverage_15min)s,
             %(incremental_5min)s, %(incremental_10min)s, %(incremental_15min)s)
    """, rows)

    conn.commit()
    cur.close()
    conn.close()
    print("完成！")


if __name__ == "__main__":
    main()
