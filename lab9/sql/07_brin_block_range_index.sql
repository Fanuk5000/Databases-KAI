-- ============================================================================
-- Лабораторна робота № 9: Індексні методи, EXPLAIN та оптимізація запитів
-- Скрипт 07: Додаткове А. Компактний індекс діапазонів блоків BRIN та розміри
-- ============================================================================

-- 1. Видалення конкуруючих B-tree індексів за часом
DROP INDEX IF EXISTS lab09_pr.lr09_time_btree;
DROP INDEX IF EXISTS lab09_pr.lr09_sensor_time_btree;

-- 2. Створення індексу діапазонів блоків BRIN (гранулярність 32 сторінки)
CREATE INDEX lr09_time_brin
ON lab09_pr.readings USING brin (measured_at)
WITH (pages_per_range = 32);

-- 3. Профілювання діапазонного запиту з BRIN індексом
-- Очікується Bitmap Index Scan on lr09_time_brin + Bitmap Heap Scan з фільтрацією Recheck Cond
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sensor_id
FROM lab09_pr.readings
WHERE measured_at >= TIMESTAMPTZ '2026-01-02 12:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-02 13:00+00';

-- 4. Порівняльний аналіз фізичного розміру таблиць та індексів на диску
SELECT
    c.relname AS object_name,
    pg_size_pretty(pg_relation_size(c.oid)) AS size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'lab09_pr'
ORDER BY pg_relation_size(c.oid) DESC;
