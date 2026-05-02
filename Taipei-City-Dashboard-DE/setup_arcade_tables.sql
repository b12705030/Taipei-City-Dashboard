-- 雙北騎樓整平 — dashboard DB 資料表建立腳本
-- 連線：localhost:5433 / dashboard DB（postgres-data）
-- 對應 CSV 來源：
--   public/mapData/arcade_total_by_district.csv
--   public/mapData/arcade_yearly_by_city.csv
--   public/mapData/arcade_yearly_by_district.csv

-- ============================================================
-- 1. 各行政區累積整平長度
-- ============================================================
CREATE TABLE IF NOT EXISTS public.arcade_total_by_district (
    id             SERIAL PRIMARY KEY,
    city           VARCHAR(20)  NOT NULL,
    district       VARCHAR(20)  NOT NULL,
    total_length_m DOUBLE PRECISION NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_arcade_total_city
    ON public.arcade_total_by_district(city);

CREATE INDEX IF NOT EXISTS idx_arcade_total_district
    ON public.arcade_total_by_district(district);

-- ============================================================
-- 2. 各縣市逐年整平長度
-- ============================================================
CREATE TABLE IF NOT EXISTS public.arcade_yearly_by_city (
    id           SERIAL PRIMARY KEY,
    city         VARCHAR(20)  NOT NULL,
    year         INTEGER      NOT NULL,
    city_total_m DOUBLE PRECISION NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_arcade_yearly_city_city
    ON public.arcade_yearly_by_city(city);

CREATE INDEX IF NOT EXISTS idx_arcade_yearly_city_year
    ON public.arcade_yearly_by_city(year);

-- ============================================================
-- 3. 各行政區逐年整平長度
-- ============================================================
CREATE TABLE IF NOT EXISTS public.arcade_yearly_by_district (
    id       SERIAL PRIMARY KEY,
    city     VARCHAR(20)  NOT NULL,
    district VARCHAR(20)  NOT NULL,
    year     INTEGER      NOT NULL,
    length_m DOUBLE PRECISION NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_arcade_yearly_dist_city
    ON public.arcade_yearly_by_district(city);

CREATE INDEX IF NOT EXISTS idx_arcade_yearly_dist_year
    ON public.arcade_yearly_by_district(year);

CREATE INDEX IF NOT EXISTS idx_arcade_yearly_dist_district
    ON public.arcade_yearly_by_district(district);

-- ============================================================
-- 4. 各行政區人行道總長度（來源：pedestrian_length_by_district.csv）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pedestrian_length_by_district (
    id             SERIAL PRIMARY KEY,
    city           VARCHAR(20)      NOT NULL,
    district       VARCHAR(20)      NOT NULL,
    walk_length_m  DOUBLE PRECISION NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_ped_len_city
    ON public.pedestrian_length_by_district(city);

CREATE INDEX IF NOT EXISTS idx_ped_len_district
    ON public.pedestrian_length_by_district(district);
