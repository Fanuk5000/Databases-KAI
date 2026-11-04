-- ============================================================================
-- Лабораторна робота № 9: Індексні методи, EXPLAIN та оптимізація запитів
-- Скрипт 05: Дослід 4. Частковий індекс (Partial Index) для рідкісних станів
-- ============================================================================

-- 1. Профілювання вибірки 20 останніх невалідних показів до створення часткового індексу
-- Очікується Index Scan Backward using lr09_time_btree з відкиданням 9481 рядка валідних даних
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sensor_id, measured_at
FROM lab09_pr.readings
WHERE NOT is_valid
ORDER BY measured_at DESC
LIMIT 20;

-- 2. Створення часткового індексу зі спадним порядком (індексує лише 200 невалідних рядків)
CREATE INDEX lr09_invalid_partial
ON lab09_pr.readings (measured_at DESC)
WHERE NOT is_valid;

-- 3. Повторне профілювання вибірки із частковим індексом
-- Очікується миттєвий Index Scan using lr09_invalid_partial, 0 відкинутих рядків, 21 блок
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sensor_id, measured_at
FROM lab09_pr.readings
WHERE NOT is_valid
ORDER BY measured_at DESC
LIMIT 20;
