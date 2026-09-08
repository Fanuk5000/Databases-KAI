import os

from db_connections import close_db, get_connection, run_final_check


def create_schemas(conn) -> None:
    """Create core and staging schemas (Stage 3.1)."""
    print("--- Створення схем ---")
    with conn.cursor() as cur:
        cur.execute("CREATE SCHEMA IF NOT EXISTS core;")
        cur.execute("CREATE SCHEMA IF NOT EXISTS staging;")
    conn.commit()
    print("Схеми 'core' та 'staging' успішно створено.\n")


def create_tables(conn) -> None:
    """Create tables core.device, core.sensor, staging.raw_measurement (Stage 3.3 - 3.5)."""
    print("--- Створення таблиць ---")
    with conn.cursor() as cur:
        # Device table
        cur.execute("""
            CREATE TABLE IF NOT EXISTS core.device (
                device_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                device_name text NOT NULL,
                model text
            );
        """)

        # Sensor table with foreign key
        cur.execute("""
            CREATE TABLE IF NOT EXISTS core.sensor (
                sensor_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                device_id bigint REFERENCES core.device(device_id),
                sensor_code text NOT NULL,
                quantity text,
                unit_symbol text
            );
        """)

        # Staging table for loading measurements
        cur.execute("""
            CREATE TABLE IF NOT EXISTS staging.raw_measurement (
                sensor_code text,
                measured_at text,
                value_text text
            );
        """)
    conn.commit()
    print(
        "Таблиці 'core.device', 'core.sensor' та 'staging.raw_measurement' створено.\n"
    )


def inspect_created_tables(conn) -> None:
    """Inspect created tables via information_schema (Stage 3.6 - 3.7)."""
    print("--- Перевірка створених таблиць ---")
    with conn.cursor() as cur:
        cur.execute("""
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_schema IN ('core', 'staging')
            ORDER BY table_schema, table_name;
        """)
        for row in cur.fetchall():
            print(f"Таблиця: {row[0]}.{row[1]}")

        print("\n--- Структура таблиці core.sensor ---")
        cur.execute("""
            SELECT column_name, data_type, is_nullable
            FROM information_schema.columns
            WHERE table_schema = 'core' AND table_name = 'sensor'
            ORDER BY ordinal_position;
        """)
        for col in cur.fetchall():
            print(f"Колонка: {col[0]}, Тип: {col[1]}, Nullable: {col[2]}")
        print()


def insert_initial_data(conn) -> None:
    """Insert initial test device and sensor records (Stage 4.1, 4.3)."""
    print("--- Додавання початкових даних (DML) ---")
    with conn.cursor() as cur:
        # Check or insert device
        cur.execute(
            "SELECT device_id FROM core.device WHERE device_name = 'MOTOR_01' LIMIT 1;"
        )
        res = cur.fetchone()
        if not res:
            cur.execute("""
                INSERT INTO core.device (device_name, model)
                VALUES ('MOTOR_01', 'DC Motor')
                RETURNING device_id;
            """)
            dev_id = cur.fetchone()[0]
        else:
            dev_id = res[0]

        # Check or insert sensor
        cur.execute(
            "SELECT sensor_id FROM core.sensor WHERE sensor_code = 'MOTOR_01_RPM' LIMIT 1;"
        )
        if not cur.fetchone():
            cur.execute(
                """
                INSERT INTO core.sensor (device_id, sensor_code, quantity, unit_symbol)
                VALUES (%s, 'MOTOR_01_RPM', 'rotation_speed', 'rpm');
            """,
                (dev_id,),
            )
    conn.commit()
    print("Дані у 'core.device' та 'core.sensor' додано.\n")


def import_measurements_csv(conn, csv_filename: str = "measurements.csv") -> None:
    """Stream import measurements data from CSV file into staging.raw_measurement (Stage 6)."""
    print(f"--- Імпорт {csv_filename} через COPY FROM STDIN ---")
    csv_path = os.path.join(os.path.dirname(__file__), csv_filename)
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"File {csv_path} was not found!")

    with open(csv_path, "r", encoding="utf-8") as file, conn.cursor() as cur:
        # Truncate before copy to keep import idempotent
        cur.execute("TRUNCATE TABLE staging.raw_measurement;")

        # Check psycopg version
        if hasattr(cur, "copy"):
            # psycopg v3 syntax per manual
            with cur.copy("""
                COPY staging.raw_measurement (sensor_code, measured_at, value_text)
                FROM STDIN
                WITH (FORMAT CSV, HEADER TRUE)
            """) as copy:
                while data := file.read(8192):
                    copy.write(data)
        else:
            # psycopg2 fallback
            cur.copy_expert(
                """
                COPY staging.raw_measurement (sensor_code, measured_at, value_text)
                FROM STDIN
                WITH (FORMAT CSV, HEADER TRUE);
            """,
                file,
            )
    conn.commit()
    print("CSV-файл успішно імпортовано в 'staging.raw_measurement'.\n")


def verify_all_data(conn) -> bool:
    """Verify record counts and content across tables (Stage 4.2, 4.4, 6.3, 6.4)."""
    print("=== Перевірка вмісту таблиць ===")
    info_exists = False

    try:
        with conn.cursor() as cur:
            print("--- core.device ---")

            cur.execute("SELECT * FROM core.device;")

            for row in cur.fetchall():
                print(row)

            print("\n--- core.sensor ---")
            cur.execute("SELECT * FROM core.sensor;")
            for row in cur.fetchall():
                print(row)

            print("\n--- staging.raw_measurement (кількість записів) ---")
            cur.execute("SELECT COUNT(*) FROM staging.raw_measurement;")
            print("Count:", cur.fetchone()[0])

            print("\n--- staging.raw_measurement (всі записи) ---")
            cur.execute("SELECT * FROM staging.raw_measurement;")
            for row in cur.fetchall():
                print(row)
    except Exception as e:
        conn.rollback()
        print("Error, no something wrong with schemas:", e)
    else:
        info_exists = True

    print()
    return info_exists


if __name__ == "__main__":
    conn = get_connection()
    try:
        create_schemas(conn)
        create_tables(conn)
        inspect_created_tables(conn)
        insert_initial_data(conn)
        import_measurements_csv(conn)
        verify_all_data(conn)
        print("\n=== ПОВНА ДІАГНОСТИЧНА ПЕРЕВІРКА ===")
        run_final_check(conn)
    finally:
        close_db()
