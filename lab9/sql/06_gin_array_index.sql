-- ============================================================================
-- Лабораторна робота № 9: Індексні методи, EXPLAIN та оптимізація запитів
-- Скрипт 06: Дослід 5. Інвертований індекс GIN для пошуку в масивах (tags text[])
-- ============================================================================

-- 1. Профілювання запиту наявності мітки 'alarm' без GIN індексу
-- Очікується повне сканування таблиці Seq Scan (~324 ms), оскільки B-tree не підтримує @>
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, measured_at
FROM lab09_pr.readings
WHERE tags @> ARRAY['alarm']::text[];

-- 2. Створення інвертованого індексу GIN
CREATE INDEX lr09_tags_gin
ON lab09_pr.readings USING gin (tags);

-- 3. Повторне профілювання запиту з GIN індексом
-- Очікується Bitmap Index Scan on lr09_tags_gin + Bitmap Heap Scan, скорочення часу до ~0.36 ms (прискорення ~894x)
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, measured_at
FROM lab09_pr.readings
WHERE tags @> ARRAY['alarm']::text[];
