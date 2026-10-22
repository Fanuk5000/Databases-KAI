-- ============================================================================
-- Лабораторна робота №6: Віконні функції, CTE, рекурсивні запити та представлення
-- Скрипт 05: Представлення: VIEW, MATERIALIZED VIEW та процедура REFRESH
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Приклад 12: Створення звичайного агрегатного представлення (VIEW)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW lab06.v_sensor_summary AS
SELECT s.id AS sensor_id,
       s.sensor_code,
       COUNT(r.id) AS reading_count,
       ROUND(AVG(r.value), 2) AS avg_value,
       MAX(r.value) AS max_value,
       COUNT(r.id) FILTER (
           WHERE r.value > s.limit_value
       ) AS over_limit_count,
       MAX(r.measured_at) AS last_measured_at
FROM lab06.sensors AS s
LEFT JOIN lab06.readings AS r ON r.sensor_id = s.id
GROUP BY s.id, s.sensor_code;

-- Читання з представлення
SELECT sensor_code, reading_count, avg_value, max_value, over_limit_count
FROM lab06.v_sensor_summary
ORDER BY sensor_id;

-- Самостійна перевірка 12: Фільтрація вибірки з VIEW (датчики з >= 2 перевищеннями)
SELECT sensor_code, reading_count, over_limit_count
FROM lab06.v_sensor_summary
WHERE over_limit_count >= 2
ORDER BY sensor_id;

-- ----------------------------------------------------------------------------
-- Приклад 13: Створення матеріалізованого представлення (MATERIALIZED VIEW)
-- ----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS lab06.mv_sensor_summary AS
SELECT sensor_id, sensor_code, reading_count,
       avg_value, max_value, over_limit_count,
       last_measured_at
FROM lab06.v_sensor_summary;

-- Читання зі збереженого знімка
SELECT sensor_code, reading_count, avg_value, max_value, over_limit_count
FROM lab06.mv_sensor_summary
ORDER BY sensor_id;

-- ----------------------------------------------------------------------------
-- Приклад 14: Життєвий цикл оновлення та експеримент з REFRESH
-- ----------------------------------------------------------------------------
-- Крок 1: Вставка контрольного вимірювання (32.0 °C о 09:00 для T-01)
INSERT INTO lab06.readings (id, sensor_id, measured_at, value)
VALUES (9001, 1, '2026-10-01 09:00', 32.0);

-- Крок 2: Порівняння VIEW та MATERIALIZED VIEW до REFRESH
SELECT 'VIEW' AS source, reading_count, avg_value, max_value, over_limit_count
FROM lab06.v_sensor_summary WHERE sensor_id = 1
UNION ALL
SELECT 'MATERIALIZED VIEW', reading_count, avg_value, max_value, over_limit_count
FROM lab06.mv_sensor_summary WHERE sensor_id = 1
ORDER BY source;

-- Крок 3: Синхронізація через REFRESH
REFRESH MATERIALIZED VIEW lab06.mv_sensor_summary;

SELECT 'VIEW' AS source, reading_count, avg_value, max_value, over_limit_count
FROM lab06.v_sensor_summary WHERE sensor_id = 1
UNION ALL
SELECT 'MATERIALIZED VIEW', reading_count, avg_value, max_value, over_limit_count
FROM lab06.mv_sensor_summary WHERE sensor_id = 1
ORDER BY source;

-- Крок 4: Видалення контрольного показу та відновлення стану
DELETE FROM lab06.readings WHERE id = 9001;
REFRESH MATERIALIZED VIEW lab06.mv_sensor_summary;

SELECT 'VIEW' AS source, reading_count, avg_value, max_value, over_limit_count
FROM lab06.v_sensor_summary WHERE sensor_id = 1
UNION ALL
SELECT 'MATERIALIZED VIEW', reading_count, avg_value, max_value, over_limit_count
FROM lab06.mv_sensor_summary WHERE sensor_id = 1
ORDER BY source;
