-- ============================================================================
-- Лабораторна робота 4.2: Типи даних PostgreSQL, JSONB, масиви, час і generate_series
-- Частина 3: Генерація серій дат та календарна аналітика
-- ============================================================================

SET search_path TO lab42, public;

-- 1. Створення послідовності дат на 10 днів жовтня через generate_series
SELECT d::date AS calendar_day
FROM generate_series(
    DATE '2026-10-01',
    DATE '2026-10-10',
    INTERVAL '1 day'
) AS d;

-- 2. Визначення номерів днів тижня (ISODOW) та позначення вихідних днів
SELECT
    d::date AS calendar_day,
    EXTRACT(ISODOW FROM d) AS day_number,
    EXTRACT(ISODOW FROM d) IN (6, 7) AS is_weekend
FROM generate_series(
    DATE '2026-10-01',
    DATE '2026-10-10',
    INTERVAL '1 day'
) AS d
ORDER BY calendar_day;

-- 3. Формування переліку виключно робочих днів
SELECT d::date AS working_day
FROM generate_series(
    DATE '2026-10-01',
    DATE '2026-10-10',
    INTERVAL '1 day'
) AS d
WHERE EXTRACT(ISODOW FROM d) NOT IN (6, 7)
ORDER BY working_day;

-- 4. Побудова щоденного календаря замовлень через LEFT JOIN (10 днів)
SELECT
    cal.calendar_day::date,
    COUNT(o.id) AS orders_count
FROM generate_series(
    DATE '2026-10-01',
    DATE '2026-10-10',
    INTERVAL '1 day'
) AS cal(calendar_day)
LEFT JOIN lab42.lab_orders o
       ON o.order_date = cal.calendar_day::date
GROUP BY cal.calendar_day
ORDER BY cal.calendar_day;

-- 5. Завдання студенту: Побудова повного календаря замовлень на весь жовтень 2026 року (31 день)
SELECT
    cal.calendar_day::date,
    COUNT(o.id) AS orders_count
FROM generate_series(
    DATE '2026-10-01',
    DATE '2026-10-31',
    INTERVAL '1 day'
) AS cal(calendar_day)
LEFT JOIN lab42.lab_orders o
       ON o.order_date = cal.calendar_day::date
GROUP BY cal.calendar_day
ORDER BY cal.calendar_day;
