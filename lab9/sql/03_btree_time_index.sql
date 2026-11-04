-- ============================================================================
-- Лабораторна робота № 9: Індексні методи, EXPLAIN та оптимізація запитів
-- Скрипт 03: Дослід 2. Прискорення діапазонного пошуку індексом B-tree
-- ============================================================================

-- 1. Створення B-tree індексу за часовою міткою
CREATE INDEX lr09_time_btree
ON lab09_pr.readings (measured_at);

-- 2. Повторне виконання діапазонного запиту з B-tree індексом
-- Очікується Index Scan using lr09_time_btree, скорочення звернень до блоків (5 блоків проти 1220)
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sensor_id, temperature
FROM lab09_pr.readings
WHERE measured_at >= TIMESTAMPTZ '2026-01-02 12:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-02 13:00+00';
