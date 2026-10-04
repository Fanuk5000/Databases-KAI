-- ============================================================================
-- Лабораторна робота 4.1: Часові типи та типи діапазонів у PostgreSQL
-- Частина 2: Типи діапазонів (tstzrange) та обмеження виключення (EXCLUDE)
-- ============================================================================

-- 1. Активація розширення для підтримки B-tree скалярів в індексах GiST
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 2. Створення таблиці бронювань із обмеженням виключення
CREATE TABLE IF NOT EXISTS lab41.room_bookings (
    id         serial PRIMARY KEY,
    room_id    int NOT NULL,
    booked_by  text NOT NULL,
    period     tstzrange NOT NULL,
    EXCLUDE USING gist (room_id WITH =, period WITH &&)
);

-- 3. Додавання валідних бронювань без перетину інтервалів
INSERT INTO lab41.room_bookings (room_id, booked_by, period)
VALUES
    (1, 'Кафедра ІТ',        tstzrange('2026-09-20 10:00+02', '2026-09-20 11:00+02')),
    (1, 'Кафедра метрології', tstzrange('2026-09-20 11:00+02', '2026-09-20 12:30+02')),
    (2, 'Деканат',            tstzrange('2026-09-20 10:30+02', '2026-09-20 11:30+02'));

-- Перевірка записів
SELECT * FROM lab41.room_bookings ORDER BY room_id, lower(period);

-- 4. Негативний тест: спроба вставки накладеного бронювання (повинна бути помилка)
-- Очікується: ERROR: conflicting key value violates exclusion constraint
-- INSERT INTO lab41.room_bookings (room_id, booked_by, period)
-- VALUES (1, 'Студентський деканат', tstzrange('2026-09-20 10:45+02', '2026-09-20 11:15+02'));

-- 5. Пошук бронювань кімнати 1, що перетинаються з контрольним вікном [10:30, 11:15) через оператор &&
SELECT
    id,
    room_id,
    booked_by,
    period
FROM lab41.room_bookings
WHERE room_id = 1
  AND period && tstzrange('2026-09-20 10:30+02', '2026-09-20 11:15+02');

-- 6. Отримання меж інтервалу (lower, upper) та перевірка входження мітки часу через @>
SELECT
    booked_by,
    lower(period) AS starts_at,
    upper(period) AS ends_at,
    period @> TIMESTAMPTZ '2026-09-20 11:15+02' AS contains_1115
FROM lab41.room_bookings;
