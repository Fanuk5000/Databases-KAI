-- ============================================================================
-- Лабораторна робота 4.1: Часові типи та типи діапазонів у PostgreSQL
-- Частина 3: Завдання для самостійного виконання та аналітика
-- ============================================================================

-- 1. Модифікація таблиці work_shifts: додавання стовпця типу interval та його розрахунок
ALTER TABLE lab41.work_shifts
ADD COLUMN IF NOT EXISTS shift_duration interval;

UPDATE lab41.work_shifts
SET shift_duration = end_time - start_time;

SELECT id, employee_name, start_time, end_time, shift_duration
FROM lab41.work_shifts
ORDER BY id;

-- 2. Створення та наповнення таблиці шкали оцінок exam_grades з типом numrange
CREATE TABLE IF NOT EXISTS lab41.exam_grades (
    id           serial PRIMARY KEY,
    grade_letter text NOT NULL,
    description  text NOT NULL,
    grade_range  numrange NOT NULL
);

INSERT INTO lab41.exam_grades (grade_letter, description, grade_range)
VALUES
    ('A', 'Відмінно',     numrange(90, 100, '[]')),
    ('B', 'Добре',        numrange(75, 90, '[)')),
    ('C', 'Задовільно',   numrange(60, 75, '[)')),
    ('F', 'Незадовільно', numrange(0, 60, '[)'));

-- Пошук оцінки для студента з тестовим балом 82.5 через оператор входження @>
SELECT
    grade_letter,
    description,
    grade_range,
    grade_range @> 82.5::numeric AS is_matching
FROM lab41.exam_grades
WHERE grade_range @> 82.5::numeric;

-- 3. Додавання нового безконфліктного бронювання для кімнати 1
INSERT INTO lab41.room_bookings (room_id, booked_by, period)
VALUES (1, 'Науковий сектор', tstzrange('2026-09-20 14:00+02', '2026-09-20 15:30+02'));

SELECT room_id, booked_by, period
FROM lab41.room_bookings
ORDER BY room_id, lower(period);

-- 4. Аналітичний запит: пошук вільних вікон між бронюваннями для кімнати 1 через LEAD()
WITH ordered_bookings AS (
    SELECT
        room_id,
        booked_by,
        lower(period) AS cur_start,
        upper(period) AS cur_end,
        LEAD(lower(period)) OVER (
            PARTITION BY room_id
            ORDER BY lower(period)
        ) AS next_start
    FROM lab41.room_bookings
    WHERE room_id = 1
      AND period && tstzrange('2026-09-20 00:00+02', '2026-09-20 23:59:59+02')
)
SELECT
    room_id,
    cur_end AS free_from,
    next_start AS free_to,
    (next_start - cur_end) AS free_duration,
    tstzrange(cur_end, next_start, '[)') AS free_slot
FROM ordered_bookings
WHERE next_start IS NOT NULL
  AND next_start > cur_end;
