-- 04_monitoring.sql
-- Моніторинг процесів сеансів через pg_stat_activity

-- 1. Отримання PID поточного серверного процесу
SELECT pg_backend_pid();

-- 2. Інформація про власний сеанс
SELECT
    pid,
    usename,
    datname,
    application_name,
    backend_type,
    state
FROM pg_stat_activity
WHERE pid = pg_backend_pid();

-- 3. Моніторинг усіх сесій бази даних lab_measurements
SELECT
    pid,
    usename,
    datname,
    application_name,
    state
FROM pg_stat_activity
WHERE datname = 'lab_measurements'
ORDER BY pid;
