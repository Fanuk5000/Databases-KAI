import os
import sys

from dotenv import load_dotenv

# Підтримка psycopg (v3 за методичкою) з fallback на psycopg2
try:
    import psycopg

    PSYCOPG_VERSION = 3
except ImportError:
    try:
        import psycopg2 as psycopg

        PSYCOPG_VERSION = 2
    except ImportError:
        print(
            "Помилка: встановіть psycopg ('pip install psycopg[binary]' або 'pip install psycopg2-binary')"
        )
        sys.exit(1)

# Завантаження змінних оточення з .env
load_dotenv()

session = None


def get_connection():
    """Створює або повертає активне з'єднання з базою даних."""
    global session
    if session is not None and not getattr(session, "closed", False):
        return session

    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise ValueError("DATABASE_URL не знайдено у файлі .env!")

    print("Підключення до Supabase PostgreSQL...")
    try:
        if PSYCOPG_VERSION == 3:
            session = psycopg.connect(database_url)
        else:
            session = psycopg.connect(database_url)
        print("Підключення успішно встановлено!\n")
        return session
    except Exception as e:
        raise RuntimeError(f"Не вдалося підключитися до бази даних: {e}") from e


def connect_db() -> None:
    """Точка входу для тесту з'єднання."""
    get_connection()


def check_db_info(conn=None) -> None:
    """Виводить базову системну інформацію про поточний сеанс (Етап 2)."""
    conn = conn or get_connection()
    with conn.cursor() as cur:
        cur.execute("""
            SELECT
                current_database(),
                current_user,
                pg_backend_pid(),
                version();
        """)
        result = cur.fetchone()
        if result and len(result) == 4:
            print("=== Інформація про підключення ===")
            print("Database:          ", result[0])
            print("User:              ", result[1])
            print("PID:               ", result[2])
            print("PostgreSQL version:", result[3])
            print()


def list_databases(conn=None) -> None:
    """Виводить список усіх доступних баз даних (Етап 2.4, аналог \\l)."""
    conn = conn or get_connection()
    with conn.cursor() as cur:
        cur.execute("SELECT datname FROM pg_database ORDER BY datname;")
        print("=== Список баз даних ===")
        for row in cur.fetchall():
            print("DB:", row[0])
        print()


def list_schemas(conn=None) -> None:
    """Виводить список усіх схем через information_schema (Етап 2.5, аналог \\dn)."""
    conn = conn or get_connection()
    with conn.cursor() as cur:
        cur.execute("""
            SELECT schema_name
            FROM information_schema.schemata
            ORDER BY schema_name;
        """)
        print("=== Список схем ===")
        for row in cur.fetchall():
            print("Schema:", row[0])
        print()


def check_catalogs_and_oids(conn=None) -> None:
    """Дослідження системних каталогів pg_database, pg_namespace, pg_class та OID (Етап 5)."""
    conn = conn or get_connection()
    with conn.cursor() as cur:
        print("=== OID бази 'postgres' (pg_database) ===")
        cur.execute("SELECT oid, datname FROM pg_database WHERE datname = 'postgres';")
        for row in cur.fetchall():
            print(f"OID: {row[0]}, DB: {row[1]}")

        print("\n=== OID схем 'core' та 'staging' (pg_namespace) ===")
        cur.execute("""
            SELECT oid, nspname
            FROM pg_namespace
            WHERE nspname IN ('core', 'staging')
            ORDER BY nspname;
        """)
        for row in cur.fetchall():
            print(f"OID: {row[0]}, Schema: {row[1]}")

        print("\n=== OID таблиць через pg_class ===")
        cur.execute("""
            SELECT c.oid, n.nspname AS schema_name, c.relname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('core', 'staging')
              AND c.relkind = 'r'
            ORDER BY n.nspname, c.relname;
        """)
        for row in cur.fetchall():
            print(f"OID: {row[0]}, Schema: {row[1]}, Table: {row[2]}")

        print("\n=== Структура таблиць через information_schema.columns ===")
        cur.execute("""
            SELECT table_schema, table_name, column_name, data_type
            FROM information_schema.columns
            WHERE table_schema IN ('core', 'staging')
            ORDER BY table_schema, table_name, ordinal_position;
        """)
        for row in cur.fetchall():
            print(row)
        print()


def run_final_check(conn=None) -> None:
    """Контрольна підсумкова перевірка всіх об'єктів (Етап 7 / check_lab1.py)."""
    conn = conn or get_connection()
    with conn.cursor() as cur:
        print("\n=== PostgreSQL ===")
        cur.execute("SELECT version();")
        print(cur.fetchone()[0])

        print("\n=== Connection ===")
        cur.execute("""
            SELECT current_database(), current_user, pg_backend_pid();
        """)
        print(cur.fetchone())

        print("\n=== Schemas ===")
        cur.execute("""
            SELECT schema_name
            FROM information_schema.schemata
            WHERE schema_name IN ('core', 'staging')
            ORDER BY schema_name;
        """)
        for row in cur.fetchall():
            print(row)

        print("\n=== Tables ===")
        cur.execute("""
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_schema IN ('core', 'staging')
            ORDER BY table_schema, table_name;
        """)
        for row in cur.fetchall():
            print(row)

        print("\n=== Devices ===")
        cur.execute("SELECT * FROM core.device;")
        for row in cur.fetchall():
            print(row)

        print("\n=== Sensors ===")
        cur.execute("SELECT * FROM core.sensor;")
        for row in cur.fetchall():
            print(row)

        print("\n=== Measurements ===")
        cur.execute("SELECT * FROM staging.raw_measurement;")
        for row in cur.fetchall():
            print(row)
        print()


def close_db() -> None:
    """Закриває з'єднання."""
    global session
    if session is not None and not getattr(session, "closed", False):
        session.close()
        print("З'єднання закрито.")


if __name__ == "__main__":
    conn = get_connection()
    try:
        check_db_info(conn)
        list_databases(conn)
        list_schemas(conn)
        check_catalogs_and_oids(conn)
    finally:
        close_db()
