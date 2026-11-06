"""
load_data_to_sql.py
"""

import sys  #--> sys.exit() --> لإيقاف تشغيل البرنامج عند ظهور خطأ
import os  #--> os.getenv() --> لقراءة إعدادات السيرفر من بيئة التشغيل
from pathlib import Path  #--> Path() --> للتعامل مع مسارات الملفات والمجلدات
import numpy as np  #--> numpy --> لمعالجة المصفوفات والقيم الفارغة
import pandas as pd  #--> pandas --> لقراءة ومعالجة جداول البيانات DataFrames
import pyodbc  #--> pyodbc --> للاتصال المباشر بقاعدة بيانات SQL Server

# إعداد المسارات ومعايير الاتصال
base_project_dir = Path(__file__).resolve().parent.parent.parent  #--> المجلد الرئيسي للمشروع
processed_data_dir = base_project_dir / "data" / "processed"  #--> مجلد البيانات المعالجة المعتمدة
schema_sql_dir = base_project_dir / "sql_server" / "schema"  #--> مجلد ملفات الـ SQL ومخططات الجداول

database_server_name = os.getenv("SQL_SERVER", r"localhost\SQLEXPRESS")  #--> اسم السيرفر
odbc_driver_name = os.getenv("SQL_DRIVER", "ODBC Driver 18 for SQL Server")  #--> مشغل ODBC
database_name = "cosmetics_store"  #--> اسم قاعدة البيانات المعتمدة للمشروع

sql_connection_string = (
    f"Driver={{{odbc_driver_name}}};"
    f"Server={database_server_name};"
    f"Database={database_name};"
    "Trusted_Connection=yes;"
    "TrustServerCertificate=yes;"
)


def open_database_connection():
    """
    فتح الاتصال بقاعدة البيانات وتفعيل ميزة الإدخال السريع
    """
    db_connection = pyodbc.connect(sql_connection_string, autocommit=False)  #--> تعطيل الحفظ التلقائي لحماية المعاملات
    db_cursor = db_connection.cursor()  #--> إنشاء مؤشر الأوامر
    db_cursor.fast_executemany = True  #--> تفعيل الإدخال السريع للبيانات
    return db_connection, db_cursor


def execute_sql_script_file(db_cursor, sql_file_path: Path):
    """
    قراءة وتنفيذ ملف SQL مقسم إلى دفعات عبر أمر GO
    """
    with open(sql_file_path, "r", encoding="utf-8") as file_handle:
        script_content = file_handle.read()

    batches = [b.strip() for b in script_content.split("\ngo\n") if b.strip()]
    if not batches:
        batches = [b.strip() for b in script_content.split("\nGO\n") if b.strip()]
    if not batches:
        batches = [script_content]

    for batch in batches:
        cleaned_lines = [l for l in batch.splitlines() if not l.strip().lower().startswith("use ")]
        executable_sql = "\n".join(cleaned_lines).strip()
        if executable_sql:
            db_cursor.execute(executable_sql)  #--> تنفيذ دفعة الـ SQL


def insert_dataframe_into_sql_table(db_cursor, table_name, columns, df, integer_columns=None):
    """
    تجهيز وإدخال بيانات DataFrame في جدول SQL المحدد
    """
    int_col_set = set(integer_columns or [])
    records = []

    for row_values in df[columns].itertuples(index=False):
        cleaned_row = []
        for col_name, cell_val in zip(columns, row_values):
            if pd.isna(cell_val) or cell_val is None:
                cleaned_row.append(None)  #--> تحويل القيم المفقودة إلى NULL
            elif col_name in int_col_set:
                cleaned_row.append(int(cell_val))  #--> تحويل الأرقام الصحيحة لـ int
            else:
                cleaned_row.append(cell_val)
        records.append(tuple(cleaned_row))

    placeholders = ", ".join(["?"] * len(columns))  #--> علامات الاستفهام المعيارية
    sql_query = f"INSERT INTO dbo.{table_name} ({', '.join(columns)}) VALUES ({placeholders})"
    db_cursor.executemany(sql_query, records)  #--> إدخال كل السجلات دفعة واحدة
    print(f"Loaded {table_name:<26}: {len(records):,} rows inserted.")


def generate_dim_date(db_cursor):
    """
    بناء جدول التواريخ DimDate ديناميكياً
    """
    print("Generating DimDate calendar table dynamically")
    db_cursor.execute("DELETE FROM dbo.DimDate;")
    dim_date_sql = """
    declare @min_date date = (select min(d) from (select min(invoice_date) d from dbo.FactSalesInvoice
                                                   union all select min(purchase_date) from dbo.FactPurchaseInvoice
                                                   union all select min(return_date)  from dbo.FactSalesReturnInvoice) x);
    declare @max_date date = (select max(d) from (select max(invoice_date) d from dbo.FactSalesInvoice
                                                   union all select max(purchase_date) from dbo.FactPurchaseInvoice
                                                   union all select max(return_date)  from dbo.FactSalesReturnInvoice) x);

    ;with DateSequence as (
        select @min_date as d
        union all
        select dateadd(day, 1, d) from DateSequence where d < @max_date
    )
    insert into dbo.DimDate
    select
        year(d) * 10000 + month(d) * 100 + day(d),
        d,
        year(d),
        datepart(quarter, d),
        month(d),
        convert(char(7), d, 120),
        choose(month(d), N'January', N'February', N'March', N'April', N'May', N'June',
                         N'July', N'August', N'September', N'October', N'November', N'December'),
        day(eomonth(d)),
        datepart(iso_week, d),
        (datediff(day, '19000101', d) % 7) + 1,
        choose((datediff(day, '19000101', d) % 7) + 1,
               N'Monday', N'Tuesday', N'Wednesday', N'Thursday', N'Friday', N'Saturday', N'Sunday'),
        case when (datediff(day, '19000101', d) % 7) + 1 in (5, 6) then 1 else 0 end
    from DateSequence
    option (maxrecursion 0);
    """
    db_cursor.execute(dim_date_sql)
    db_cursor.execute("SELECT COUNT(*) FROM dbo.DimDate;")
    count_val = db_cursor.fetchone()[0]
    print(f"Generated DimDate table with {count_val} calendar days.")


def log_missing_invoices(db_cursor):
    """
    رصد الفواتير المفقودة وتسجيلها في جدول MissingInvoicesLog
    """
    print("Detecting invoice sequence gaps for MissingInvoicesLog")
    db_cursor.execute("DELETE FROM dbo.MissingInvoicesLog;")
    missing_sql = """
    with SequenceBounds as (
        select min(invoice_no) as min_no, max(invoice_no) as max_no from dbo.FactSalesInvoice
    ),
    FullSequence as (
        select b.min_no as n, b.max_no from SequenceBounds b
        union all
        select n + 1, max_no from FullSequence where n < max_no
    ),
    DetectedGaps as (
        select t.n as missing_invoice_no
        from FullSequence t
        left join dbo.FactSalesInvoice s on s.invoice_no = t.n
        where s.invoice_no is null
    )
    insert into dbo.MissingInvoicesLog (missing_invoice_no, gap_after_invoice, gap_before_invoice)
    select
        g.missing_invoice_no,
        (select max(invoice_no) from dbo.FactSalesInvoice where invoice_no < g.missing_invoice_no) as gap_after_invoice,
        (select min(invoice_no) from dbo.FactSalesInvoice where invoice_no > g.missing_invoice_no) as gap_before_invoice
    from DetectedGaps g
    option (maxrecursion 0);
    """
    db_cursor.execute(missing_sql)
    db_cursor.execute("SELECT COUNT(*) FROM dbo.MissingInvoicesLog;")
    count_val = db_cursor.fetchone()[0]
    print(f"Logged {count_val} sequence gaps in MissingInvoicesLog.")


def rebuild_database_data(db_cursor):
    print("Executing table creation and constraint scripts")
    execute_sql_script_file(db_cursor, schema_sql_dir / "02_create_tables_and_constraints.sql")

    print("Loading clean data from data/processed")

    # 1. DimAccount
    accounts_df = pd.read_csv(processed_data_dir / "cleaned_accounts.csv").replace({np.nan: None})
    account_cols = [
        "acct_no", "acct_name", "nature", "account_classification", "classification_rationale",
        "is_internal", "balance_debit", "balance_credit", "discount_pct", "mobile", "address",
        "last_sale_date", "last_sale_total", "last_receipt_date", "last_receipt_value"
    ]
    insert_dataframe_into_sql_table(db_cursor, "DimAccount", account_cols, accounts_df, integer_columns=["acct_no", "is_internal"])

    # 2. DimProduct
    products_df = pd.read_csv(processed_data_dir / "cleaned_products.csv", dtype={"barcode": str}).replace({np.nan: None})
    products_df["barcode"] = products_df["barcode"].dropna().astype(str).str.strip().str.replace(r"\.0$", "", regex=True)
    product_cols = [
        "item_code", "item_name", "normalized_item_name", "product_scope", "product_category",
        "source_category", "total_qty", "unit", "sell_price", "avg_purchase_price",
        "last_purchase_price", "barcode", "item_code_1_MISLABELED", "stock_cost_valuation",
        "is_out_of_stock"
    ]
    insert_dataframe_into_sql_table(db_cursor, "DimProduct", product_cols, products_df, integer_columns=["item_code", "is_out_of_stock"])

    # 3. FactSalesInvoice
    sales_inv_df = pd.read_csv(processed_data_dir / "cleaned_sales_invoices.csv").replace({np.nan: None})
    sales_inv_df["order_time"] = sales_inv_df["time"]
    sales_inv_df["account_name"] = sales_inv_df["account"].dropna().astype(str).str.strip()
    sales_inv_df["total_discount"] = sales_inv_df["total_discount"].fillna(0.0)
    sales_inv_cols = [
        "invoice_no", "counter", "invoice_date", "order_time", "order_hour", "order_year",
        "order_month", "order_day_name", "is_weekend", "acct_no", "account_name",
        "customer_account_classification", "sale_type", "internal_account_status",
        "is_internal_account", "is_retail_sale", "payment_method", "total_qty",
        "total_discount", "final_total", "profit", "cash_drawer", "credit_card",
        "treasury", "paid_cash", "deferred", "due", "warehouse", "sales_rep", "added_by"
    ]
    sales_inv_int_cols = ["invoice_no", "counter", "order_hour", "order_year", "order_month", "is_weekend", "acct_no", "is_internal_account", "is_retail_sale"]
    insert_dataframe_into_sql_table(db_cursor, "FactSalesInvoice", sales_inv_cols, sales_inv_df, integer_columns=sales_inv_int_cols)

    # 4. FactSalesItem
    sales_items_df = pd.read_csv(processed_data_dir / "cleaned_sales_items.csv").replace({np.nan: None})
    sales_items_df["discount"] = sales_items_df["discount"].fillna(0.0)
    sales_item_cols = [
        "invoice_no", "invoice_row_index", "item_code", "item_name", "available_qty",
        "qty", "price", "discount", "profit", "line_final", "unit_cost"
    ]
    sales_item_int_cols = ["invoice_no", "invoice_row_index", "item_code"]
    insert_dataframe_into_sql_table(db_cursor, "FactSalesItem", sales_item_cols, sales_items_df, integer_columns=sales_item_int_cols)

    # 5. FactPurchaseInvoice
    purch_inv_df = pd.read_csv(processed_data_dir / "cleaned_purchase_invoices.csv").replace({np.nan: None})
    purch_inv_df["purchase_time"] = purch_inv_df["time"]
    purch_inv_df["account_name"] = purch_inv_df["account"].dropna().astype(str).str.strip()
    acct_map = dict(zip(accounts_df["acct_name"], accounts_df["acct_no"]))
    purch_inv_df["acct_no"] = purch_inv_df["account_name"].map(acct_map)
    purch_inv_df["total_discount"] = purch_inv_df["total_discount"].fillna(0.0)
    purch_inv_cols = [
        "invoice_no", "counter", "purchase_date", "purchase_time", "acct_no", "account_name",
        "payment_method", "total_qty", "total_discount", "final_total", "cash_drawer",
        "paid_cash", "deferred", "due", "warehouse", "added_by"
    ]
    purch_inv_int_cols = ["invoice_no", "counter", "acct_no"]
    insert_dataframe_into_sql_table(db_cursor, "FactPurchaseInvoice", purch_inv_cols, purch_inv_df, integer_columns=purch_inv_int_cols)

    # 6. FactPurchaseItem
    purch_items_df = pd.read_csv(processed_data_dir / "cleaned_purchase_items.csv").replace({np.nan: None})
    purch_items_df["discount"] = purch_items_df["discount"].fillna(0.0)
    purch_item_cols = [
        "invoice_no", "invoice_row_index", "item_code", "item_name", "available_qty",
        "qty", "price", "discount", "line_final"
    ]
    purch_item_int_cols = ["invoice_no", "invoice_row_index", "item_code"]
    insert_dataframe_into_sql_table(db_cursor, "FactPurchaseItem", purch_item_cols, purch_items_df, integer_columns=purch_item_int_cols)

    # 7. FactSalesReturnInvoice
    returns_inv_df = pd.read_csv(processed_data_dir / "cleaned_sales_returns_invoices.csv").replace({np.nan: None})
    returns_inv_df["return_time"] = returns_inv_df["time"]
    returns_inv_df["account_name"] = returns_inv_df["account"].dropna().astype(str).str.strip()
    returns_inv_df["acct_no"] = returns_inv_df["account_name"].map(acct_map)
    returns_inv_df["total_discount"] = returns_inv_df["total_discount"].fillna(0.0)
    returns_inv_cols = [
        "return_invoice_no", "counter", "return_date", "return_time", "return_year",
        "return_month", "return_day_name", "original_invoice_no", "original_invoice_status",
        "is_linked_to_sales", "is_retail_sale", "acct_no", "account_name", "payment_method",
        "total_qty", "total_discount", "final_total", "profit", "cash_drawer", "warehouse"
    ]
    returns_inv_int_cols = ["return_invoice_no", "counter", "return_year", "return_month", "original_invoice_no", "is_linked_to_sales", "is_retail_sale", "acct_no"]
    insert_dataframe_into_sql_table(db_cursor, "FactSalesReturnInvoice", returns_inv_cols, returns_inv_df, integer_columns=returns_inv_int_cols)

    # 8. FactSalesReturnItem
    returns_items_df = pd.read_csv(processed_data_dir / "cleaned_sales_returns_items.csv").replace({np.nan: None})
    returns_items_df["discount"] = returns_items_df["discount"].fillna(0.0)
    returns_item_cols = [
        "return_invoice_no", "invoice_row_index", "item_code", "item_name", "available_qty",
        "qty", "price", "discount", "profit", "line_final"
    ]
    returns_item_int_cols = ["return_invoice_no", "invoice_row_index", "item_code"]
    insert_dataframe_into_sql_table(db_cursor, "FactSalesReturnItem", returns_item_cols, returns_items_df, integer_columns=returns_item_int_cols)

    # إنشاء التقويم وسجل الفجوات
    generate_dim_date(db_cursor)
    log_missing_invoices(db_cursor)

    # إنشاء الفهارس والـ Views
    print("Creating performance indexes and analytical views")
    execute_sql_script_file(db_cursor, schema_sql_dir / "03_create_indexes.sql")
    execute_sql_script_file(db_cursor, schema_sql_dir / "04_create_views.sql")
    print("Indexes and analytical views created successfully.")


def run_pre_commit_validations(db_cursor):
    errors = []
    print("Running pre-commit integrity and financial reconciliation checks")

    # 1. مطابقة أعداد الصفوف
    expected_row_counts = {
        "DimAccount": 37, "DimProduct": 1437, "FactSalesInvoice": 5505,
        "FactSalesItem": 10891, "FactPurchaseInvoice": 32, "FactPurchaseItem": 1658,
        "FactSalesReturnInvoice": 127, "FactSalesReturnItem": 157, "MissingInvoicesLog": 26
    }
    for tbl_name, expected_cnt in expected_row_counts.items():
        db_cursor.execute(f"SELECT COUNT(*) FROM dbo.{tbl_name};")
        actual_cnt = db_cursor.fetchone()[0]
        if actual_cnt != expected_cnt:
            errors.append(f"Row count mismatch on {tbl_name}: {actual_cnt} != {expected_cnt}")

    # 2. مطابقة الإجماليات المالية
    db_cursor.execute("SELECT * FROM dbo.vw_StoreNetSalesSummary;")
    row = db_cursor.fetchone()
    cols = [c[0] for c in db_cursor.description]
    summary = dict(zip(cols, row))

    benchmarks = [
        ("Gross book sales", float(summary["gross_book_sales"]), 978248.29),
        ("Gross book profit", float(summary["gross_book_profit"]), 198590.41),
        ("Non-retail excluded sales", float(summary["non_retail_excluded_sales"]), 62482.00),
        ("Retail gross sales", float(summary["retail_gross_sales"]), 915766.29),
        ("Total returns value", float(summary["total_returns"]), -13779.78),
        ("Retail net sales", float(summary["retail_net_sales"]), 901986.51),
        ("Retail net profit", float(summary["retail_net_profit"]), 192534.06),
        ("Retail net margin %", float(summary["retail_net_margin_pct"]), 21.35),
    ]

    for b_name, actual_val, expected_val in benchmarks:
        if abs(actual_val - expected_val) > 0.05:
            errors.append(f"Financial check failed on {b_name}: {actual_val} != {expected_val}")
        else:
            print(f"Verified {b_name:<26}: {actual_val:>12,.2f} EGP (Matches benchmark)")

    # 3. فحص التكامل المرجعي وعدم وجود سجلات يتيمة
    fk_queries = [
        ("Sales Items -> Sales Invoices", "SELECT COUNT(*) FROM dbo.FactSalesItem si LEFT JOIN dbo.FactSalesInvoice s ON si.invoice_no = s.invoice_no WHERE s.invoice_no IS NULL;"),
        ("Sales Items -> Products", "SELECT COUNT(*) FROM dbo.FactSalesItem si LEFT JOIN dbo.DimProduct p ON si.item_code = p.item_code WHERE p.item_code IS NULL;"),
        ("Sales Invoices -> Accounts", "SELECT COUNT(*) FROM dbo.FactSalesInvoice s LEFT JOIN dbo.DimAccount a ON s.acct_no = a.acct_no WHERE s.acct_no IS NOT NULL AND a.acct_no IS NULL;"),
        ("Purchase Items -> Purchase Invoices", "SELECT COUNT(*) FROM dbo.FactPurchaseItem pi LEFT JOIN dbo.FactPurchaseInvoice p ON pi.invoice_no = p.invoice_no WHERE p.invoice_no IS NULL;"),
        ("Purchase Items -> Products", "SELECT COUNT(*) FROM dbo.FactPurchaseItem pi LEFT JOIN dbo.DimProduct pr ON pi.item_code = pr.item_code WHERE pr.item_code IS NULL;"),
        ("Purchase Invoices -> Accounts", "SELECT COUNT(*) FROM dbo.FactPurchaseInvoice p LEFT JOIN dbo.DimAccount a ON p.acct_no = a.acct_no WHERE p.acct_no IS NOT NULL AND a.acct_no IS NULL;"),
        ("Return Items -> Return Invoices", "SELECT COUNT(*) FROM dbo.FactSalesReturnItem ri LEFT JOIN dbo.FactSalesReturnInvoice r ON ri.return_invoice_no = r.return_invoice_no WHERE r.return_invoice_no IS NULL;"),
        ("Return Items -> Products", "SELECT COUNT(*) FROM dbo.FactSalesReturnItem ri LEFT JOIN dbo.DimProduct pr ON ri.item_code = pr.item_code WHERE pr.item_code IS NULL;"),
        ("Return Invoices -> Accounts", "SELECT COUNT(*) FROM dbo.FactSalesReturnInvoice r LEFT JOIN dbo.DimAccount a ON r.acct_no = a.acct_no WHERE r.acct_no IS NOT NULL AND a.acct_no IS NULL;"),
    ]
    for rel_name, query_str in fk_queries:
        db_cursor.execute(query_str)
        orphans = db_cursor.fetchone()[0]
        if orphans != 0:
            errors.append(f"Orphan records found in {rel_name}: {orphans}")

    return errors


def main():
    print(f"Starting ETL rebuild on database: {database_name} at server: {database_server_name}")

    try:
        db_connection, db_cursor = open_database_connection()
    except pyodbc.Error as e:
        print(f"Database connection error: {e}")
        sys.exit(1)

    try:
        rebuild_database_data(db_cursor)
        errors = run_pre_commit_validations(db_cursor)

        if errors:
            print("Validation errors detected:")
            for err in errors:
                print(f" * {err}")
            db_connection.rollback()
            print("Transaction rolled back.")
            sys.exit(1)

        print("All validations passed. Committing transaction")
        db_connection.commit()
        print("ETL completed successfully.")

    except Exception as e:
        print(f"Runtime error during ETL: {e}")
        db_connection.rollback()
        sys.exit(1)
    finally:
        db_connection.close()


if __name__ == "__main__":
    main()
