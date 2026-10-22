-- ============================================================================
-- Лабораторна робота №6: Віконні функції, CTE, рекурсивні запити та представлення
-- Скрипт 02: Віконні функції: середнє, ранжування та доступ до сусідніх рядків
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Приклад 1: Порівняння показу із середнім свого датчика
-- ----------------------------------------------------------------------------
SELECT id, sensor_id, measured_at, value,
       ROUND(AVG(value) OVER (
           PARTITION BY sensor_id
       ), 2) AS sensor_avg,
       ROUND(value - AVG(value) OVER (
           PARTITION BY sensor_id
       ), 2) AS deviation
FROM lab06.readings
ORDER BY sensor_id, measured_at, id;

-- Самостійна перевірка 1: Відставання від максимуму свого датчика
SELECT id, sensor_id, measured_at, value,
       MAX(value) OVER (
           PARTITION BY sensor_id
       ) AS sensor_max,
       ROUND(value - MAX(value) OVER (
           PARTITION BY sensor_id
       ), 2) AS lag_from_max
FROM lab06.readings
ORDER BY sensor_id, measured_at, id;

-- ----------------------------------------------------------------------------
-- Приклад 2: Порівняння функцій ранжування (ROW_NUMBER, RANK, DENSE_RANK)
-- ----------------------------------------------------------------------------
SELECT id, value,
       ROW_NUMBER() OVER (
           PARTITION BY sensor_id
           ORDER BY value DESC, measured_at, id
       ) AS row_no,
       RANK() OVER (
           PARTITION BY sensor_id
           ORDER BY value DESC
       ) AS rank_no,
       DENSE_RANK() OVER (
           PARTITION BY sensor_id
           ORDER BY value DESC
       ) AS dense_no
FROM lab06.readings
WHERE sensor_id = 1
ORDER BY value DESC, measured_at, id;

-- Самостійна перевірка 2: Додавання первинного ключа id в ORDER BY ранжування
SELECT id, value,
       RANK() OVER (
           PARTITION BY sensor_id
           ORDER BY value DESC, id
       ) AS rank_no_with_id,
       DENSE_RANK() OVER (
           PARTITION BY sensor_id
           ORDER BY value DESC, id
       ) AS dense_no_with_id
FROM lab06.readings
WHERE sensor_id = 1
ORDER BY value DESC, id;

-- ----------------------------------------------------------------------------
-- Приклад 3: Порівняння сусідніх показів через LAG і LEAD
-- ----------------------------------------------------------------------------
SELECT id, measured_at, value,
       LAG(value) OVER w AS prev_value,
       LEAD(value) OVER w AS next_value,
       value - LAG(value) OVER w AS delta
FROM lab06.readings
WHERE sensor_id = 1
WINDOW w AS (
    PARTITION BY sensor_id
    ORDER BY measured_at, id
)
ORDER BY measured_at, id;

-- Самостійна перевірка 3: Зсув на 2 позиції назад (LAG(value, 2))
SELECT id, measured_at, value,
       LAG(value, 2) OVER w AS prev_2_value,
       value - LAG(value, 2) OVER w AS delta_2
FROM lab06.readings
WHERE sensor_id = 1
WINDOW w AS (
    PARTITION BY sensor_id
    ORDER BY measured_at, id
)
ORDER BY measured_at, id;
