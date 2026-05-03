"""Geocode Taipei city hotspots — run inside Docker on br_dashboard network."""
import time
import requests
import psycopg2

conn = psycopg2.connect(
    host="postgres-data", port=5432,
    dbname="dashboard", user="postgres", password="lja2203125"
)
cur = conn.cursor()

cur.execute("""
    SELECT id, center_lat, center_lng, accident_count
    FROM traffic_pedestrian_hotspot
    WHERE city = 'taipei'
      AND (near_location IS NULL OR near_location = '')
    ORDER BY accident_count DESC
    LIMIT 30
""")
rows = cur.fetchall()
print(f"需處理 {len(rows)} 筆台北市")

for row_id, lat, lng, cnt in rows:
    url = (
        f"https://nominatim.openstreetmap.org/reverse"
        f"?lat={lat}&lon={lng}&format=json&zoom=17&accept-language=zh-TW"
    )
    try:
        r = requests.get(url, headers={"User-Agent": "taipei-dashboard/1.0"}, timeout=10)
        d = r.json()
        addr = d.get("address", {})
        road = addr.get("road") or addr.get("pedestrian") or addr.get("path") or ""
        dist = addr.get("city_district") or addr.get("suburb") or ""
        name = f"{dist}{road}" if dist and dist not in road else road
        print(f"  [{cnt}件] ({float(lat):.3f},{float(lng):.3f}) -> {name}")
        if name:
            cur.execute(
                "UPDATE traffic_pedestrian_hotspot SET near_location=%s WHERE id=%s",
                (name, row_id)
            )
            conn.commit()
    except Exception as e:
        print(f"  error ({lat},{lng}): {e}")
    time.sleep(1.1)

cur.close()
conn.close()
print("完成")
