-- 02_roles_and_privileges.sql
-- Створення ролі column_user та налаштування гранулярних прав доступу

RESET ROLE;

-- 1. Створення ролі без права самостійного входу (контейнер прав)
CREATE ROLE column_user NOLOGIN;

-- 2. Надання ролі postgres дозволу на перемикання (для PostgreSQL 16+ використовується WITH SET TRUE)
GRANT column_user TO postgres WITH SET TRUE;

-- 3. Надання привілею USAGE на схему (обов'язкова умова доступу до таблиць усередині схеми)
GRANT USAGE ON SCHEMA lab_columns TO column_user;

-- 4. Надання повного права на читання таблиці students
GRANT SELECT ON lab_columns.students TO column_user;

-- 5. Гранульоване надання права на редагування ТІЛЬКИ стовпця name (Column-Level Privilege)
GRANT UPDATE (name) ON lab_columns.students TO column_user;
