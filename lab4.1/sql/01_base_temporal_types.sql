-- ============================================================================
-- Лабораторна робота 4.1: Часові типи та типи діапазонів у PostgreSQL
-- Частина 1: Базові часові типи (date, time, timestamptz, interval)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS lab41;

-- 1. Створення таблиці обліку робочих змін
CREATE TABLE IF NOT EXISTS lab41.work_shifts (
    id            serial PRIMARY KEY,
    employee_name text NOT NULL,
    work_date     date NOT NULL,
    start_time    time NOT NULL,
    end_time      time NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- 2. Наповнення початковими тестовими даними
INSERT INTO lab41.work_shifts (employee_name, work_date, start_time, end_time)
VALUES
    ('Іваненко О.П.', '2026-09-15', '08:00', '16:00'),
    ('Петренко С.М.', '2026-09-15', '09:30', '18:00'),
    ('Іваненко О.П.', '2026-09-16', '12:00', '20:00');

-- Перевірка стану таблиці
SELECT * FROM lab41.work_shifts ORDER BY id;

-- 3. Часова арифметика: обчислення тривалості зміни (інтервал)
SELECT
    employee_name,
    work_date,
    start_time,
    end_time,
    (end_time - start_time) AS shift_duration
FROM lab41.work_shifts
ORDER BY work_date, start_time;

-- 4. Вилучення дня тижня та місяця через EXTRACT()
SELECT
    employee_name,
    work_date,
    EXTRACT(DOW  FROM work_date) AS day_of_week,
    EXTRACT(MONTH FROM work_date) AS month_num
FROM lab41.work_shifts;

-- 5. Обчислення часу від створення запису через AGE()
SELECT
    employee_name,
    created_at,
    AGE(now(), created_at) AS time_since_creation
FROM lab41.work_shifts;

-- 6. Фільтрація за часом початку та форматування дати через TO_CHAR()
SELECT
    employee_name,
    TO_CHAR(work_date, 'DD.MM.YYYY') AS formatted_date,
    start_time
FROM lab41.work_shifts
WHERE start_time > TIME '09:00';
