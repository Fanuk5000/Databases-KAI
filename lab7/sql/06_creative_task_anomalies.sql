-- ============================================================================
-- Лабораторна робота №6: Віконні функції, CTE, рекурсивні запити та представлення
-- Скрипт 06: Творче завдання: система виявлення теплових аномалій (Розділ 9)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Доповнення реляційної моделі (новий вузол, новий датчик, 8 вимірювань)
-- ----------------------------------------------------------------------------
BEGIN;

-- Новий вузол обладнання під Стендом А (id = 2)
INSERT INTO lab06.equipment (id, parent_id, name)
VALUES (7, 2, 'Експериментальний модуль нагріву')
ON CONFLICT (id) DO NOTHING;

-- Новий датчик T-04 із порогом 25.0 °C
INSERT INTO lab06.sensors (id, sensor_code, equipment_id, limit_value)
VALUES (4, 'T-04', 7, 25.0)
ON CONFLICT (id) DO NOTHING;

-- 8 вимірювань сенсора T-04 із закладеними сценаріями тестування
INSERT INTO lab06.readings (id, sensor_id, measured_at, value) VALUES
    (101, 4, '2026-10-01 08:00', 23.0),  -- 1: Норма (нижче порогу)
    (102, 4, '2026-10-01 08:10', 25.0),  -- 2: Граничний випадок (рівність ліміту: не є перевищенням)
    (103, 4, '2026-10-01 08:20', 26.5),  -- 3: Перше перевищення (prev_val <= limit, умова 2 false)
    (104, 4, '2026-10-01 08:30', 28.0),  -- 4: УМОВА ВИКОНУЄТЬСЯ (26.5->28.0, delta=+1.5, обидва > 25.0)
    (105, 4, '2026-10-01 08:40', 28.5),  -- 5: Умова не виконується (delta = +0.5 < 1.0)
    (106, 4, '2026-10-01 08:40', 27.0),  -- 6: Збіг часової мітки (спад температури, delta = -1.5)
    (107, 4, '2026-10-01 08:50', 24.0),  -- 7: Повернення в норму
    (108, 4, '2026-10-01 09:00', 29.0)   -- 8: Стрибок після норми (попередник 24.0 < limit, умова 2 false)
ON CONFLICT (id) DO NOTHING;

COMMIT;

-- ----------------------------------------------------------------------------
-- 2. Створення аналітичного VIEW та MATERIALIZED VIEW
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW lab06.v_thermal_anomalies AS
WITH RECURSIVE stand_equipment AS (
    SELECT id, ARRAY[id] AS path
    FROM lab06.equipment
    WHERE id = 2  -- Стенд А

    UNION ALL

    SELECT e.id, se.path || e.id
    FROM lab06.equipment AS e
    JOIN stand_equipment AS se ON e.parent_id = se.id
    WHERE NOT (e.id = ANY(se.path))
), stand_sensors AS (
    SELECT s.id AS sensor_id, s.sensor_code, s.limit_value, e.name AS equipment_name
    FROM stand_equipment se
    JOIN lab06.equipment e ON e.id = se.id
    JOIN lab06.sensors s ON s.equipment_id = se.id
), metrics AS (
    SELECT r.id, r.sensor_id, ss.sensor_code, ss.equipment_name,
           r.measured_at, r.value, ss.limit_value,
           LAG(r.value) OVER w AS prev_value,
           ROUND(r.value - LAG(r.value) OVER w, 2) AS delta,
           ROUND(AVG(r.value) OVER w_mov, 2) AS moving_avg_3
    FROM lab06.readings r
    JOIN stand_sensors ss ON ss.sensor_id = r.sensor_id
    WINDOW
        w AS (
            PARTITION BY r.sensor_id
            ORDER BY r.measured_at, r.id
        ),
        w_mov AS (
            PARTITION BY r.sensor_id
            ORDER BY r.measured_at, r.id
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        )
), evaluated AS (
    SELECT m.*,
           CASE
               WHEN m.value > m.limit_value
                AND m.prev_value > m.limit_value
                AND m.delta >= 1.0
                AND m.value > m.moving_avg_3
               THEN 'CRITICAL_ANOMALY'
               ELSE 'NORMAL'
           END AS anomaly_status
    FROM metrics m
)
SELECT sensor_code, equipment_name, id AS reading_id,
       measured_at, value, limit_value, prev_value, delta,
       moving_avg_3, anomaly_status,
       DENSE_RANK() OVER (
           PARTITION BY sensor_code
           ORDER BY delta DESC NULLS LAST
       ) AS rank_by_spike
FROM evaluated
ORDER BY sensor_code, measured_at, reading_id;

CREATE MATERIALIZED VIEW IF NOT EXISTS lab06.mv_thermal_anomalies AS
SELECT * FROM lab06.v_thermal_anomalies;

-- ----------------------------------------------------------------------------
-- 3. Валідація трьох контрольних випадків (виконується, не виконується, межа)
-- ----------------------------------------------------------------------------
SELECT reading_id, sensor_code, measured_at, value, prev_value, delta, moving_avg_3, anomaly_status
FROM lab06.v_thermal_anomalies
WHERE sensor_code = 'T-04' AND reading_id IN (102, 104, 105)
ORDER BY reading_id;

-- ----------------------------------------------------------------------------
-- 4. Триетапна перевірка життєвого циклу REFRESH
-- ----------------------------------------------------------------------------
-- Стан 1: До змін
SELECT anomaly_status, COUNT(*) 
FROM lab06.mv_thermal_anomalies 
WHERE sensor_code = 'T-04' 
GROUP BY anomaly_status;

-- Стан 2: Додавання аномального вимірювання (31.0 °C о 09:10)
INSERT INTO lab06.readings (id, sensor_id, measured_at, value)
VALUES (109, 4, '2026-10-01 09:10', 31.0);

SELECT 'VIEW' AS src, COUNT(*) FROM lab06.v_thermal_anomalies WHERE sensor_code = 'T-04' AND anomaly_status = 'CRITICAL_ANOMALY'
UNION ALL
SELECT 'MATERIALIZED VIEW', COUNT(*) FROM lab06.mv_thermal_anomalies WHERE sensor_code = 'T-04' AND anomaly_status = 'CRITICAL_ANOMALY';

-- Стан 3: Після виконання REFRESH
REFRESH MATERIALIZED VIEW lab06.mv_thermal_anomalies;

SELECT 'VIEW' AS src, COUNT(*) FROM lab06.v_thermal_anomalies WHERE sensor_code = 'T-04' AND anomaly_status = 'CRITICAL_ANOMALY'
UNION ALL
SELECT 'MATERIALIZED VIEW', COUNT(*) FROM lab06.mv_thermal_anomalies WHERE sensor_code = 'T-04' AND anomaly_status = 'CRITICAL_ANOMALY';

-- Відновлення базового стану
DELETE FROM lab06.readings WHERE id = 109;
REFRESH MATERIALIZED VIEW lab06.mv_thermal_anomalies;
