-- =====================================================================
-- Файл: 02_queries_aggregation_filter.sql
-- Тема: Пошук за шаблоном ILIKE, агрегація, NULL, FILTER та DISTINCT ON
-- =====================================================================

-- Розділ 3. Пошук за шаблоном: ILIKE
-- 3.1. Базовий вибір активних датчиків за шаблоном коду ESP-
SELECT id, code, name
FROM lab5.sensors
WHERE code ILIKE 'ESP-%'
ORDER BY id;

-- 3.2. Завдання 1: пошук датчиків, у назві яких міститься слово «датчик» у будь-якому регістрі
SELECT id, code, name
FROM lab5.sensors
WHERE name ILIKE '%датчик%'
ORDER BY id;

-- Розділ 4. Агрегатні функції та NULL
-- 4.1. Дослідження різниці між COUNT(*) та COUNT(temperature), розрахунок середнього та екстремумів
SELECT
    sensor_id,
    COUNT(*)                   AS rows_total,
    COUNT(temperature)         AS values_known,
    ROUND(AVG(temperature), 2) AS avg_temp,
    MIN(temperature)           AS min_temp,
    MAX(temperature)           AS max_temp
FROM lab5.readings
GROUP BY sensor_id
ORDER BY sensor_id;

-- 4.2. Завдання 2: фільтрація сформованих груп через HAVING (середня температура > 20 °C)
SELECT sensor_id, ROUND(AVG(temperature), 2) AS avg_temp
FROM lab5.readings
GROUP BY sensor_id
HAVING AVG(temperature) > 20
ORDER BY sensor_id;

-- Розділ 5. Клауза FILTER: диференційована агрегація
-- 5.1. Базовий підрахунок валідних, невалідних та гарячих показів
SELECT
    sensor_id,
    COUNT(*)                                  AS total,
    COUNT(*) FILTER (WHERE is_valid)          AS valid,
    COUNT(*) FILTER (WHERE NOT is_valid)      AS invalid,
    COUNT(*) FILTER (WHERE temperature >= 30) AS hot
FROM lab5.readings
GROUP BY sensor_id
ORDER BY sensor_id;

-- 5.2. Завдання 3: додавання стовпця hot_valid (достовірні вимірювання >= 30 °C)
SELECT
    sensor_id,
    COUNT(*)                                               AS total,
    COUNT(*) FILTER (WHERE is_valid)                       AS valid,
    COUNT(*) FILTER (WHERE NOT is_valid)                   AS invalid,
    COUNT(*) FILTER (WHERE temperature >= 30)              AS hot,
    COUNT(*) FILTER (WHERE is_valid AND temperature >= 30) AS hot_valid
FROM lab5.readings
GROUP BY sensor_id
ORDER BY sensor_id;

-- Розділ 6. DISTINCT ON: отримання першого запису групи
-- 6.1. Останнє достовірне вимірювання кожного датчика
SELECT DISTINCT ON (sensor_id)
    sensor_id, id, measured_at, temperature
FROM lab5.readings
WHERE is_valid
  AND temperature IS NOT NULL
ORDER BY sensor_id, measured_at DESC, id DESC;

-- 6.2. Завдання 4: останній запис кожного датчика незалежно від is_valid
SELECT DISTINCT ON (sensor_id)
    sensor_id, id, measured_at, temperature, is_valid
FROM lab5.readings
ORDER BY sensor_id, measured_at DESC, id DESC;
