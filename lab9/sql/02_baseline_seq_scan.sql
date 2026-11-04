-- ============================================================================
-- Лабораторна робота № 9: Індексні методи, EXPLAIN та оптимізація запитів
-- Скрипт 02: Дослід 1. Базовий діапазонний пошук без індексу (Baseline Seq Scan)
-- ============================================================================

-- 1. Перевірка кількості записів за 1 годину (очікується found_rows = 60)
SELECT COUNT(*) AS found_rows
FROM lab09_pr.readings
WHERE measured_at >= TIMESTAMPTZ '2026-01-02 12:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-02 13:00+00';

-- 2. Профілювання запиту за допомогою EXPLAIN (ANALYZE, BUFFERS)
-- Очікується Seq Scan по всій таблиці (100k рядків), читання 1220 блоків пам'яті
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sensor_id, temperature
FROM lab09_pr.readings
WHERE measured_at >= TIMESTAMPTZ '2026-01-02 12:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-02 13:00+00';
