-- =====================================================================
-- Файл: 04_lateral_and_summary.sql
-- Тема: Корельовані підзапити LATERAL та підсумкове комплексне завдання
-- =====================================================================

-- Розділ 12. Корельовані підзапити: LATERAL
-- 12.1. Вибірка двох останніх вимірювань для кожного датчика через LEFT JOIN LATERAL
SELECT
    s.id      AS sensor_id,
    s.code,
    last_r.id AS reading_id,
    last_r.temperature
FROM lab5.sensors AS s
LEFT JOIN LATERAL (
    SELECT r.id, r.temperature
    FROM lab5.readings AS r
    WHERE r.sensor_id = s.id
    ORDER BY r.measured_at DESC, r.id DESC
    LIMIT 2
) AS last_r ON true
ORDER BY s.id, last_r.id DESC;

-- 12.2. Завдання 7: обмеження вибірки до одного останнього вимірювання на датчик
SELECT
    s.id      AS sensor_id,
    s.code,
    last_r.id AS reading_id,
    last_r.temperature
FROM lab5.sensors AS s
LEFT JOIN LATERAL (
    SELECT r.id, r.temperature
    FROM lab5.readings AS r
    WHERE r.sensor_id = s.id
    ORDER BY r.measured_at DESC, r.id DESC
    LIMIT 1
) AS last_r ON true
ORDER BY s.id;

-- Розділ 13. Підсумкове комплексне завдання
-- 13.1. Для кожного активного датчика з кодом ESP-%: останнє достовірне значення, загальна кількість та кількість недостовірних
SELECT
    s.code,
    latest.temperature AS last_valid,
    stats.total,
    stats.invalid
FROM lab5.sensors AS s
LEFT JOIN LATERAL (
    SELECT r.temperature
    FROM lab5.readings AS r
    WHERE r.sensor_id = s.id
      AND r.is_valid
      AND r.temperature IS NOT NULL
    ORDER BY r.measured_at DESC, r.id DESC
    LIMIT 1
) AS latest ON true
CROSS JOIN LATERAL (
    SELECT
        COUNT(*)                               AS total,
        COUNT(*) FILTER (WHERE NOT r.is_valid) AS invalid
    FROM lab5.readings AS r
    WHERE r.sensor_id = s.id
) AS stats
WHERE s.active
  AND s.code ILIKE 'ESP-%'
ORDER BY s.code;
