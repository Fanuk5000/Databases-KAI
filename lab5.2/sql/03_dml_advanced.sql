-- =====================================================================
-- Файл: 03_dml_advanced.sql
-- Тема: RETURNING, UPDATE ... FROM, DELETE ... USING, ON CONFLICT, MERGE
-- =====================================================================

-- Розділ 7. Пропозиція RETURNING у DML операціях
-- 7.1. Оновлення ліміту alert_limit з поверненням змінених значень
BEGIN;
UPDATE lab5.sensors
SET alert_limit = alert_limit + 2
WHERE code = 'esp-01'
RETURNING id, code, alert_limit;
ROLLBACK;

-- 7.2. Вставка нового датчика з поверненням згенерованого id
BEGIN;
INSERT INTO lab5.sensors (code, name, room)
VALUES ('esp-05', 'Новий датчик', '105')
RETURNING id, code, name;
ROLLBACK;

-- 7.3. Завдання 5: перенесення esp-02 у кімнату 202 та повернення зміненого рядка
BEGIN;
UPDATE lab5.sensors
SET room = '202'
WHERE code = 'esp-02'
RETURNING id, code, room;
ROLLBACK;

-- Розділ 8. Модифікація зв'язаних даних: UPDATE ... FROM
-- 8.1. Оновлення порогів спрацювання у sensors з таблиці sensor_settings
BEGIN;
UPDATE lab5.sensors AS s
SET alert_limit = cfg.alert_limit
FROM lab5.sensor_settings AS cfg
WHERE s.id = cfg.sensor_id
RETURNING s.id, s.code, s.alert_limit;
ROLLBACK;

-- Розділ 9. Видалення зв'язаних даних: DELETE ... USING
-- 9.1. Видалення показів неактивних датчиків (обов'язкова умова зв'язку в WHERE)
BEGIN;
DELETE FROM lab5.readings AS r
USING lab5.sensors AS s
WHERE r.sensor_id = s.id
  AND NOT s.active
RETURNING r.id, r.sensor_id, r.temperature;
ROLLBACK;

-- Розділ 10. Декларативне вирішення конфліктів: ON CONFLICT
-- 10.1. Оновлення наявного датчика через DO UPDATE з псевдотаблицею EXCLUDED
BEGIN;
INSERT INTO lab5.sensors (code, name, room)
VALUES ('esp-01', 'Нова назва', '105')
ON CONFLICT (code)
DO UPDATE SET
    name = EXCLUDED.name,
    room = EXCLUDED.room
RETURNING id, code, name, room;
ROLLBACK;

-- 10.2. Завдання 6: послідовна вставка дубліката esp-05 (DO NOTHING, потім DO UPDATE)
BEGIN;
INSERT INTO lab5.sensors (code, name, room)
VALUES ('esp-05', 'Датчик 5', '105')
ON CONFLICT (code) DO NOTHING;

INSERT INTO lab5.sensors (code, name, room)
VALUES ('esp-05', 'Датчик 5 (оновлений)', '205')
ON CONFLICT (code)
DO UPDATE SET
    name = EXCLUDED.name,
    room = EXCLUDED.room
RETURNING id, code, name, room;
ROLLBACK;

-- Розділ 11. Декларативна синхронізація через команду MERGE
-- 11.1. Злиття таблиць sensors та sensor_import (оновлення наявних + вставка нових)
BEGIN;
MERGE INTO lab5.sensors AS s
USING lab5.sensor_import AS i
ON s.code = i.code
WHEN MATCHED THEN
    UPDATE SET
        name = i.name,
        room = i.room
WHEN NOT MATCHED THEN
    INSERT (code, name, room)
    VALUES (i.code, i.name, i.room);

SELECT * FROM lab5.sensors ORDER BY id;
ROLLBACK;
