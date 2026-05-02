-- 在 postgres-manager (dashboardmanager DB) 中新增行人安全儀表板組件
-- 連線：localhost:5432 / dashboardmanager DB
-- 執行前請確認 traffic_pedestrian_* 資料表已有資料

-- ============================================================
-- 1. components 表（組件基本資訊）
-- ============================================================

INSERT INTO public.components (index, name) VALUES
    ('traffic_pedestrian_heatmap',         '行人事故熱區'),
    ('traffic_pedestrian_hourly_taipei',   '行人事故時段分析'),
    ('traffic_pedestrian_yearly_trend',    '行人事故年度趨勢'),
    ('traffic_pedestrian_hotspot_ranking', '行人事故高風險路口排名')
ON CONFLICT (index) DO UPDATE SET name = EXCLUDED.name;


-- ============================================================
-- 2. component_charts 表（圖表設定）
-- ============================================================

INSERT INTO public.component_charts (index, color, types, unit) VALUES
    ('traffic_pedestrian_heatmap',
        ARRAY['#FFF9C4', '#FFB300', '#E65100', '#B71C1C'],
        ARRAY['DistrictChart'],
        '件'),
    ('traffic_pedestrian_hourly_taipei',
        ARRAY['#7B1818', '#B71C1C', '#FF6F00', '#FFD180', '#FFF9C4'],
        ARRAY['HeatmapChart'],
        '件'),
    ('traffic_pedestrian_yearly_trend',
        ARRAY['#E53935', '#1E88E5'],
        ARRAY['TimelineSeparateChart'],
        '件'),
    ('traffic_pedestrian_hotspot_ranking',
        ARRAY['#B71C1C'],
        ARRAY['BarChart'],
        '件')
ON CONFLICT (index) DO UPDATE
    SET color = EXCLUDED.color,
        types = EXCLUDED.types,
        unit  = EXCLUDED.unit;


-- ============================================================
-- 3. component_maps 表（地圖圖層設定，供 C1 使用）
-- ============================================================

INSERT INTO public.component_maps (index, title, type, source, size, icon, paint, property) VALUES
    (
        'traffic_pedestrian_heatmap',

        '行人事故熱點',
        'circle',
        'geojson',
        'small',
        NULL,
        '{
            "circle-color": [
                "interpolate", ["linear"],
                ["get", "accident_count"],
                1,  "#FFF9C4",
                5,  "#FFB300",
                10, "#E65100",
                20, "#B71C1C"
            ],
            "circle-radius": [
                "interpolate", ["linear"], ["zoom"],
                10, ["interpolate", ["linear"], ["get", "accident_count"],
                      1, 1,   5, 2,   10, 3,   20, 5],
                13, ["interpolate", ["linear"], ["get", "accident_count"],
                      1, 3,   5, 5,   10, 7,   20, 10],
                16, ["interpolate", ["linear"], ["get", "accident_count"],
                      1, 5,   5, 8,   10, 12,  20, 16]
            ],
            "circle-opacity": [
                "interpolate", ["linear"], ["zoom"],
                10, 0.6,
                13, 0.85
            ],
            "circle-stroke-width": 0,
            "circle-blur": 0.1
        }',
        '[
            {"key": "accident_count", "name": "事故件數"},
            {"key": "death_count",    "name": "死亡人數"},
            {"key": "injury_count",   "name": "受傷人數"},
            {"key": "top_cause",      "name": "最主要肇因"},
            {"key": "top_hour",       "name": "高峰時段"},
            {"key": "near_location",  "name": "鄰近路口"},
            {"key": "city",           "name": "城市"}
        ]'
    )
ON CONFLICT (index) DO UPDATE
    SET title    = EXCLUDED.title,
        type     = EXCLUDED.type,
        source   = EXCLUDED.source,
        size     = EXCLUDED.size,
        icon     = EXCLUDED.icon,
        paint    = EXCLUDED.paint,
        property = EXCLUDED.property;

-- 台北市專用 map config（下拉選單切換用）
INSERT INTO public.component_maps (index, title, type, source, size, icon, paint, property)
SELECT 'traffic_pedestrian_heatmap_taipei', '行人事故熱點(臺北)', type, source, size, icon, paint, property
FROM public.component_maps WHERE index = 'traffic_pedestrian_heatmap'
ON CONFLICT (index) DO UPDATE
    SET title    = EXCLUDED.title,
        type     = EXCLUDED.type,
        source   = EXCLUDED.source,
        size     = EXCLUDED.size,
        icon     = EXCLUDED.icon,
        paint    = EXCLUDED.paint,
        property = EXCLUDED.property;


-- ============================================================
-- 4. query_charts 表
-- ============================================================

-- 清除所有舊的 pedestrian query_charts（確保重跑時能正確更新）
DELETE FROM public.query_charts WHERE index LIKE 'traffic_pedestrian%';

-- C1：台北市行人事故熱區地圖 (taipei)
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'traffic_pedestrian_heatmap',
    NULL,
    (SELECT ARRAY[id] FROM public.component_maps WHERE index = 'traffic_pedestrian_heatmap' LIMIT 1),
    '{}',
    '2022-01-01', 'now', 1, 'year',
    '警察局交通大隊、內政部警政署',
    '台北市各行政區行人事故件數（2022年起）。',
    '以台北市各行政區為單位，統計2022年以來的行人事故件數，展示事故熱點分布。',
    '識別事故最多的行政區，輔助政策改善優先順序規劃。',
    ARRAY['https://data.taipei/dataset/detail?id=2f238b4f-1b27-4085-93e9-d684ef0e2735', 'https://data.gov.tw/dataset/12818', 'https://data.gov.tw/dataset/13139', 'https://data.gov.tw/dataset/161199', 'https://data.gov.tw/dataset/167905', 'https://data.gov.tw/dataset/172969', 'https://data.gov.tw/dataset/177136'],
    ARRAY['doit'],
    NOW(), NOW(),
    'two_d',
    E'SELECT district_name AS x_axis, SUM(accident_count)::INT AS data\nFROM traffic_pedestrian_district_stats\nWHERE city_name = ''臺北市''\nGROUP BY district_name\nORDER BY x_axis',
    NULL,
    'taipei'
);

-- C1：雙北行人事故熱區地圖 (metrotaipei)
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'traffic_pedestrian_heatmap',
    NULL,
    (SELECT ARRAY[id] FROM public.component_maps WHERE index = 'traffic_pedestrian_heatmap' LIMIT 1),
    '{}',
    '2022-01-01', 'now', 1, 'year',
    '警察局交通大隊、內政部警政署',
    '雙北各行政區行人事故件數（2022年起）。',
    '以雙北各行政區為單位，統計2022年以來的行人事故件數，展示事故熱點分布。',
    '識別事故最多的行政區，輔助政策改善優先順序規劃。',
    ARRAY['https://data.taipei/dataset/detail?id=2f238b4f-1b27-4085-93e9-d684ef0e2735', 'https://data.gov.tw/dataset/12818', 'https://data.gov.tw/dataset/13139', 'https://data.gov.tw/dataset/161199', 'https://data.gov.tw/dataset/167905', 'https://data.gov.tw/dataset/172969', 'https://data.gov.tw/dataset/177136'],
    ARRAY['doit'],
    NOW(), NOW(),
    'two_d',
    E'SELECT district_name AS x_axis, SUM(accident_count)::INT AS data\nFROM traffic_pedestrian_district_stats\nGROUP BY district_name\nORDER BY x_axis',
    NULL,
    'metrotaipei'
);

-- C1-taipei：臺北市版本（下拉選單用）
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
)
SELECT
    index, history_config,
    (SELECT ARRAY[id] FROM public.component_maps WHERE index = 'traffic_pedestrian_heatmap_taipei' LIMIT 1),
    map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, NOW(), NOW(),
    'two_d',
    E'SELECT district_name AS x_axis, SUM(accident_count)::INT AS data\nFROM traffic_pedestrian_district_stats\nWHERE city_name = ''臺北市''\nGROUP BY district_name\nORDER BY x_axis',
    NULL,
    'taipei'
FROM public.query_charts
WHERE index = 'traffic_pedestrian_heatmap' AND city = 'metrotaipei'
ON CONFLICT DO NOTHING;

-- C2：雙北行人事故時段分析（三個 city 版本，對應後端 query_charts.city 篩選）

-- 共用 SQL 片段（CASE weekday）抽出為說明，實際各版本重複寫入
-- city = taipei：只查臺北市
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'traffic_pedestrian_hourly_taipei',
    NULL,
    '{}',
    '{}',
    '2022-01-01',
    'now',
    1,
    'year',
    '內政部警政署',
    '臺北市行人事故依小時與星期幾的分布熱力格。',
    '以熱力格（HeatmapChart）呈現臺北市近三年行人事故在不同時段（0–23時）與不同星期的分布情形。顏色越深代表事故件數越多，可用於識別高風險時段，輔助交通規劃與執法資源配置。',
    '識別行人事故高峰時段（如通勤時段），協助決定執法資源部署時間或號誌調整時機。',
    ARRAY['https://data.gov.tw/dataset/12818', 'https://data.gov.tw/dataset/13139', 'https://data.gov.tw/dataset/161199', 'https://data.gov.tw/dataset/167905', 'https://data.gov.tw/dataset/172969', 'https://data.gov.tw/dataset/177136'],
    ARRAY['doit'],
    NOW(),
    NOW(),
    'three_d',
    E'SELECT x_axis, y_axis, data FROM (\n    SELECT\n        hour::text AS x_axis,\n        CASE EXTRACT(ISODOW FROM make_date(\n            GREATEST(year::int, 2022),\n            GREATEST(month::int, 1),\n            1\n        ))\n            WHEN 1 THEN ''週一''\n            WHEN 2 THEN ''週二''\n            WHEN 3 THEN ''週三''\n            WHEN 4 THEN ''週四''\n            WHEN 5 THEN ''週五''\n            WHEN 6 THEN ''週六''\n            WHEN 7 THEN ''週日''\n        END AS y_axis,\n        COUNT(*)::INT AS data\n    FROM traffic_pedestrian_accident_taipei\n    WHERE year >= 2022 AND hour IS NOT NULL AND month IS NOT NULL\n    GROUP BY hour, y_axis\n) sub\nORDER BY x_axis::int, CASE y_axis WHEN ''週一'' THEN 7 WHEN ''週二'' THEN 6 WHEN ''週三'' THEN 5 WHEN ''週四'' THEN 4 WHEN ''週五'' THEN 3 WHEN ''週六'' THEN 2 WHEN ''週日'' THEN 1 ELSE 0 END',
    NULL,
    'taipei'
);

-- city = metrotaipei：雙北合計
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'traffic_pedestrian_hourly_taipei',
    NULL,
    '{}',
    '{}',
    '2022-01-01',
    'now',
    1,
    'year',
    '內政部警政署',
    '雙北行人事故依小時與星期幾的分布熱力格。',
    '以熱力格（HeatmapChart）呈現雙北近三年行人事故在不同時段（0–23時）與不同星期的合計分布情形。',
    '識別雙北行人事故高峰時段，協助決定執法資源部署時間或號誌調整時機。',
    ARRAY['https://data.gov.tw/dataset/12818', 'https://data.gov.tw/dataset/13139', 'https://data.gov.tw/dataset/161199', 'https://data.gov.tw/dataset/167905', 'https://data.gov.tw/dataset/172969', 'https://data.gov.tw/dataset/177136'],
    ARRAY['doit'],
    NOW(),
    NOW(),
    'three_d',
    E'SELECT x_axis, y_axis, data FROM (\n    SELECT\n        hour::text AS x_axis,\n        CASE EXTRACT(ISODOW FROM make_date(\n            GREATEST(year::int, 2022),\n            GREATEST(month::int, 1),\n            1\n        ))\n            WHEN 1 THEN ''週一''\n            WHEN 2 THEN ''週二''\n            WHEN 3 THEN ''週三''\n            WHEN 4 THEN ''週四''\n            WHEN 5 THEN ''週五''\n            WHEN 6 THEN ''週六''\n            WHEN 7 THEN ''週日''\n        END AS y_axis,\n        COUNT(*)::INT AS data\n    FROM (\n        SELECT hour, year, month FROM traffic_pedestrian_accident_taipei WHERE year >= 2022\n        UNION ALL\n        SELECT hour, year, month FROM traffic_pedestrian_accident_ntpc WHERE year >= 2022\n    ) combined\n    WHERE hour IS NOT NULL AND month IS NOT NULL\n    GROUP BY hour, y_axis\n) sub\nORDER BY x_axis::int, CASE y_axis WHEN ''週一'' THEN 7 WHEN ''週二'' THEN 6 WHEN ''週三'' THEN 5 WHEN ''週四'' THEN 4 WHEN ''週五'' THEN 3 WHEN ''週六'' THEN 2 WHEN ''週日'' THEN 1 ELSE 0 END',
    NULL,
    'metrotaipei'
);

-- C3：雙北行人事故年度趨勢 (metrotaipei)
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'traffic_pedestrian_yearly_trend',
    NULL,
    '{}',
    '{}',
    'static',
    NULL,
    1,
    'year',
    '警察局交通大隊、內政部警政署',
    '雙北行人事故年度趨勢，呈現台北與新北近年事故件數變化。',
    '以雙軸圖呈現臺北市（長條）與新北市（折線）歷年行人事故件數。可觀察 2023 年行人安全改革後的效果，以及雙北城市間的改善差距，作為政策評估的參考依據。',
    '評估行人安全政策成效，比較雙北改善進度，找出需要加強的城市或年度。',
    ARRAY[
        'https://data.taipei/dataset/detail?id=2f238b4f-1b27-4085-93e9-d684ef0e2735',
        'https://data.gov.tw/dataset/13139'
    ],
    ARRAY['doit'],
    NOW(),
    NOW(),
    'time',
    E'SELECT\n    make_date(year::int, 1, 1) AS x_axis,\n    CASE WHEN city = ''taipei'' THEN ''台北市'' WHEN city = ''ntpc'' THEN ''新北市'' ELSE city END AS y_axis,\n    accident_count AS data\nFROM traffic_pedestrian_yearly_trend\nWHERE year > 0\nORDER BY year, city',
    NULL,
    'metrotaipei'
);

-- C4：行人事故高風險路口排名 (metrotaipei)
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'traffic_pedestrian_hotspot_ranking',
    NULL,
    '{}',
    '{}',
    '2022-01-01',
    'now',
    1,
    'year',
    '警察局交通大隊、內政部警政署',
    '近三年雙北行人事故最多的前 20 個路口排名。',
    '列出雙北近三年行人事故件數最多的前 20 個熱點位置。事故件數越高代表該路口的行人安全狀況越需要關注，建議相關單位評估是否需要改善交通設計、號誌規劃或加強執法。',
    '識別最需要優先改善的路口，供政府規劃改善工程（行人保護時相、縮短右轉等待、行人庇護島等）的順序參考。',
    ARRAY[
        'https://data.taipei/dataset/detail?id=2f238b4f-1b27-4085-93e9-d684ef0e2735',
        'https://data.gov.tw/dataset/13139'
    ],
    ARRAY['doit'],
    NOW(),
    NOW(),
    'two_d',
    E'SELECT\n    COALESCE(\n        NULLIF(near_location, ''''),\n        ROUND(center_lng::numeric, 4)::text || '', '' || ROUND(center_lat::numeric, 4)::text\n    ) AS x_axis,\n    accident_count AS data\nFROM traffic_pedestrian_hotspot\nORDER BY accident_count DESC\nLIMIT 20',
    NULL,
    'metrotaipei'
);

-- C4-taipei：臺北市版本
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
)
SELECT
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, NOW(), NOW(),
    query_type,
    E'SELECT\n    COALESCE(\n        NULLIF(near_location, ''''),\n        ROUND(center_lng::numeric, 4)::text || '', '' || ROUND(center_lat::numeric, 4)::text\n    ) AS x_axis,\n    accident_count AS data\nFROM traffic_pedestrian_hotspot\nWHERE city = ''taipei''\nORDER BY accident_count DESC\nLIMIT 20',
    query_history,
    'taipei'
FROM public.query_charts
WHERE index = 'traffic_pedestrian_hotspot_ranking' AND city = 'metrotaipei'
ON CONFLICT DO NOTHING;


-- ============================================================
-- 5. dashboards 表（建立行人安全儀表板）
-- ============================================================

INSERT INTO public.dashboards (index, name, components, icon, created_at, updated_at)
SELECT
    'pedestrian-safety',
    '行人安全地圖',
    ARRAY(
        SELECT id FROM public.components
        WHERE index IN (
            'traffic_pedestrian_heatmap',
            'traffic_pedestrian_hourly_taipei',
            'traffic_pedestrian_yearly_trend',
            'traffic_pedestrian_hotspot_ranking'
        )
        ORDER BY ARRAY_POSITION(
            ARRAY[
                'traffic_pedestrian_heatmap',
                'traffic_pedestrian_hourly_taipei',
                'traffic_pedestrian_yearly_trend',
                'traffic_pedestrian_hotspot_ranking'
            ],
            index
        )
    ),
    'directions_walk',
    NOW(),
    NOW()
ON CONFLICT (index) DO UPDATE
    SET name       = EXCLUDED.name,
        components = EXCLUDED.components,
        icon       = EXCLUDED.icon,
        updated_at = NOW();


-- ============================================================
-- 6. dashboard_groups 表（將儀表板加入 metrotaipei group）
-- ============================================================

INSERT INTO public.dashboard_groups (dashboard_id, group_id)
SELECT
    d.id,
    g.id
FROM public.dashboards d
CROSS JOIN public.groups g
WHERE d.index = 'pedestrian-safety'
  AND g.name IN ('public', 'metrotaipei')
ON CONFLICT DO NOTHING;


-- ============================================================
-- 驗證
-- ============================================================
SELECT
    c.id,
    c.index,
    c.name,
    cc.types,
    qc.city,
    qc.query_type
FROM public.components c
JOIN public.component_charts cc ON c.index = cc.index
JOIN public.query_charts qc ON c.index = qc.index
WHERE c.index LIKE 'traffic_pedestrian%'
ORDER BY c.index, qc.city;
