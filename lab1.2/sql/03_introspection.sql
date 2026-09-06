-- 03_introspection.sql
-- Дослідження метаданих через information_schema та системний каталог pg_catalog

-- 1. Опитування стандартного представлення information_schema.columns
SELECT
    table_schema,
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'experiment'
  AND table_name = 'test_result'
ORDER BY ordinal_position;

-- 2. Низькорівневий запит до pg_catalog.pg_class та pg_catalog.pg_namespace
SELECT
    c.oid,
    n.nspname AS schema_name,
    c.relname,
    c.relkind
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'experiment'
  AND c.relname = 'test_result';

-- 3. Дослідження псевдотипу regclass та функції to_regclass
SELECT 'experiment.test_result'::regclass;
SELECT to_regclass('experiment.test_result');
SELECT to_regclass('experiment.unknown_table');
