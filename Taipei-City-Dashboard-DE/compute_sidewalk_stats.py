"""
計算各行政區人行道寬度分布統計（紅/黃/綠比例）
輸出至 public.sidewalk_width_stats

紅：SW_WTH < 1.25m
黃：1.25m <= SW_WTH < 2.5m
綠：SW_WTH >= 2.5m
"""

import json
import os
import psycopg2
from collections import defaultdict

# ── 環境設定 ──────────────────────────────────────────────────
def _load_env(path):
    env = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return env

_ENV_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docker", ".env")
_ENV = _load_env(_ENV_PATH)
DB_PASSWORD = os.environ.get("DB_DASHBOARD_PASSWORD") or _ENV.get("DB_DASHBOARD_PASSWORD", "postgres")
DB_HOST     = os.environ.get("DB_HOST", "localhost")
DB_PORT     = int(os.environ.get("DB_PORT", "5433"))

# ── 路徑設定 ──────────────────────────────────────────────────
BASE_DIR    = os.path.dirname(os.path.abspath(__file__))
MAPDATA_DIR = os.path.join(BASE_DIR, "..", "Taipei-City-Dashboard-FE", "public", "mapData")

FILES = [
    ("sidewalk_width_taipei.geojson",     "taipei"),
    ("sidewalk_width_newtaipei.geojson",  "newtaipei"),
]


def categorize(wth):
    if wth is None:
        return None
    if wth < 1.25:
        return "red"
    elif wth < 2.5:
        return "yellow"
    else:
        return "green"


def compute_stats():
    # { (city, district_name) -> {red, yellow, green, total} }
    stats = defaultdict(lambda: {"red": 0, "yellow": 0, "green": 0, "total": 0})

    for filename, city in FILES:
        path = os.path.join(MAPDATA_DIR, filename)
        if not os.path.exists(path):
            print(f"  找不到 {path}，跳過")
            continue

        print(f"  讀取 {filename} ...")
        with open(path, encoding="utf-8") as f:
            data = json.load(f)

        for feat in data["features"]:
            props   = feat["properties"]
            district = props.get("VILL_NAME", "").strip()
            wth      = props.get("SWW_WTH")

            if not district or wth is None:
                continue

            cat = categorize(float(wth))
            if cat is None:
                continue

            key = (city, district)
            stats[key][cat]   += 1
            stats[key]["total"] += 1

    return stats


def main():
    print("計算各行政區人行道寬度分布...")
    stats = compute_stats()

    rows = []
    for (city, district_name), counts in stats.items():
        total = counts["total"]
        if total == 0:
            continue
        rows.append({
            "city":          city,
            "district_name": district_name,
            "count_red":     counts["red"],
            "count_yellow":  counts["yellow"],
            "count_green":   counts["green"],
            "total":         total,
            "pct_red":       round(counts["red"]   / total * 100, 1),
            "pct_yellow":    round(counts["yellow"] / total * 100, 1),
            "pct_green":     round(counts["green"]  / total * 100, 1),
        })

    print(f"共 {len(rows)} 個行政區，寫入 DB...")

    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT,
        dbname="dashboard", user="postgres", password=DB_PASSWORD
    )
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS public.sidewalk_width_stats (
            id            SERIAL PRIMARY KEY,
            city          VARCHAR(20),
            district_name VARCHAR(30),
            count_red     INTEGER,
            count_yellow  INTEGER,
            count_green   INTEGER,
            total         INTEGER,
            pct_red       FLOAT,
            pct_yellow    FLOAT,
            pct_green     FLOAT
        )
    """)
    cur.execute("TRUNCATE public.sidewalk_width_stats")

    cur.executemany("""
        INSERT INTO public.sidewalk_width_stats
            (city, district_name, count_red, count_yellow, count_green,
             total, pct_red, pct_yellow, pct_green)
        VALUES
            (%(city)s, %(district_name)s, %(count_red)s, %(count_yellow)s, %(count_green)s,
             %(total)s, %(pct_red)s, %(pct_yellow)s, %(pct_green)s)
    """, rows)

    conn.commit()
    cur.close()
    conn.close()
    print("完成！")

    # 印出預覽
    for r in sorted(rows, key=lambda x: (x["city"], x["district_name"]))[:6]:
        print(f"  {r['city']:12} {r['district_name']:8} 紅{r['pct_red']:5.1f}% 黃{r['pct_yellow']:5.1f}% 綠{r['pct_green']:5.1f}%")


if __name__ == "__main__":
    main()
