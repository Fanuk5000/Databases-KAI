-- 03_seed.sql
-- Первинне наповнення даними

-- 1. Додавання приладу
INSERT INTO core.device (device_name, model)
VALUES ('Redmi Note 9 pro', 'M2003J6B2G')
RETURNING device_id;

-- 2. Додавання сенсора для створеного пристрою
INSERT INTO core.sensor (device_id, sensor_code, quantity, unit_symbol)
VALUES (1, 'CPU_Mhz_001', 'Frequence', 'Mhz');

-- 3. Перевірка результатів
SELECT * FROM core.device;
SELECT * FROM core.sensor;
