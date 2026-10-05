-- ============================================================================
-- Лабораторна робота 4.2: Типи даних PostgreSQL, JSONB, масиви, час і generate_series
-- Частина 2: Робота з JSONB та керування часовими поясами
-- ============================================================================

SET search_path TO lab42, public;

-- 1. Отримання простого скалярного значення з JSONB через оператор ->>
SELECT id, metadata->>'priority' AS priority
FROM lab42.lab_orders;

-- 2. Отримання вкладеного значення (payment -> method)
SELECT id, metadata->'payment'->>'method' AS payment_method
FROM lab42.lab_orders;

-- 3. Фільтрація за значенням усередині JSONB з явним приведенням ::boolean
SELECT id, customer_name
FROM lab42.lab_orders
WHERE (metadata->'payment'->>'paid')::boolean = true;

-- 4. Пошук JSON-фрагмента за допомогою оператора входження @>
SELECT id, customer_name
FROM lab42.lab_orders
WHERE metadata @> '{"payment":{"method":"card"}}'::jsonb;

-- 5. Розгортання вкладеного JSON-масиву items у текстові рядки
SELECT id, jsonb_array_elements_text(metadata->'items') AS item
FROM lab42.lab_orders
ORDER BY id;

-- 6. Завдання студенту: Знайти замовлення з пріоритетом вище 3 (приведення до ::integer)
SELECT id, customer_name, (metadata->>'priority')::integer AS priority
FROM lab42.lab_orders
WHERE (metadata->>'priority')::integer > 3;

-- ============================================================================
-- Часові пояси та оператор AT TIME ZONE
-- ============================================================================

-- 7. Перевірка поточного часового поясу сеансу
SHOW timezone;

-- 8. Встановлення часового поясу Europe/Kyiv на рівні сеансу
SET timezone = 'Europe/Kyiv';
SELECT CURRENT_TIMESTAMP;

-- 9. Конвертація одного фіксованого моменту часу між різними поясами
SELECT
    TIMESTAMPTZ '2026-10-15 12:00+03' AS original_time,
    TIMESTAMPTZ '2026-10-15 12:00+03' AT TIME ZONE 'UTC' AS utc_time,
    TIMESTAMPTZ '2026-10-15 12:00+03' AT TIME ZONE 'America/New_York' AS new_york_time;

-- 10. Перетворення збереженого поля created_at у пояси UTC та Europe/Kyiv
SELECT                         
    id,
    created_at,
    created_at AT TIME ZONE 'UTC' AS utc_time,
    created_at AT TIME ZONE 'Europe/Kyiv' AS kyiv_time
FROM lab42.lab_orders;

-- 11. Завдання студенту: Додавання відображення created_at у часовому поясі 'Asia/Tokyo'
SELECT                         
    id,
    created_at,
    created_at AT TIME ZONE 'UTC' AS utc_time,
    created_at AT TIME ZONE 'Europe/Kyiv' AS kyiv_time,
    created_at AT TIME ZONE 'Asia/Tokyo' AS tokyo_time
FROM lab42.lab_orders;
