from db_connections import (
    check_catalogs_and_oids,
    check_db_info,
    close_db,
    get_connection,
    list_databases,
    list_schemas,
    run_final_check,
)
from db_creations import (
    create_schemas,
    create_tables,
    import_measurements_csv,
    insert_initial_data,
    inspect_created_tables,
    verify_all_data,
)


def get_db_info() -> None:
    conn = get_connection()
    try:
        check_db_info(conn)
        list_databases(conn)
        list_schemas(conn)
        check_catalogs_and_oids(conn)
    except Exception as e:
        conn.rollback()
        print("Error:", e)
    else:
        print("Всі читання даних з БД пройшли успішно!\n")
    finally:
        close_db()


def perf_db_creations() -> None:
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
    except Exception as e:
        conn.rollback()
        print("Error:", e)
    else:
        print("Все записано та прочитано успішно у БД!\n")
    finally:
        close_db()

def is_data_exists() -> bool:
    conn = get_connection()
    exists = False
    try:
        exists = run_final_check(conn, hide_print=True)
    except Exception as e:
        conn.rollback()
        print("Error:", e)
    finally:
        close_db()
    return exists


if __name__ == "__main__":
    if is_data_exists():
        print("=== Іноформація про БД до будь-яких змін ===")
        get_db_info()
    perf_db_creations()
    get_db_info()
