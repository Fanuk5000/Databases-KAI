-- 02_search_path.sql
-- Дослідження поведінки просторів імен та шляху пошуку схем search_path

-- 1. Перевірка поточного значення search_path
SHOW search_path;

-- 2. Спроба некваліфікованого доступу (призводить до помилки relation does not exist)
-- SELECT * FROM test_result;

-- 3. Тимчасове додавання схеми experiment до search_path
SET search_path TO experiment, public;

-- 4. Успішне виконання некваліфікованого запиту
SELECT * FROM test_result;

-- 5. Відновлення дефолтного search_path сесії
RESET search_path;
