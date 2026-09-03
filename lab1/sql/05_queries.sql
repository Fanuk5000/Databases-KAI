-- 05_queries.sql
-- Опитування системних каталогів та аналіз метаданих

-- 1. Опитування каталогу баз даних
SELECT oid, datname FROM pg_database;

-- 2. Опитування просторів імен (схем)
SELECT oid, nspname FROM pg_namespace;

-- 3. Пошук створених таблиць через pg_class та pg_namespace (з'ясування OID)
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    c.oid     AS table_oid,
    c.relkind AS object_type
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('core', 'staging')
  AND c.relkind = 'r';

-- 4. Перегляд метаданих таблиці core.sensor через information_schema
SELECT
    table_schema,
    table_name,
    column_name,
    ordinal_position,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'core'
  AND table_name = 'sensor'
ORDER BY ordinal_position;
