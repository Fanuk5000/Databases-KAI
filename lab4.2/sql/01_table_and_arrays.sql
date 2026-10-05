-- ============================================================================
-- Лабораторна робота 4.2: Типи даних PostgreSQL, JSONB, масиви, час і generate_series
-- Частина 1: Створення таблиці, первинне наповнення та операції з масивами
-- ============================================================================

-- 1. Створення ізольованої схеми
CREATE SCHEMA IF NOT EXISTS lab42;
SET search_path TO lab42, public;

-- Видалення старої версії таблиці
DROP TABLE IF EXISTS lab42.lab_orders;

-- 2. Створення навчальної таблиці з розширеними типами даних
CREATE TABLE lab42.lab_orders (
    id              INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_name   VARCHAR(100) NOT NULL,
    amount          NUMERIC(10,2) NOT NULL,
    quantity        INTEGER NOT NULL DEFAULT 1,
    is_paid         BOOLEAN NOT NULL DEFAULT false,
    order_date      DATE NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processing_time INTERVAL,
    tags            TEXT[],
    metadata        JSONB
);

-- 3. Наповнення базовими навчальними даними (записи 1-3)
INSERT INTO lab42.lab_orders (
    customer_name, amount, quantity, is_paid, order_date, processing_time, tags, metadata
) VALUES
(
    'Іваненко О. П.', 32500.00, 1, true, DATE '2026-10-02', INTERVAL '2 days 4 hours',
    ARRAY['терміново', 'крихкий'],
    '{"payment":{"method":"card","paid":true},"priority":5,"items":["ноутбук","миша"]}'::jsonb
),
(
    'Петренко С. В.', 780.50, 3, false, DATE '2026-10-05', INTERVAL '1 day',
    ARRAY['стандартна доставка'],
    '{"payment":{"method":"cash","paid":false},"priority":2,"items":["ручки","зошити"]}'::jsonb
),
(
    'Коваленко І. М.', 1450.00, 2, true, DATE '2026-10-05', INTERVAL '6 hours',
    ARRAY['терміново'],
    '{"payment":{"method":"card","paid":true},"priority":4,"items":["клавіатура"]}'::jsonb
);

-- 4. Перевірка таблиці після початкового завантаження
SELECT * FROM lab42.lab_orders ORDER BY id;

-- 5. Завдання студенту: Додавання четвертого замовлення з власними даними
INSERT INTO lab42.lab_orders (
    customer_name, amount, quantity, is_paid, order_date, processing_time, tags, metadata
) VALUES (
    'Сидоренко В. М.', 5200.00, 1, true, DATE '2026-10-07', INTERVAL '12 hours',
    ARRAY['крихкий'],
    '{"payment":{"method":"card","paid":true},"priority":3,"items":["монітор"]}'::jsonb
);

-- Перевірка 4 записів
SELECT * FROM lab42.lab_orders ORDER BY id;

-- 6. Перегляд першого елемента масиву (1-based індексація)
SELECT id, customer_name, tags[1] AS first_tag
FROM lab42.lab_orders;

-- 7. Пошук значення всередині масиву за допомогою оператора ANY
SELECT id, customer_name, tags
FROM lab42.lab_orders
WHERE 'терміново' = ANY(tags);

-- 8. Визначення кількості елементів масиву (array_length)
SELECT id, tags, array_length(tags, 1) AS tags_count
FROM lab42.lab_orders;

-- 9. Перетворення масиву на окремі реляційні рядки (unnest)
SELECT id, unnest(tags) AS tag
FROM lab42.lab_orders
ORDER BY id;

-- 10. Завдання студенту: Вибірка замовлень, де масив tags містить рівно один елемент
SELECT id, customer_name, tags, array_length(tags, 1) AS tags_count
FROM lab42.lab_orders
WHERE array_length(tags, 1) = 1;
