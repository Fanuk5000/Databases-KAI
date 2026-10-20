-- =====================================================================
-- Файл: 01_schema_and_tables.sql
-- Тема: Ізоляція схеми, створення таблиць, індексів та наповнення даними
-- =====================================================================

-- 0. Перевірка середовища сесії (без зміни search_path)
SHOW search_path;
SELECT current_database(), current_user, pg_backend_pid();

-- 1. Створення ізольованої схеми lab5
CREATE SCHEMA IF NOT EXISTS lab5;

-- 2. Створення таблиці датчиків
CREATE TABLE IF NOT EXISTS lab5.sensors (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        varchar(20)  NOT NULL UNIQUE,
    name        varchar(100) NOT NULL,
    room        varchar(20),
    active      boolean      NOT NULL DEFAULT true,
    alert_limit numeric(5,2)          DEFAULT 30
);

-- 3. Створення таблиці вимірювань
CREATE TABLE IF NOT EXISTS lab5.readings (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sensor_id   integer   NOT NULL REFERENCES lab5.sensors(id),
    measured_at timestamp NOT NULL,
    temperature numeric(5,2),
    is_valid    boolean   NOT NULL DEFAULT true
);

-- 4. Створення вторинних B-tree індексів для readings
CREATE INDEX IF NOT EXISTS idx_readings_sensor_id
    ON lab5.readings(sensor_id);

CREATE INDEX IF NOT EXISTS idx_readings_measured_at
    ON lab5.readings(measured_at);

-- 5. Допоміжні таблиці для завдань з UPDATE ... FROM та MERGE
CREATE TABLE IF NOT EXISTS lab5.sensor_settings (
    sensor_id   integer PRIMARY KEY REFERENCES lab5.sensors(id),
    alert_limit numeric(5,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS lab5.sensor_import (
    code varchar(20),
    name varchar(100),
    room varchar(20)
);

-- 6. Верифікація створених таблиць у схемі lab5
SELECT schemaname, tablename
FROM pg_tables
WHERE schemaname = 'lab5'
ORDER BY tablename;

-- 7. Наповнення базовими даними: sensors
INSERT INTO lab5.sensors (code, name, room, active, alert_limit)
VALUES
    ('esp-01', 'Датчик 1', '101', true,  28),
    ('esp-02', 'Датчик 2', '102', true,  30),
    ('esp-03', 'Датчик 3', '103', false, 25),
    ('esp-04', 'Датчик 4', '104', true,  27);

-- 8. Наповнення базовими даними: readings через зіставлення з code
INSERT INTO lab5.readings (sensor_id, measured_at, temperature, is_valid)
SELECT s.id, v.measured_at, v.temperature, v.is_valid
FROM (VALUES
    ('esp-01', timestamp '2026-10-01 10:00', 22::numeric(5,2), true),
    ('esp-01', timestamp '2026-10-01 11:00', 24::numeric(5,2), true),
    ('esp-01', timestamp '2026-10-01 11:00', 25::numeric(5,2), false),

    ('esp-02', timestamp '2026-10-01 10:00', 30::numeric(5,2), true),
    ('esp-02', timestamp '2026-10-01 11:00', 32::numeric(5,2), true),
    ('esp-02', timestamp '2026-10-01 12:00', NULL,              false),

    ('esp-03', timestamp '2026-10-01 10:00', 18::numeric(5,2), true),
    ('esp-03', timestamp '2026-10-01 11:00', 19::numeric(5,2), true)
) AS v(code, measured_at, temperature, is_valid)
JOIN lab5.sensors AS s ON s.code = v.code;

-- 9. Наповнення конфігураційної таблиці: sensor_settings
INSERT INTO lab5.sensor_settings (sensor_id, alert_limit)
SELECT s.id, v.alert_limit
FROM (VALUES
    ('esp-01', 29::numeric(5,2)),
    ('esp-02', 35::numeric(5,2))
) AS v(code, alert_limit)
JOIN lab5.sensors AS s ON s.code = v.code;

-- 10. Наповнення таблиці імпорту: sensor_import
INSERT INTO lab5.sensor_import (code, name, room)
VALUES
    ('esp-01', 'Датчик 1 оновлений', '201'),
    ('esp-05', 'Датчик 5',           '205');
