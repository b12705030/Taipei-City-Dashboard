UPDATE public.query_charts
SET
    source     = '內政部國土管理署',
    short_desc = '依人行道淨寬（SWW_WTH）以 1.25m / 2.5m 為斷點，將各路段分為紅（< 1.25m）、黃（1.25–2.5m）、綠（≥ 2.5m）三級，並統計各行政區比例。',
    long_desc  = '資料來源為內政部國土管理署「全國人行道資料」（WGS84），涵蓋台北市與新北市。人行道淨寬（SWW_WTH）為扣除障礙物後實際可通行寬度，依營建署《都市人本交通道路規劃設計手冊（第二版）》建議：1.25m 為單人舒適通行寬度（含拐杖使用者無障礙需求），2.5m 為雙人舒適並行寬度。地圖以 MultiPolygon 幾何呈現每段人行道範圍，顏色標示無障礙可及等級；圖表顯示各行政區三色段數比例。',
    use_case   = '識別行人通行品質不足路段，輔助人行道改善優先序排定；評估各行政區無障礙友善程度，作為都市步行環境政策依據。',
    links      = ARRAY['https://data.gov.tw/dataset/58791'],
    contributors = ARRAY['reneting']
WHERE index = 'sidewalk_width';
