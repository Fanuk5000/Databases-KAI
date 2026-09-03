-- 01_init_user_db.sql
-- Створення ролі та бази даних
-- Виконується від імені суперкористувача (postgres)

DO
$do$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = 'lab_student'
   ) THEN
      CREATE ROLE lab_student WITH LOGIN PASSWORD 'secretpassword' SUPERUSER;
   END IF;
END
$do$;

SELECT 'CREATE DATABASE lab_measurements OWNER lab_student'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lab_measurements')\gexec

GRANT ALL PRIVILEGES ON DATABASE lab_measurements TO lab_student;
