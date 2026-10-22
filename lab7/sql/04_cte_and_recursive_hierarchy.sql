-- ============================================================================
-- Лабораторна робота №6: Віконні функції, CTE, рекурсивні запити та представлення
-- Скрипт 04: Звичайні CTE та рекурсивний обхід ієрархій обладнання
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Приклад 8: Останній показ кожного датчика через CTE (ROW_NUMBER = 1)
-- ----------------------------------------------------------------------------
WITH numbered AS (
    SELECT id, sensor_id, measured_at, value,
           ROW_NUMBER() OVER (
               PARTITION BY sensor_id
               ORDER BY measured_at DESC, id DESC
           ) AS rn
    FROM lab06.readings
)
SELECT sensor_id, id, measured_at, value
FROM numbered
WHERE rn = 1
ORDER BY sensor_id;

-- Самостійна перевірка 8: Отримання двох останніх вимірювань (rn <= 2)
WITH numbered AS (
    SELECT id, sensor_id, measured_at, value,
           ROW_NUMBER() OVER (
               PARTITION BY sensor_id
               ORDER BY measured_at DESC, id DESC
           ) AS rn
    FROM lab06.readings
)
SELECT sensor_id, id, measured_at, value, rn
FROM numbered
WHERE rn <= 2
ORDER BY sensor_id, measured_at DESC, id DESC;

-- ----------------------------------------------------------------------------
-- Приклад 9: Ланцюжок з двох CTE: пошук стрибків температури (ABS(delta) >= 2.0)
-- ----------------------------------------------------------------------------
WITH previous AS (
    SELECT id, sensor_id, measured_at, value,
           LAG(value) OVER (
               PARTITION BY sensor_id
               ORDER BY measured_at, id
           ) AS prev_value
    FROM lab06.readings
), changes AS (
    SELECT id, sensor_id, measured_at,
           value, prev_value,
           value - prev_value AS delta
    FROM previous
)
SELECT sensor_id, id, measured_at,
       prev_value, value, delta
FROM changes
WHERE ABS(delta) >= 2.0
ORDER BY sensor_id, measured_at, id;

-- Самостійна перевірка 9: Фільтрація тільки позитивного нагріву (delta >= 2.0)
WITH previous AS (
    SELECT id, sensor_id, measured_at, value,
           LAG(value) OVER (
               PARTITION BY sensor_id
               ORDER BY measured_at, id
           ) AS prev_value
    FROM lab06.readings
), changes AS (
    SELECT id, sensor_id, measured_at,
           value, prev_value,
           value - prev_value AS delta
    FROM previous
)
SELECT sensor_id, id, measured_at,
       prev_value, value, delta
FROM changes
WHERE delta >= 2.0
ORDER BY sensor_id, measured_at, id;

-- ----------------------------------------------------------------------------
-- Приклад 10: Рекурсивний обхід повного дерева обладнання (WITH RECURSIVE)
-- ----------------------------------------------------------------------------
WITH RECURSIVE tree AS (
    SELECT id, parent_id, name,
           0 AS depth,
           ARRAY[id] AS path
    FROM lab06.equipment
    WHERE parent_id IS NULL

    UNION ALL

    SELECT e.id, e.parent_id, e.name,
           t.depth + 1,
           t.path || e.id
    FROM lab06.equipment AS e
    JOIN tree AS t ON e.parent_id = t.id
    WHERE NOT (e.id = ANY(t.path))
)
SELECT id, depth, path,
       repeat('    ', depth) || name AS equipment_tree
FROM tree
ORDER BY path;

-- Самостійна перевірка 10: Рекурсивний спуск від Стенда А (id = 2)
WITH RECURSIVE tree AS (
    SELECT id, parent_id, name,
           0 AS depth,
           ARRAY[id] AS path
    FROM lab06.equipment
    WHERE id = 2

    UNION ALL

    SELECT e.id, e.parent_id, e.name,
           t.depth + 1,
           t.path || e.id
    FROM lab06.equipment AS e
    JOIN tree AS t ON e.parent_id = t.id
    WHERE NOT (e.id = ANY(t.path))
)
SELECT id, depth, path,
       repeat('    ', depth) || name AS equipment_tree
FROM tree
ORDER BY path;

-- ----------------------------------------------------------------------------
-- Приклад 11: Датчики вибраного стенда А та всіх його вкладених об'єктів
-- ----------------------------------------------------------------------------
WITH RECURSIVE branch AS (
    SELECT id, ARRAY[id] AS path
    FROM lab06.equipment
    WHERE id = 2

    UNION ALL

    SELECT e.id, b.path || e.id
    FROM lab06.equipment AS e
    JOIN branch AS b ON e.parent_id = b.id
    WHERE NOT (e.id = ANY(b.path))
)
SELECT s.id AS sensor_id, s.sensor_code,
       e.name AS equipment_name
FROM branch AS b
JOIN lab06.equipment AS e ON e.id = b.id
JOIN lab06.sensors AS s ON s.equipment_id = b.id
ORDER BY s.id;

-- Самостійна перевірка 11: Датчики для Стенда Б (id = 3) та всієї лабораторії (id = 1)
-- 1. Стенд Б
WITH RECURSIVE branch AS (
    SELECT id, ARRAY[id] AS path FROM lab06.equipment WHERE id = 3
    UNION ALL
    SELECT e.id, b.path || e.id FROM lab06.equipment e JOIN branch b ON e.parent_id = b.id WHERE NOT (e.id = ANY(b.path))
)
SELECT s.id AS sensor_id, s.sensor_code, e.name AS equipment_name
FROM branch b JOIN lab06.equipment e ON e.id = b.id JOIN lab06.sensors s ON s.equipment_id = b.id;

-- 2. Вся лабораторія (id = 1)
WITH RECURSIVE branch AS (
    SELECT id, ARRAY[id] AS path FROM lab06.equipment WHERE id = 1
    UNION ALL
    SELECT e.id, b.path || e.id FROM lab06.equipment e JOIN branch b ON e.parent_id = b.id WHERE NOT (e.id = ANY(b.path))
)
SELECT s.id AS sensor_id, s.sensor_code, e.name AS equipment_name
FROM branch b JOIN lab06.equipment e ON e.id = b.id JOIN lab06.sensors s ON s.equipment_id = b.id ORDER BY s.id;
