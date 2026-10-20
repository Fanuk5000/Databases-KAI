-- =====================================================================
-- Файл: 05_standalone_tasks.sql
-- Тема: Еталонні розв'язки 9 самостійних завдань лабораторної роботи
-- =====================================================================

-- 1. Знайти датчики, код яких містить 02
SELECT id, code, name
FROM lab5.sensors
WHERE code ILIKE '%02%'
ORDER BY id;

-- 2. Обчислити середню температуру кожного датчика
SELECT sensor_id, ROUND(AVG(temperature), 2) AS avg_temp
FROM lab5.readings
GROUP BY sensor_id
ORDER BY sensor_id;

-- 3. Підрахувати кількість достовірних і недостовірних вимірювань кожного датчика
SELECT
    sensor_id,
    COUNT(*) FILTER (WHERE is_valid)     AS valid_cnt,
    COUNT(*) FILTER (WHERE NOT is_valid) AS invalid_cnt
FROM lab5.readings
GROUP BY sensor_id
ORDER BY sensor_id;

-- 4. Знайти останнє достовірне вимірювання кожного датчика
SELECT DISTINCT ON (sensor_id)
    sensor_id, id, measured_at, temperature
FROM lab5.readings
WHERE is_valid AND temperature IS NOT NULL
ORDER BY sensor_id, measured_at DESC, id DESC;

-- 5. Підняти alert_limit датчика esp-02 на 5 і повернути змінений рядок через RETURNING
BEGIN;
UPDATE lab5.sensors
SET alert_limit = alert_limit + 5
WHERE code = 'esp-02'
RETURNING id, code, alert_limit;
ROLLBACK;

-- 6. Оновити пороги датчиків з таблиці sensor_settings через UPDATE ... FROM
BEGIN;
UPDATE lab5.sensors AS s
SET alert_limit = cfg.alert_limit
FROM lab5.sensor_settings AS cfg
WHERE s.id = cfg.sensor_id
RETURNING s.id, s.code, s.alert_limit;
ROLLBACK;

-- 7. Змоделювати повторне надходження датчика esp-02 через ON CONFLICT DO UPDATE
BEGIN;
INSERT INTO lab5.sensors (code, name, room)
VALUES ('esp-02', 'Датчик 2 (дубль)', '999')
ON CONFLICT (code)
DO UPDATE SET name = EXCLUDED.name, room = EXCLUDED.room
RETURNING id, code, name, room;
ROLLBACK;

-- 8. Синхронізувати sensors з sensor_import через MERGE
BEGIN;
MERGE INTO lab5.sensors AS s
USING lab5.sensor_import AS i
ON s.code = i.code
WHEN MATCHED THEN
    UPDATE SET name = i.name, room = i.room
WHEN NOT MATCHED THEN
    INSERT (code, name, room) VALUES (i.code, i.name, i.room);
SELECT * FROM lab5.sensors ORDER BY id;
ROLLBACK;

-- 9. Вивести два останні вимірювання кожного датчика через LATERAL
SELECT s.id, s.code, lr.id AS reading_id, lr.temperature
FROM lab5.sensors AS s
LEFT JOIN LATERAL (
    SELECT r.id, r.temperature
    FROM lab5.readings AS r
    WHERE r.sensor_id = s.id
    ORDER BY r.measured_at DESC, r.id DESC
    LIMIT 2
) AS lr ON true
ORDER BY s.id, lr.id DESC;
