-- 02_schema.sql
-- Створення схем core та staging, а також таблиць відповідно до архітектури рівнів даних

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS staging;

ALTER SCHEMA core OWNER TO lab_student;
ALTER SCHEMA staging OWNER TO lab_student;

-- Таблиця пристроїв (core.device) з автоінкрементним первинним ключем
CREATE TABLE IF NOT EXISTS core.device (
    device_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    device_name VARCHAR(100) NOT NULL,
    model VARCHAR(100)
);

-- Таблиця сенсорів (core.sensor) з зовнішнім ключем до core.device
CREATE TABLE IF NOT EXISTS core.sensor (
    sensor_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    device_id INT NOT NULL,
    sensor_code VARCHAR(50) NOT NULL UNIQUE,
    quantity VARCHAR(100) NOT NULL,
    unit_symbol VARCHAR(20) NOT NULL,
    CONSTRAINT fk_sensor_device
        FOREIGN KEY (device_id)
        REFERENCES core.device (device_id)
        ON DELETE CASCADE
);

-- Таблиця staging для сирих показників із текстовими колонками
CREATE TABLE IF NOT EXISTS staging.raw_measurement (
    sensor_code TEXT,
    measured_at TEXT,
    value_text TEXT
);

ALTER TABLE core.device OWNER TO lab_student;
ALTER TABLE core.sensor OWNER TO lab_student;
ALTER TABLE staging.raw_measurement OWNER TO lab_student;
