-- ============================================================================
-- Лабораторна робота №6: Віконні функції, CTE, рекурсивні запити та представлення
-- Скрипт 03: Рамки вікна, накопичувальні показники та ковзні середні
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Приклад 4: Накопичувальні кількість, середнє та кількість перевищень ліміту
-- ----------------------------------------------------------------------------
SELECT r.id, r.measured_at, r.value,
       COUNT(*) OVER w AS running_count,
       ROUND(AVG(r.value) OVER w, 2) AS running_avg,
       SUM(CASE WHEN r.value > s.limit_value
                THEN 1 ELSE 0 END) OVER w AS over_count
FROM lab06.readings AS r
JOIN lab06.sensors AS s ON s.id = r.sensor_id
WHERE r.sensor_id = 1
WINDOW w AS (
    PARTITION BY r.sensor_id
    ORDER BY r.measured_at, r.id
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
)
ORDER BY r.measured_at, r.id;

-- Самостійна перевірка 4: Розрахунок для датчика T-02 (поріг 30.0 °C)
SELECT r.id, r.measured_at, r.value,
       COUNT(*) OVER w AS running_count,
       ROUND(AVG(r.value) OVER w, 2) AS running_avg,
       SUM(CASE WHEN r.value > s.limit_value
                THEN 1 ELSE 0 END) OVER w AS over_count
FROM lab06.readings AS r
JOIN lab06.sensors AS s ON s.id = r.sensor_id
WHERE r.sensor_id = 2
WINDOW w AS (
    PARTITION BY r.sensor_id
    ORDER BY r.measured_at, r.id
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
)
ORDER BY r.measured_at, r.id;

-- ----------------------------------------------------------------------------
-- Приклад 5: Порівняння поведінки ROWS та RANGE на збігах часу (08:20)
-- ----------------------------------------------------------------------------
SELECT id, measured_at, value,
       COUNT(*) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at, id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS rows_count,
       COUNT(*) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at
           RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS range_count
FROM lab06.readings
WHERE sensor_id = 1
ORDER BY measured_at, id;

-- Самостійна перевірка 5: Дефолтна рамка PostgreSQL (RANGE UNBOUNDED PRECEDING)
SELECT id, measured_at, value,
       COUNT(*) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at
       ) AS default_count,
       COUNT(*) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at
           RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS explicit_range_count
FROM lab06.readings
WHERE sensor_id = 1
ORDER BY measured_at, id;

-- ----------------------------------------------------------------------------
-- Приклад 6: Ковзне середнє: 3 записи (ROWS) проти 20 хвилин (RANGE INTERVAL)
-- ----------------------------------------------------------------------------
SELECT id, measured_at, value,
       COUNT(*) OVER w_rows AS n_rows,
       ROUND(AVG(value) OVER w_rows, 2) AS avg_3_rows,
       COUNT(*) OVER w_time AS n_time,
       ROUND(AVG(value) OVER w_time, 2) AS avg_20_min
FROM lab06.readings
WHERE sensor_id = 1
WINDOW
    w_rows AS (
        PARTITION BY sensor_id
        ORDER BY measured_at, id
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ),
    w_time AS (
        PARTITION BY sensor_id
        ORDER BY measured_at
        RANGE BETWEEN INTERVAL '20 minutes' PRECEDING AND CURRENT ROW
    )
ORDER BY measured_at, id;

-- Самостійна перевірка 6: Зміна часового вікна на 10 хвилин
SELECT id, measured_at, value,
       COUNT(*) OVER w_10min AS n_10min,
       ROUND(AVG(value) OVER w_10min, 2) AS avg_10min
FROM lab06.readings
WHERE sensor_id = 1
WINDOW w_10min AS (
    PARTITION BY sensor_id
    ORDER BY measured_at
    RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
)
ORDER BY measured_at, id;

-- ----------------------------------------------------------------------------
-- Приклад 7: Крайні значення (FIRST_VALUE, LAST_VALUE) та пастка дефолтної рамки
-- ----------------------------------------------------------------------------
SELECT id, measured_at, value,
       FIRST_VALUE(value) OVER w_full AS first_value,
       LAST_VALUE(value) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at, id
       ) AS last_default,
       LAST_VALUE(value) OVER w_full AS last_full
FROM lab06.readings
WHERE sensor_id = 1
WINDOW w_full AS (
    PARTITION BY sensor_id
    ORDER BY measured_at, id
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
ORDER BY measured_at, id;

-- Самостійна перевірка 7: Останнє та максимальне значення для T-02
SELECT DISTINCT
       LAST_VALUE(value) OVER (
           PARTITION BY sensor_id
           ORDER BY measured_at, id
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS last_sensor_value,
       MAX(value) OVER (
           PARTITION BY sensor_id
       ) AS max_sensor_value
FROM lab06.readings
WHERE sensor_id = 2;
