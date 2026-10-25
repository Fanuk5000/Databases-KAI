-- ============================================================================
-- Лабораторна робота №8: Транзакції, MVCC, блокування та VACUUM у PostgreSQL
-- Файл: 01_schema_and_initial_data.sql
-- Призначення: Перевірка оточення, створення схеми lab08, таблиці readings та наповнення
-- ============================================================================

-- 1. Перевірка підключення та параметрів поточної сесії
SELECT 
    current_database() AS db_name,
    current_user AS db_user,
    pg_backend_pid() AS session_pid,
    current_setting('server_version') AS pg_version;

SHOW search_path;

-- 2. Скидання та створення ізольованої схеми lab08
DROP SCHEMA IF EXISTS lab08 CASCADE;
CREATE SCHEMA IF NOT EXISTS lab08;

-- 3. Створення таблиці показів температури датчиків
CREATE TABLE lab08.readings (
    id integer PRIMARY KEY,
    sensor_id integer NOT NULL,
    temperature numeric(5,1) NOT NULL
);

-- 4. Наповнення базовими даними (3 вимірювання)
INSERT INTO lab08.readings (id, sensor_id, temperature)
VALUES
    (1, 1, 20.0),
    (2, 1, 21.0),
    (3, 2, 24.0);

-- 5. Контрольна вибірка початкового стану
SELECT id, sensor_id, temperature
FROM lab08.readings
ORDER BY id;
