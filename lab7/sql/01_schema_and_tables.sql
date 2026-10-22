-- ============================================================================
-- Лабораторна робота №6: Віконні функції, CTE, рекурсивні запити та представлення
-- Скрипт 01: Створення схеми, таблиць, індексів та внесення базових даних
-- ============================================================================

-- Перевірка сесії (без зміни search_path)
SHOW search_path;
SELECT current_database(), current_user, pg_backend_pid();

-- Створення схеми
CREATE SCHEMA IF NOT EXISTS lab06;

-- 1. Таблиця ієрархії обладнання
CREATE TABLE IF NOT EXISTS lab06.equipment (
    id        integer PRIMARY KEY,
    parent_id integer REFERENCES lab06.equipment(id),
    name      text NOT NULL,
    CHECK (parent_id IS NULL OR parent_id <> id)
);

-- 2. Довідник сенсорів
CREATE TABLE IF NOT EXISTS lab06.sensors (
    id           integer PRIMARY KEY,
    sensor_code  text NOT NULL UNIQUE,
    equipment_id integer NOT NULL REFERENCES lab06.equipment(id),
    limit_value  numeric(5,1) NOT NULL
);

-- 3. Таблиця вимірювань
CREATE TABLE IF NOT EXISTS lab06.readings (
    id          integer PRIMARY KEY,
    sensor_id   integer NOT NULL REFERENCES lab06.sensors(id),
    measured_at timestamp NOT NULL,
    value       numeric(5,1) NOT NULL
);

-- Вторинні індекси для прискорення JOIN та сортування у вікнах
CREATE INDEX IF NOT EXISTS idx_equipment_parent_id 
    ON lab06.equipment(parent_id);

CREATE INDEX IF NOT EXISTS idx_sensors_equipment_id 
    ON lab06.sensors(equipment_id);

CREATE INDEX IF NOT EXISTS idx_readings_sensor_measured 
    ON lab06.readings(sensor_id, measured_at, id);

-- Транзакційне наповнення початковими навчальними даними
BEGIN;

INSERT INTO lab06.equipment (id, parent_id, name) VALUES
    (1, NULL, 'Навчальна лабораторія'),
    (2, 1,    'Стенд А'),
    (3, 1,    'Стенд Б'),
    (4, 2,    'Нагрівальна камера'),
    (5, 2,    'Охолоджувальний блок'),
    (6, 3,    'Повітряний канал')
ON CONFLICT (id) DO NOTHING;

INSERT INTO lab06.sensors (id, sensor_code, equipment_id, limit_value) VALUES
    (1, 'T-01', 4, 22.0),
    (2, 'T-02', 5, 30.0),
    (3, 'T-03', 6, 19.0)
ON CONFLICT (id) DO NOTHING;

INSERT INTO lab06.readings (id, sensor_id, measured_at, value) VALUES
    (1,  1, '2026-10-01 08:00', 20.0),
    (2,  1, '2026-10-01 08:10', 22.0),
    (3,  1, '2026-10-01 08:20', 22.0),
    (4,  1, '2026-10-01 08:20', 24.0),
    (5,  1, '2026-10-01 08:40', 23.0),
    (6,  1, '2026-10-01 08:50', 25.0),
    (7,  2, '2026-10-01 08:00', 28.0),
    (8,  2, '2026-10-01 08:10', 29.0),
    (9,  2, '2026-10-01 08:20', 31.0),
    (10, 2, '2026-10-01 08:30', 31.0),
    (11, 2, '2026-10-01 08:40', 30.0),
    (12, 2, '2026-10-01 08:50', 29.0),
    (13, 3, '2026-10-01 08:00', 18.0),
    (14, 3, '2026-10-01 08:10', 18.0),
    (15, 3, '2026-10-01 08:20', 19.0),
    (16, 3, '2026-10-01 08:30', 17.0),
    (17, 3, '2026-10-01 08:40', 18.0),
    (18, 3, '2026-10-01 08:50', 20.0)
ON CONFLICT (id) DO NOTHING;

COMMIT;

-- Контрольний запит верифікації наповнення (18 рядків, по 6 на кожен датчик)
SELECT sensor_id,
       COUNT(*)             AS reading_count,
       ROUND(AVG(value), 2) AS avg_value
FROM lab06.readings
GROUP BY sensor_id
ORDER BY sensor_id;
