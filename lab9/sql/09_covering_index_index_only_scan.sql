-- ============================================================================
-- Лабораторна робота № 9: Індексні методи, EXPLAIN та оптимізація запитів
-- Скрипт 09: Творче завдання. Покривний індекс (Covering Index) та Index Only Scan
-- ============================================================================

-- 1. Створення покривного індексу з включенням корисного стовпця temperature в листки B-tree
CREATE INDEX lr09_sensor_time_covering
ON lab09_pr.readings (sensor_id, measured_at)
INCLUDE (temperature);

-- 2. Оновлення карти видимості (Visibility Map) для увімкнення Index Only Scan
VACUUM (ANALYZE) lab09_pr.readings;

-- 3. Профілювання вибірки датчика 42 за добу
-- Очікується Index Only Scan using lr09_sensor_time_covering, показник Heap Fetches: 0
EXPLAIN (ANALYZE, BUFFERS)
SELECT sensor_id, measured_at, temperature
FROM lab09_pr.readings
WHERE sensor_id = 42
  AND measured_at >= TIMESTAMPTZ '2026-01-02 00:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-03 00:00+00';
