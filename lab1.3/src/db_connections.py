import os
import sys

from dotenv import load_dotenv

# Support for psycopg (v3 per manual) with fallback to psycopg2
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

# Load environment variables from .env
load_dotenv()

session = None


def get_connection():
    """Create or return an active database connection."""
    global session
    if session is not None and not getattr(session, "closed", False):
        return session

    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise ValueError("DATABASE_URL was not found in the .env file!")

    print("Підключення до Supabase PostgreSQL...")
    try:
        session = psycopg.connect(database_url)
        print("Підключення успішно встановлено!\n")
        return session
    except Exception as e:
        raise RuntimeError(f"Failed to connect to the database: {e}") from e


def connect_db() -> None:
    """Entry point for testing connection."""
    get_connection()


def check_db_info(conn=None) -> None:
    """Print basic system information about current session (Stage 2)."""
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
    """List all available databases (Stage 2.4, analogous to \\l)."""
    conn = conn or get_connection()
    with conn.cursor() as cur:
        cur.execute("SELECT datname FROM pg_database ORDER BY datname;")
        print("=== Список баз даних ===")
        for row in cur.fetchall():
            print("DB:", row[0])
        print()


def list_schemas(conn=None) -> None:
    """List all schemas via information_schema (Stage 2.5, analogous to \\dn)."""
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
    """Inspect system catalogs pg_database, pg_namespace, pg_class and OIDs (Stage 5)."""
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


def run_final_check(conn=None, hide_print=False) -> bool:
    """Comprehensive final diagnostic check on all objects (Stage 7 / check_lab1.py)."""
    conn = conn or get_connection()
    has_schemas = False
    with conn.cursor() as cur:
        if not hide_print:
            print("\n=== PostgreSQL ===")
        cur.execute("SELECT version();")
        db_data = cur.fetchone()

        if not hide_print and db_data:
            print(db_data[0])

        if not hide_print:
            print("\n=== Connection ===")
        cur.execute("""
            SELECT current_database(), current_user, pg_backend_pid();
        """)
        if not hide_print:
            print(cur.fetchone())

        if not hide_print:
            print("\n=== Schemas ===")
        cur.execute("""
            SELECT schema_name
            FROM information_schema.schemata
            WHERE schema_name IN ('core', 'staging')
            ORDER BY schema_name;
        """)
        if not hide_print:
            for row in cur.fetchall():
                print(row)

        if not hide_print:
            print("\n=== Tables ===")
        cur.execute("""
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_schema IN ('core', 'staging')
            ORDER BY table_schema, table_name;
        """)
        if not hide_print:
            for row in cur.fetchall():
                print(row)

        for title, query in (
            ("Devices", "SELECT * FROM core.device;"),
            ("Sensors", "SELECT * FROM core.sensor;"),
            ("Measurements", "SELECT * FROM staging.raw_measurement;"),
        ):
            if not hide_print:
                print(f"\n=== {title} ===")
            try:
                cur.execute(query)
                if not hide_print:
                    for row in cur.fetchall():
                        print(row)
            except Exception as e:
                conn.rollback()
                if not hide_print:
                    print(f"[Notice] Could not read {title}: {e}")
                has_schemas = True
        if not hide_print:
            print()
        return has_schemas


def close_db() -> None:
    """Close the database connection."""
    global session
    if session is not None and not getattr(session, "closed", False):
        session.close()
        session = None
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
