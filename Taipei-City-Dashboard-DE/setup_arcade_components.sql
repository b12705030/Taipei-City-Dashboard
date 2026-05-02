-- 雙北騎樓整平儀表板 — dashboardmanager DB 組件設定腳本
-- 連線：localhost:5432 / dashboardmanager DB（postgres-manager）
-- 僅保留單一組件 arcade_total_district，整合四種視覺化：
--   DistrictChart + BarChart + DonutChart + MapLegend

-- ============================================================
-- 0-pre. contributors 表（組件資訊面板需要 user_id 存在才能渲染）
-- ============================================================

INSERT INTO public.contributors (user_id, user_name, image, link, include, created_at, updated_at)
SELECT 'b12705030', 'b12705030',
       'https://avatars.githubusercontent.com/b12705030',
       'https://github.com/b12705030',
       true, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM public.contributors WHERE user_id = 'b12705030');

-- ============================================================
-- 0. 清除舊有已不使用的組件
-- ============================================================

DELETE FROM public.query_charts
WHERE index IN (
    'arcade_yearly_city_trend',
    'arcade_yearly_district_trend',
    'arcade_district_share'
);

DELETE FROM public.component_charts
WHERE index IN (
    'arcade_yearly_city_trend',
    'arcade_yearly_district_trend',
    'arcade_district_share'
);

DELETE FROM public.components
WHERE index IN (
    'arcade_yearly_city_trend',
    'arcade_yearly_district_trend',
    'arcade_district_share'
);


-- ============================================================
-- 1. components 表
-- ============================================================

INSERT INTO public.components (index, name) VALUES
    ('arcade_total_district', '騎樓整平累積量')
ON CONFLICT (index) DO UPDATE SET name = EXCLUDED.name;


-- ============================================================
-- 2. component_charts 表
-- ============================================================
-- color 陣列說明：
--   [0] '#FFF9C4'  ← DistrictChart 漸層低值（淡黃）
--   [1] '#B71C1C'  ← DistrictChart 漸層高值（深紅）
--   [2..11]        ← DonutChart 行政區分類色（依序循環）

INSERT INTO public.component_charts (index, color, types, unit) VALUES
    ('arcade_total_district',
        ARRAY[
            '#FFF9C4', '#B71C1C',
            '#F4511E', '#FB8C00', '#FDD835',
            '#43A047', '#00ACC1', '#1E88E5',
            '#5E35B1', '#D81B60', '#8D6E63', '#FF7043'
        ],
        ARRAY['DistrictChart', 'BarChart', 'DonutChart', 'MapLegend'],
        '公尺')
ON CONFLICT (index) DO UPDATE
    SET color = EXCLUDED.color,
        types = EXCLUDED.types,
        unit  = EXCLUDED.unit;


-- ============================================================
-- 3. component_maps 表（比例符號圖層）
-- 注意：taipei 版本必須先於 metrotaipei 版本存在
-- ============================================================

DELETE FROM public.component_maps
WHERE index IN ('arcade_total_district_taipei', 'arcade_total_district');

-- 3-1. 台北市版本
INSERT INTO public.component_maps (index, title, type, source, size, icon, paint, property)
VALUES (
    'arcade_total_district_taipei',
    '騎樓整平總量',
    'circle',
    'geojson',
    NULL,
    NULL,
    '{
        "circle-color": [
            "interpolate", ["linear"],
            ["get", "total_length_m"],
            0,      "#FFF9C4",
            30000,  "#FFB300",
            150000, "#E65100",
            500000, "#B71C1C"
        ],
        "circle-radius": [
            "interpolate", ["linear"], ["zoom"],
            10, ["interpolate", ["linear"], ["get", "total_length_m"],
                  0, 3,   30000, 6,   150000, 10,   500000, 16],
            14, ["interpolate", ["linear"], ["get", "total_length_m"],
                  0, 5,   30000, 10,  150000, 16,   500000, 24]
        ],
        "circle-opacity": 0.85,
        "circle-stroke-width": 1,
        "circle-stroke-color": "#ffffff"
    }',
    '[
        {"key": "district",       "name": "行政區"},
        {"key": "city",           "name": "城市"},
        {"key": "total_length_m", "name": "累積整平長度（公尺）"}
    ]'
);

-- 3-2. 雙北版本（統一黃→紅漸層，與 DistrictChart 一致）
INSERT INTO public.component_maps (index, title, type, source, size, icon, paint, property)
VALUES (
    'arcade_total_district',
    '騎樓整平總量（雙北）',
    'circle',
    'geojson',
    NULL,
    NULL,
    '{
        "circle-color": [
            "interpolate", ["linear"],
            ["get", "total_length_m"],
            0,      "#FFF9C4",
            10000,  "#FFB300",
            100000, "#E65100",
            500000, "#B71C1C"
        ],
        "circle-radius": [
            "interpolate", ["linear"], ["zoom"],
            10, ["interpolate", ["linear"], ["get", "total_length_m"],
                  0, 3,   10000, 6,   100000, 10,   500000, 16],
            14, ["interpolate", ["linear"], ["get", "total_length_m"],
                  0, 5,   10000, 10,  100000, 16,   500000, 24]
        ],
        "circle-opacity": 0.85,
        "circle-stroke-width": 1,
        "circle-stroke-color": "#ffffff"
    }',
    '[
        {"key": "district",       "name": "行政區"},
        {"key": "city",           "name": "城市"},
        {"key": "total_length_m", "name": "累積整平長度（公尺）"}
    ]'
);


-- ============================================================
-- 4. query_charts 表
-- ============================================================

DELETE FROM public.query_charts WHERE index LIKE 'arcade_%';

-- ── 台北市版本（附台北地圖圖層）────────────────────────────────
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'arcade_total_district',
    NULL,
    (SELECT ARRAY[id] FROM public.component_maps
     WHERE index = 'arcade_total_district_taipei' LIMIT 1),
    '{}',
    'static', NULL, NULL, NULL,
    '臺北市政府工務局',
    '台北市各行政區騎樓整平工程累積長度，反映步行舒適度的空間分佈。',
    '顯示台北市 12 個行政區的騎樓整平工程累積長度（公尺）。舒適度是影響民眾是否願意步行至公共運輸節點的重要因素——若人行道不連續、騎樓高低落差大或寬度不足，即使距離不長也可能降低步行意願。騎樓整平工程透過消除高低落差、拓寬可用步行寬度，改善動線連續性。資料來源為臺北市政府工務局公開之騎樓整平工程完成路段統計，整合至民國 113 年底。可透過行政區圖（色深反映整平量）、橫向長條圖（排名比較）、圓餅圖（佔比分佈）及地圖圖例四種視角呈現。',
    '透過行政區圖可快速識別台北市整平量集中的熱區。萬華、大同、大安等舊城核心區因 1990 年代大規模整平政策，整平累積量遠高於其他行政區，合計佔全市逾六成。士林、北投、文山等面積較大行政區整平量相對分散。切換至橫向長條圖可進行跨區排名比較，圓餅圖可了解各行政區占全市整平量的份額，協助評估步行空間資源分配的空間均衡性，為優先改善區域的政策規劃提供依據。',
    ARRAY['https://data.taipei/dataset/detail?id=09504c47-7349-4cab-9ce6-db30f32a392e', 'https://data.taipei/dataset/detail?id=1601ef3a-c253-4988-b047-943d9e786143'],
    ARRAY['b12705030'],
    NOW(), NOW(),
    'two_d',
    E'SELECT district AS x_axis,\n       ROUND(total_length_m)::INT AS data\nFROM public.arcade_total_by_district\nWHERE city = ''台北市''\nORDER BY data DESC',
    NULL,
    'taipei'
);

-- ── 新北市版本（無地圖圖層）────────────────────────────────────
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'arcade_total_district',
    NULL, '{}', '{}',
    'static', NULL, NULL, NULL,
    '新北市政府工務局',
    '新北市各行政區騎樓整平工程累積長度，反映步行舒適度的空間分佈。',
    '顯示新北市各行政區的騎樓整平工程累積長度（公尺）。舒適度是影響民眾是否願意步行至公共運輸節點的重要因素——若人行道不連續、騎樓高低落差大或寬度不足，即使距離不長也可能降低步行意願。騎樓整平工程透過消除高低落差、拓寬可用步行寬度，改善動線連續性。資料來源為新北市政府工務局公開之騎樓整平各年度施作路段統計，整合至民國 113 年底。可透過行政區圖（色深反映整平量）、橫向長條圖（排名比較）、圓餅圖（佔比分佈）及地圖圖例四種視角呈現。',
    '透過行政區圖可識別新北市整平量集中的區域——板橋、中和、永和等都市化程度高的行政區整平累積量明顯高於其他行政區，烏來、坪林、石碇等山區行政區整平量趨近於零。新北市多數行政區的整平量遠低於台北市，反映兩市歷史整平政策規模的差距。切換至橫向長條圖可進行跨區排名比較，圓餅圖可了解各行政區占全市整平量的份額，協助評估哪些行政區需要優先投入步行環境改善。',
    ARRAY['https://data.ntpc.gov.tw/datasets/7ccd0715-2e3e-453a-a290-180d8f3075cd'],
    ARRAY['b12705030'],
    NOW(), NOW(),
    'two_d',
    E'SELECT district AS x_axis,\n       ROUND(total_length_m)::INT AS data\nFROM public.arcade_total_by_district\nWHERE city = ''新北市''\nORDER BY data DESC',
    NULL,
    'newtaipei'
);

-- ── 雙北版本（附雙北地圖圖層，Top 20）─────────────────────────
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'arcade_total_district',
    NULL,
    (SELECT ARRAY[id] FROM public.component_maps
     WHERE index = 'arcade_total_district' LIMIT 1),
    '{}',
    'static', NULL, NULL, NULL,
    '臺北市政府工務局、新北市政府工務局',
    '雙北各行政區騎樓整平工程累積長度，反映步行舒適度的空間分佈。',
    '顯示雙北地區（臺北市與新北市）各行政區的騎樓整平工程累積長度（公尺）。舒適度是影響民眾是否願意步行至公共運輸節點的重要因素——若人行道不連續、騎樓高低落差大或寬度不足，即使距離不長也可能降低步行意願。騎樓整平工程透過消除高低落差、拓寬可用步行寬度，改善動線連續性，讓最後一哩不只是「走得到」，而是「願意走」。資料來源為臺北市及新北市政府工務局公開施工完成路段統計，整合至民國 113 年底。可透過行政區圖、橫向長條圖、圓餅圖及地圖圖例四種視角呈現。',
    '雙北視角下，台北市因 1990 年代大規模整平政策，整體累積整平量遠高於新北市，兩市規模落差懸殊。透過行政區圖可比較兩市整平熱區：台北以萬華、大同、大安等舊城核心區為主，新北以板橋、中和、永和為整平量較高的行政區。此分佈差異可作為評估雙北步行環境空間均衡性及優先改善順序的參考依據，協助政府規劃更均衡的整平資源分配。',
    ARRAY['https://data.taipei/dataset/detail?id=09504c47-7349-4cab-9ce6-db30f32a392e', 'https://data.ntpc.gov.tw/datasets/7ccd0715-2e3e-453a-a290-180d8f3075cd', 'https://data.taipei/dataset/detail?id=1601ef3a-c253-4988-b047-943d9e786143'],
    ARRAY['b12705030'],
    NOW(), NOW(),
    'two_d',
    E'SELECT district AS x_axis,\n       ROUND(total_length_m)::INT AS data\nFROM public.arcade_total_by_district\nORDER BY data DESC',
    NULL,
    'metrotaipei'
);


-- ============================================================
-- 5. arcade_map_legend 獨立圖例組件
-- 說明：MapLegend 需要 map_legend query type，無法與 two_d 同組件
--       因此獨立為一個純圖例卡片，顯示圓點色階說明
-- ============================================================

-- 清除舊有（冪等）
DELETE FROM public.query_charts   WHERE index = 'arcade_map_legend';
DELETE FROM public.component_charts WHERE index = 'arcade_map_legend';
DELETE FROM public.components      WHERE index = 'arcade_map_legend';

INSERT INTO public.components (index, name) VALUES
    ('arcade_map_legend', '騎樓整平地圖圖例')
ON CONFLICT (index) DO UPDATE SET name = EXCLUDED.name;

-- 4 色對應 4 個圖例項目（index 順序須與 query 的 unnest 順序一致）
INSERT INTO public.component_charts (index, color, types, unit) VALUES
    ('arcade_map_legend',
        ARRAY['#FFF9C4', '#FFB300', '#E65100', '#B71C1C'],
        ARRAY['MapLegend'],
        '公尺')
ON CONFLICT (index) DO UPDATE
    SET color = EXCLUDED.color,
        types = EXCLUDED.types,
        unit  = EXCLUDED.unit;

-- 三個 city 版本共用同一個靜態圖例（無地圖圖層）
DELETE FROM public.query_charts WHERE index = 'arcade_map_legend';

INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
)
SELECT
    'arcade_map_legend',
    NULL, '{}', '{}',
    'static', NULL, NULL, NULL,
    '臺北市政府工務局、新北市政府工務局',
    '地圖圓點色階對照表。',
    '說明地圖上各行政區圓點顏色與大小所對應的騎樓整平累積長度範圍。顏色由淡黃至深紅表示整平量由少至多，圓點大小亦隨整平量等比例縮放。',
    '協助使用者快速判讀地圖上各行政區圓點所代表的整平量級別。',
    ARRAY['https://data.taipei/', 'https://data.ntpc.gov.tw/'],
    ARRAY['b12705030'],
    NOW(), NOW(),
    'map_legend',
    $SQL$SELECT
    unnest(ARRAY[
        '< 10,000 公尺',
        '10,000 – 100,000 公尺',
        '100,000 – 500,000 公尺',
        '≥ 500,000 公尺'
    ]) AS name,
    NULL::float AS value,
    'circle'    AS type$SQL$,
    NULL,
    city_val
FROM (VALUES ('taipei'), ('newtaipei'), ('metrotaipei')) AS t(city_val);


-- ============================================================
-- 6. arcade_leveling_ratio 組件（騎樓整平涵蓋率）
-- 指標：arcade_total_length / walk_length × 100（%）
-- ============================================================

DELETE FROM public.query_charts   WHERE index = 'arcade_leveling_ratio';
DELETE FROM public.component_charts WHERE index = 'arcade_leveling_ratio';
DELETE FROM public.components      WHERE index = 'arcade_leveling_ratio';

INSERT INTO public.components (index, name) VALUES
    ('arcade_leveling_ratio', '騎樓整平涵蓋率')
ON CONFLICT (index) DO UPDATE SET name = EXCLUDED.name;

INSERT INTO public.component_charts (index, color, types, unit) VALUES
    ('arcade_leveling_ratio',
        ARRAY[
            '#FFF9C4', '#B71C1C',
            '#F4511E', '#FB8C00', '#FDD835',
            '#43A047', '#00ACC1', '#1E88E5',
            '#5E35B1', '#D81B60', '#8D6E63', '#FF7043'
        ],
        ARRAY['DistrictChart', 'BarChart'],
        '%')
ON CONFLICT (index) DO UPDATE
    SET color = EXCLUDED.color,
        types = EXCLUDED.types,
        unit  = EXCLUDED.unit;

DELETE FROM public.query_charts WHERE index = 'arcade_leveling_ratio';

-- ── 台北市版本 ────────────────────────────────────────────────
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'arcade_leveling_ratio',
    NULL, '{}', '{}',
    'static', NULL, NULL, NULL,
    '臺北市政府工務局',
    '台北市各行政區騎樓整平涵蓋率，以整平長度佔人行道總長度的比例衡量步行舒適度。',
    '顯示台北市各行政區的騎樓整平涵蓋率（整平長度 ÷ 人行道總長度，上限 100%）。舒適度是影響民眾是否願意步行至公共運輸節點的重要因素——若人行道不連續、騎樓高低落差大或寬度不足，即使距離不長也可能降低步行意願。涵蓋率越高，代表已整平的騎樓佔人行道網絡的比例越大，步行環境品質相對較佳。騎樓整平長度來源為臺北市政府工務局公開完成路段統計，人行道長度來源為 OSM 人行道網絡資料，整合至民國 113 年底。',
    '透過行政區圖可快速識別台北市騎樓整平涵蓋率較高的行政區。萬華、大同、大安等舊城核心區因 1990 年代大規模整平政策，涵蓋率已接近上限（100%）；士林、北投、文山等面積較大行政區人行道網絡廣，涵蓋率相對較低。切換至橫向長條圖可進行跨區排名比較，協助識別步行環境相對薄弱的行政區，作為優先改善政策的空間依據。',
    ARRAY['https://data.taipei/dataset/detail?id=09504c47-7349-4cab-9ce6-db30f32a392e', 'https://data.taipei/dataset/detail?id=1601ef3a-c253-4988-b047-943d9e786143', 'https://data.gov.tw/dataset/58791'],
    ARRAY['b12705030'],
    NOW(), NOW(),
    'two_d',
    E'SELECT p.district AS x_axis,\n       ROUND(LEAST(COALESCE(a.total_length_m, 0) / p.walk_length_m * 100, 100)::numeric, 1)::FLOAT AS data\nFROM public.pedestrian_length_by_district p\nLEFT JOIN public.arcade_total_by_district a\n    ON p.district = a.district AND a.city = ''台北市''\nWHERE p.city = ''台北市'' AND p.walk_length_m > 0\nORDER BY data DESC',
    NULL,
    'taipei'
);

-- ── 新北市版本 ────────────────────────────────────────────────
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'arcade_leveling_ratio',
    NULL, '{}', '{}',
    'static', NULL, NULL, NULL,
    '新北市政府工務局',
    '新北市各行政區騎樓整平涵蓋率，以整平長度佔人行道總長度的比例衡量步行舒適度。',
    '顯示新北市各行政區的騎樓整平涵蓋率（整平長度 ÷ 人行道總長度，上限 100%）。舒適度是影響民眾是否願意步行至公共運輸節點的重要因素——若人行道不連續、騎樓高低落差大或寬度不足，即使距離不長也可能降低步行意願。涵蓋率越高，代表已整平的騎樓佔人行道網絡的比例越大，步行環境品質相對較佳。騎樓整平長度來源為新北市政府工務局公開完成路段統計，人行道長度來源為 OSM 人行道網絡資料，整合至民國 113 年底。',
    '透過行政區圖可識別新北市騎樓整平涵蓋率較高的行政區。永和涵蓋率最高（約 83%），中和、板橋次之；烏來、坪林、石碇等山區行政區人行道廣但整平量趨近於零，涵蓋率最低。切換至橫向長條圖可進行跨區排名比較，協助識別步行環境相對薄弱的行政區，作為優先改善政策的空間依據。',
    ARRAY['https://data.ntpc.gov.tw/datasets/7ccd0715-2e3e-453a-a290-180d8f3075cd', 'https://data.ntpc.gov.tw/datasets/8bbd1aca-752c-4df0-b515-1cfd88b36274', 'https://data.gov.tw/dataset/58791'],
    ARRAY['b12705030'],
    NOW(), NOW(),
    'two_d',
    E'SELECT p.district AS x_axis,\n       ROUND(LEAST(COALESCE(a.total_length_m, 0) / p.walk_length_m * 100, 100)::numeric, 1)::FLOAT AS data\nFROM public.pedestrian_length_by_district p\nLEFT JOIN public.arcade_total_by_district a\n    ON p.district = a.district AND a.city = ''新北市''\nWHERE p.city = ''新北市'' AND p.walk_length_m > 0\nORDER BY data DESC',
    NULL,
    'newtaipei'
);

-- ── 雙北版本（實際比值，封頂 100%）────────────────────────────
-- 封頂後台北最高 100%、新北最高約 83%，同一色階即可呈現差距，
-- 不再需要 city-max 歸一化，且切換城市前後數值一致。
INSERT INTO public.query_charts (
    index, history_config, map_config_ids, map_filter,
    time_from, time_to, update_freq, update_freq_unit,
    source, short_desc, long_desc, use_case,
    links, contributors, created_at, updated_at,
    query_type, query_chart, query_history, city
) VALUES (
    'arcade_leveling_ratio',
    NULL, '{}', '{}',
    'static', NULL, NULL, NULL,
    '臺北市政府工務局、新北市政府工務局',
    '雙北各行政區騎樓整平涵蓋率，以整平長度佔人行道總長度的比例衡量步行舒適度。',
    '顯示雙北地區（臺北市與新北市）各行政區的騎樓整平涵蓋率（整平長度 ÷ 人行道總長度，上限 100%）。舒適度是影響民眾是否願意步行至公共運輸節點的重要因素——若人行道不連續、騎樓高低落差大或寬度不足，即使距離不長也可能降低步行意願。涵蓋率越高，代表已整平的騎樓佔人行道網絡的比例越大，步行環境品質相對較佳，讓最後一哩不只是「走得到」，而是「願意走」。騎樓整平長度來源為臺北市及新北市政府工務局公開完成路段統計，人行道長度來源為 OSM 人行道網絡資料，整合至民國 113 年底。',
    '雙北視角下，台北市各行政區涵蓋率普遍高於新北市，反映兩市歷史整平政策投入規模的差距。台北以萬華、大同、大安等舊城核心區涵蓋率最高（達 100%），新北以永和涵蓋率最高（約 83%）；兩市山區行政區（烏來、坪林）整平量幾乎為零。切換至橫向長條圖可進行跨市排名比較，協助政府識別整平資源不足的行政區，作為雙北步行空間均衡改善的規劃依據。',
    ARRAY['https://data.taipei/dataset/detail?id=09504c47-7349-4cab-9ce6-db30f32a392e', 'https://data.ntpc.gov.tw/datasets/7ccd0715-2e3e-453a-a290-180d8f3075cd', 'https://data.taipei/dataset/detail?id=1601ef3a-c253-4988-b047-943d9e786143', 'https://data.ntpc.gov.tw/datasets/8bbd1aca-752c-4df0-b515-1cfd88b36274', 'https://data.gov.tw/dataset/58791'],
    ARRAY['b12705030'],
    NOW(), NOW(),
    'two_d',
    E'SELECT p.district AS x_axis,\n       ROUND(LEAST(COALESCE(a.total_length_m, 0) / p.walk_length_m * 100, 100)::numeric, 1)::FLOAT AS data\nFROM public.pedestrian_length_by_district p\nLEFT JOIN public.arcade_total_by_district a\n    ON p.district = a.district AND p.city = a.city\nWHERE p.walk_length_m > 0\nORDER BY data DESC',
    NULL,
    'metrotaipei'
);


-- ============================================================
-- 7. dashboards 表
-- ============================================================

INSERT INTO public.dashboards (index, name, components, icon, created_at, updated_at)
SELECT
    'arcade-leveling',
    '騎樓整平指標',
    ARRAY(
        SELECT id FROM public.components
        WHERE index IN (
            'arcade_total_district',
            'arcade_leveling_ratio'
        )
        ORDER BY ARRAY_POSITION(
            ARRAY[
                'arcade_total_district',
                'arcade_leveling_ratio'
            ],
            index
        )
    ),
    'storefront',
    NOW(),
    NOW()
ON CONFLICT (index) DO UPDATE
    SET name       = EXCLUDED.name,
        components = EXCLUDED.components,
        icon       = EXCLUDED.icon,
        updated_at = NOW();


-- ============================================================
-- 8. dashboard_groups 表
-- ============================================================

INSERT INTO public.dashboard_groups (dashboard_id, group_id)
SELECT d.id, g.id
FROM public.dashboards d
CROSS JOIN public.groups g
WHERE d.index = 'arcade-leveling'
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
    qc.query_type,
    array_length(qc.map_config_ids, 1) AS has_map
FROM public.components c
JOIN public.component_charts cc ON c.index = cc.index
JOIN public.query_charts qc     ON c.index = qc.index
WHERE c.index LIKE 'arcade_%'
ORDER BY c.index, qc.city;
-- 預期：9 筆（3 組件 × 3 cities）
