-- ============================================================================
-- Лабораторна робота № 9: Індексні методи, EXPLAIN та оптимізація запитів
-- Скрипт 04: Дослід 3. Складений індекс (Composite Index) за двома стовпцями
-- ============================================================================

-- 1. Профілювання запиту до створення складеного індексу
-- Пошук даних датчика № 42 за добу (02.01.2026, очікується 15 рядків).
-- Очікується Index Scan за lr09_time_btree з подальшим відкиданням 1425 рядків через Filter: (sensor_id = 42)
EXPLAIN (ANALYZE, BUFFERS)
SELECT sensor_id, measured_at, temperature
FROM lab09_pr.readings
WHERE sensor_id = 42
  AND measured_at >= TIMESTAMPTZ '2026-01-02 00:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-03 00:00+00';

-- 2. Створення складеного індексу (спочатку точна рівність, потім інтервал)
CREATE INDEX lr09_sensor_time_btree
ON lab09_pr.readings (sensor_id, measured_at);

-- 3. Повторне профілювання зі складеним індексом
-- Очікується Index Scan using lr09_sensor_time_btree, 0 рядків відкинуто фільтром
EXPLAIN (ANALYZE, BUFFERS)
SELECT sensor_id, measured_at, temperature
FROM lab09_pr.readings
WHERE sensor_id = 42
  AND measured_at >= TIMESTAMPTZ '2026-01-02 00:00+00'
  AND measured_at <  TIMESTAMPTZ '2026-01-03 00:00+00';
