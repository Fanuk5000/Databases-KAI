-- 01_schema.sql
-- Створення схеми experiment, таблиці test_result та наповнення початковими даними

CREATE SCHEMA IF NOT EXISTS experiment;
ALTER SCHEMA experiment OWNER TO lab_student;

CREATE TABLE IF NOT EXISTS experiment.test_result (
    result_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    experiment_name text NOT NULL,
    measured_value numeric,
    unit_symbol text
);

ALTER TABLE experiment.test_result OWNER TO lab_student;

INSERT INTO experiment.test_result (experiment_name, measured_value, unit_symbol)
VALUES
    ('Voltage test', 12.4, 'V'),
    ('Current test', 1.8, 'A'),
    ('Speed test', 1480, 'rpm');
