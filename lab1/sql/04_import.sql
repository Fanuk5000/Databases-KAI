-- 04_import.sql
-- Імпорт даних через клієнтську команду \copy у терміналі psql

\copy staging.raw_measurement FROM './data/measurements.csv' WITH (FORMAT csv, HEADER true);

-- Перевірка результату завантаження
SELECT COUNT(*) AS total_rows FROM staging.raw_measurement;

-- Перегляд імпортованих записів
SELECT * FROM staging.raw_measurement;
