-- ============================================================================
-- Лабораторна робота № 9: Індексні методи, EXPLAIN та оптимізація запитів
-- Скрипт 01: Перевірка середовища, створення схеми, DDL та наповнення даними
-- ============================================================================

-- 1. Перевірка параметрів сесії та середовища підключення
SELECT 
    current_database(), 
    current_user, 
    pg_backend_pid(), 
    current_setting('server_version');

SHOW search_path;

-- 2. Очищення та створення ізольованої навчальної схеми lab09_pr
-- УВАГА: видаляє попередній вміст схеми для забезпечення чистоти експерименту
DROP SCHEMA IF EXISTS lab09_pr CASCADE;
CREATE SCHEMA lab09_pr;

-- 3. Створення таблиці датчиків (sensors)
CREATE TABLE lab09_pr.sensors (
    id integer PRIMARY KEY,
    sensor_code text NOT NULL UNIQUE,
    location text NOT NULL
);

-- 4. Створення таблиці показів вимірювань (readings)
CREATE TABLE lab09_pr.readings (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sensor_id integer NOT NULL REFERENCES lab09_pr.sensors(id),
    measured_at timestamptz NOT NULL,
    temperature numeric(5,2) NOT NULL,
    is_valid boolean NOT NULL,
    tags text[] NOT NULL
);

-- 5. Наповнення довідника датчиків (100 датчиків)
INSERT INTO lab09_pr.sensors (id, sensor_code, location)
SELECT 
    n, 
    'SNS-' || lpad(n::text, 3, '0'),
    'Сектор ' || (((n - 1) / 20) + 1)
FROM generate_series(1, 100) AS g(n);

-- 6. Наповнення таблиці показів (100 000 вимірювань із кроком в 1 хвилину)
-- Кожне 500-те вимірювання маркується невалідним (is_valid = false) та містить тег 'alarm'
INSERT INTO lab09_pr.readings (sensor_id, measured_at, temperature, is_valid, tags)
SELECT 
    ((n - 1) % 100) + 1,
    TIMESTAMPTZ '2026-01-01 00:00+00' + (n - 1) * INTERVAL '1 minute',
    18.0 + (n % 220)::numeric / 10,
    n % 500 <> 0,
    CASE 
        WHEN n % 500 = 0 THEN ARRAY['alarm']::text[]
        ELSE ARRAY['normal']::text[] 
    END
FROM generate_series(1, 100000) AS g(n);

-- 7. Оновлення системної статистики планувальника
ANALYZE lab09_pr.sensors;
ANALYZE lab09_pr.readings;

-- 8. Контрольна перевірка кількості записів (очікується 100000 / 200 / 200)
SELECT
    COUNT(*) AS total_readings,
    COUNT(*) FILTER (WHERE NOT is_valid) AS invalid_readings,
    COUNT(*) FILTER (WHERE tags @> ARRAY['alarm']::text[]) AS alarms
FROM lab09_pr.readings;
