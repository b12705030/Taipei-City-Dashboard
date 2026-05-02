-- 人行道寬度指標 component setup
-- 以 SW_WTH 欄位依 1.25m / 2.5m 斷點分三色（紅/黃/綠）顯示

-- ── 1. component_maps ─────────────────────────────────────────
INSERT INTO public.component_maps (id, index, title, type, source, size, icon, paint, property)
VALUES
(108, 'sidewalk_width_taipei', '人行道寬度（台北市）', 'fill', 'geojson', NULL, NULL,
'{
    "fill-color": [
        "step", ["get", "SW_WTH"],
        "#E53935",
        1.25, "#FFC107",
        2.5, "#4CAF50"
    ],
    "fill-opacity": [
        "interpolate", ["linear"], ["zoom"],
        12, 0.45,
        16, 0.8
    ]
}',
'[
    {"key": "NAME",     "name": "道路名稱"},
    {"key": "SW_WTH",  "name": "人行道寬度(m)"},
    {"key": "SWW_WTH", "name": "人行道淨寬(m)"},
    {"key": "SW_LENG", "name": "人行道長度(m)"},
    {"key": "VILL_NAME","name": "鄉鎮"}
]'),
(109, 'sidewalk_width_newtaipei', '人行道寬度（新北市）', 'fill', 'geojson', NULL, NULL,
'{
    "fill-color": [
        "step", ["get", "SW_WTH"],
        "#E53935",
        1.25, "#FFC107",
        2.5, "#4CAF50"
    ],
    "fill-opacity": [
        "interpolate", ["linear"], ["zoom"],
        12, 0.45,
        16, 0.8
    ]
}',
'[
    {"key": "NAME",     "name": "道路名稱"},
    {"key": "SW_WTH",  "name": "人行道寬度(m)"},
    {"key": "SWW_WTH", "name": "人行道淨寬(m)"},
    {"key": "SW_LENG", "name": "人行道長度(m)"},
    {"key": "VILL_NAME","name": "鄉鎮"}
]')
ON CONFLICT (id) DO UPDATE SET
    index   = EXCLUDED.index,
    title   = EXCLUDED.title,
    type    = EXCLUDED.type,
    source  = EXCLUDED.source,
    paint   = EXCLUDED.paint,
    property = EXCLUDED.property;

-- ── 2. component_charts ───────────────────────────────────────
-- 紅：< 1.25m、黃：1.25–2.5m、綠：≥ 2.5m
INSERT INTO public.component_charts (index, color, types, unit, stacked, scrollable)
VALUES (
    'sidewalk_width',
    ARRAY['#E53935', '#FFC107', '#4CAF50'],
    ARRAY['MapLegend'],
    '',
    false,
    false
)
ON CONFLICT (index) DO UPDATE SET
    color  = EXCLUDED.color,
    types  = EXCLUDED.types;

-- ── 3. component ──────────────────────────────────────────────
INSERT INTO public.components (index, name)
VALUES ('sidewalk_width', '人行道寬度指標')
ON CONFLICT (index) DO UPDATE SET
    name       = EXCLUDED.name,
    updated_at = NOW();

-- ── 4. query_charts（台北市 & 雙北）──────────────────────────
-- 先刪再插（避免重複）
DELETE FROM public.query_charts WHERE index = 'sidewalk_width';

INSERT INTO public.query_charts
    (index, city, query_type, map_config_ids, created_at, updated_at,
     time_from, time_to, update_freq, update_freq_unit, source, short_desc, long_desc, query_chart)
VALUES
    ('sidewalk_width', 'taipei',      'map_legend', ARRAY[108],     NOW(), NOW(), 'static', NULL, 1, 'year',
     '全國人行道資料（內政部）', '台北市人行道寬度指標', NULL,
     E'SELECT unnest(ARRAY[''< 1.25m（窄）'', ''1.25–2.5m（一般）'', ''≥ 2.5m（寬）'']) AS name, ''fill'' AS type'),
    ('sidewalk_width', 'metrotaipei', 'map_legend', ARRAY[108,109], NOW(), NOW(), 'static', NULL, 1, 'year',
     '全國人行道資料（內政部）', '雙北人行道寬度指標', NULL,
     E'SELECT unnest(ARRAY[''< 1.25m（窄）'', ''1.25–2.5m（一般）'', ''≥ 2.5m（寬）'']) AS name, ''fill'' AS type');

-- ── 5. 加入 map-layers 儀表板 ─────────────────────────────────
-- 取得新 component id
DO $$
DECLARE
    new_comp_id INTEGER;
BEGIN
    SELECT id INTO new_comp_id FROM public.components WHERE index = 'sidewalk_width';

    -- 更新兩個 map-layers 儀表板（id 106 和 359）
    UPDATE public.dashboards
    SET components = array_append(components, new_comp_id),
        updated_at = NOW()
    WHERE index IN ('map-layers-taipei', 'map-layers-metrotaipei')
      AND NOT (components @> ARRAY[new_comp_id]);
END $$;
