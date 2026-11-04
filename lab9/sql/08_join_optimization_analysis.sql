-- ============================================================================
-- Лабораторна робота № 9: Індексні методи, EXPLAIN та оптимізація запитів
-- Скрипт 08: Додаткове Б. Профілювання операції з'єднання таблиць (JOIN)
-- ============================================================================

-- Профілювання запиту об'єднання перших 10 датчиків з агрегацією кількості показів
-- Очікується Hash Join (хешування 10 датчиків + послідовне сканування readings),
-- подальша групова агрегація HashAggregate та сортування quicksort
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.sensor_code, COUNT(*) AS number_of_readings
FROM lab09_pr.sensors AS s
JOIN lab09_pr.readings AS r ON r.sensor_id = s.id
WHERE s.id <= 10
GROUP BY s.sensor_code
ORDER BY s.sensor_code;
