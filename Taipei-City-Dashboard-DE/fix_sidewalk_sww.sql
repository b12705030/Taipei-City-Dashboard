UPDATE public.component_maps
SET paint = $json${"fill-color":["step",["get","SWW_WTH"],"#E53935",1.25,"#FFC107",2.5,"#4CAF50"],"fill-opacity":["interpolate",["linear"],["zoom"],12,0.45,16,0.8]}$json$::json,
    property = $prop$[
    {"key": "NAME",     "name": "道路名稱"},
    {"key": "SW_WTH",  "name": "人行道寬度(m)"},
    {"key": "SWW_WTH", "name": "人行道淨寬(m)"},
    {"key": "SW_LENG", "name": "人行道長度(m)"},
    {"key": "VILL_NAME","name": "鄉鎮"}
]$prop$::json
WHERE id IN (108, 109);
