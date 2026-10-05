-- ============================================================================
-- Лабораторна робота 4.2: Типи даних PostgreSQL, JSONB, масиви, час і generate_series
-- Частина 4: Користувацький тип ENUM та підсумкові комплексні завдання
-- ============================================================================

SET search_path TO lab42, public;

-- ============================================================================
-- Додаткове завдання: створення перелічуваного типу ENUM
-- ============================================================================

-- 1. Створення типу переліку для статусів замовлення
DROP TYPE IF EXISTS lab42.order_status;
CREATE TYPE lab42.order_status AS ENUM (
    'new',
    'processing',
    'completed'
);

-- 2. Додавання стовпця status до таблиці з дефолтним значенням 'new'
ALTER TABLE lab42.lab_orders
ADD COLUMN status lab42.order_status NOT NULL DEFAULT 'new';

-- 3. Оновлення статусу для першого замовлення
UPDATE lab42.lab_orders
SET status = 'processing'
WHERE id = 1;

-- Перевірка статусів
SELECT id, customer_name, status
FROM lab42.lab_orders;

-- ============================================================================
-- Підсумкове завдання
-- ============================================================================

-- 4. Додавання двох додаткових замовлень (записи 5 та 6)
INSERT INTO lab42.lab_orders (
    customer_name, amount, quantity, is_paid, order_date, processing_time, tags, metadata, status
) VALUES
(
    'Мельник Т. В.', 8400.00, 1, true, DATE '2026-10-12', INTERVAL '1 day 2 hours',
    ARRAY['терміново', 'кур''єр'],
    '{"payment":{"method":"card","paid":true},"priority":5,"items":["планшет"]}'::jsonb,
    'processing'
),
(
    'Бондаренко А. С.', 430.00, 5, false, DATE '2026-10-15', INTERVAL '4 hours',
    ARRAY['стандартна доставка'],
    '{"payment":{"method":"cash","paid":false},"priority":1,"items":["блокнот","кабель"]}'::jsonb,
    'new'
);

-- 5. Пошук усіх замовлень із тегом 'терміново'
SELECT id, customer_name, tags
FROM lab42.lab_orders
WHERE 'терміново' = ANY(tags);

-- 6. Виведення способу оплати та факту сплати з metadata для кожного замовлення
SELECT
    id,
    customer_name,
    metadata->'payment'->>'method' AS payment_method,
    (metadata->'payment'->>'paid')::boolean AS is_paid_json
FROM lab42.lab_orders;

-- 7. Вибірка замовлень з priority більше 3
SELECT id, customer_name, amount, (metadata->>'priority')::integer AS priority
FROM lab42.lab_orders
WHERE (metadata->>'priority')::integer > 3;

-- 8. Відображення created_at у часових поясах UTC та Europe/Kyiv
SELECT
    id,
    customer_name,
    created_at AT TIME ZONE 'UTC' AS created_at_utc,
    created_at AT TIME ZONE 'Europe/Kyiv' AS created_at_kyiv
FROM lab42.lab_orders;

-- 9. Побудова повного календаря за весь жовтень 2026 року з кількістю замовлень та сумою виручки
SELECT
    cal.calendar_day::date AS date,
    EXTRACT(ISODOW FROM cal.calendar_day) AS day_of_week,
    COUNT(o.id) AS orders_count,
    COALESCE(SUM(o.amount), 0.00) AS total_revenue
FROM generate_series(
    DATE '2026-10-01',
    DATE '2026-10-31',
    INTERVAL '1 day'
) AS cal(calendar_day)
LEFT JOIN lab42.lab_orders o
       ON o.order_date = cal.calendar_day::date
GROUP BY cal.calendar_day
ORDER BY cal.calendar_day;
