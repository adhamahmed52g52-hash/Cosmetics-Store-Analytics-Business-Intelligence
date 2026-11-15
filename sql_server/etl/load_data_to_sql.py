import sys
import os
from pathlib import Path
import pandas as pd
import pyodbc

# مسارات المشروع الرئيسية
base_project_dir = Path(__file__).resolve().parent.parent.parent
processed_data_dir = base_project_dir / "data" / "processed"
schema_sql_dir = base_project_dir / "sql_server" / "schema"

# إعدادات الاتصال بقاعدة البيانات
database_server_name = os.getenv("SQL_SERVER", r"localhost\SQLEXPRESS")
odbc_driver_name = os.getenv("SQL_DRIVER", "ODBC Driver 18 for SQL Server")
database_name = "cosmetics_store"

sql_connection_string = (
    f"Driver={{{odbc_driver_name}}};"
    f"Server={database_server_name};"
    f"Database={database_name};"
    "Trusted_Connection=yes;"
    "TrustServerCertificate=yes;"
)


def run_sql_file(cursor, sql_file_path: Path):
    # قراءة ملف SQL وتشغيله دفعة دفعة بالاعتماد على أمر GO
    with open(sql_file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # فصل الأوامر بكلمة GO
    batches = [b.strip() for b in content.replace("\nGO\n", "\ngo\n").split("\ngo\n") if b.strip()]
    for batch in batches:
        # استبعاد أوامر USE لأننا متصلين بالفعل بنفس قاعدة البيانات
        sql = "\n".join([line for line in batch.splitlines() if not line.strip().lower().startswith("use ")]).strip()
        if sql:
            cursor.execute(sql)


def load_table(cursor, table_name, df, columns, int_columns=None):
    # إدخال بيانات الجدول دفعة واحدة وبطريقة سريعة
    int_cols = set(int_columns or [])
    records = []

    # تجهيز البيانات وتحويل القيم الفارغة إلى None لتصبح NULL في SQL
    for row in df[columns].itertuples(index=False):
        cleaned_row = []
        for col_name, val in zip(columns, row):
            if pd.isna(val) or val is None:
                cleaned_row.append(None)
            elif col_name in int_cols:
                cleaned_row.append(int(val))
            else:
                cleaned_row.append(val)
        records.append(tuple(cleaned_row))

    # تكوين جملة الـ INSERT وتشغيلها عبر fast_executemany
    placeholders = ", ".join(["?"] * len(columns))
    sql_query = f"INSERT INTO dbo.{table_name} ({', '.join(columns)}) VALUES ({placeholders})"
    cursor.executemany(sql_query, records)
    print(f"Loaded {table_name:<26}: {len(records):,} rows inserted.")


def generate_dim_date(cursor):
    # توليد جدول التقويم الزمني لجميع أيام المشروع ديناميكياً
    print("Generating DimDate calendar table dynamically")
    cursor.execute("DELETE FROM dbo.DimDate;")
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
    cursor.execute(dim_date_sql)
    cursor.execute("SELECT COUNT(*) FROM dbo.DimDate;")
    count_val = cursor.fetchone()[0]
    print(f"Generated DimDate table with {count_val} calendar days.")


def log_missing_invoices(cursor):
    # رصد الفجوات في تسلسل أرقام الفواتير وحفظها في جدول MissingInvoicesLog
    print("Detecting invoice sequence gaps for MissingInvoicesLog")
    cursor.execute("DELETE FROM dbo.MissingInvoicesLog;")
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
    cursor.execute(missing_sql)
    cursor.execute("SELECT COUNT(*) FROM dbo.MissingInvoicesLog;")
    count_val = cursor.fetchone()[0]
    print(f"Logged {count_val} sequence gaps in MissingInvoicesLog.")


def rebuild_database_data(cursor):
    # 1. إنشاء الجداول والعلاقات
    print("Executing table creation and constraint scripts")
    run_sql_file(cursor, schema_sql_dir / "02_create_tables_and_constraints.sql")

    print("Loading clean data from data/processed")

    # 1. دليل الحسابات (DimAccount)
    accounts_df = pd.read_csv(processed_data_dir / "cleaned_accounts.csv")
    account_cols = [
        "acct_no", "acct_name", "nature", "account_classification", "classification_rationale",
        "is_internal", "balance_debit", "balance_credit", "discount_pct", "mobile", "address",
        "last_sale_date", "last_sale_total", "last_receipt_date", "last_receipt_value"
    ]
    load_table(cursor, "DimAccount", accounts_df, account_cols, int_columns=["acct_no", "is_internal"])

    # خريطة لربط أسماء الحسابات بأرقامها في باقي الجداول
    acct_map = dict(zip(accounts_df["acct_name"].astype(str).str.strip(), accounts_df["acct_no"]))

    # 2. كتالوج المنتجات (DimProduct)
    products_df = pd.read_csv(processed_data_dir / "cleaned_products.csv", dtype={"barcode": str})
    products_df["barcode"] = products_df["barcode"].dropna().astype(str).str.strip().str.replace(r"\.0$", "", regex=True)
    product_cols = [
        "item_code", "item_name", "normalized_item_name", "product_scope", "product_category",
        "source_category", "total_qty", "unit", "sell_price", "avg_purchase_price",
        "last_purchase_price", "barcode", "item_code_1_MISLABELED", "stock_cost_valuation",
        "is_out_of_stock"
    ]
    load_table(cursor, "DimProduct", products_df, product_cols, int_columns=["item_code", "is_out_of_stock"])

    # 3. فواتير المبيعات (FactSalesInvoice)
    sales_inv_df = pd.read_csv(processed_data_dir / "cleaned_sales_invoices.csv")
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
    sales_inv_ints = ["invoice_no", "counter", "order_hour", "order_year", "order_month", "is_weekend", "acct_no", "is_internal_account", "is_retail_sale"]
    load_table(cursor, "FactSalesInvoice", sales_inv_df, sales_inv_cols, int_columns=sales_inv_ints)

    # 4. بنود المبيعات (FactSalesItem)
    sales_items_df = pd.read_csv(processed_data_dir / "cleaned_sales_items.csv")
    sales_items_df["discount"] = sales_items_df["discount"].fillna(0.0)
    sales_item_cols = [
        "invoice_no", "invoice_row_index", "item_code", "item_name", "available_qty",
        "qty", "price", "discount", "profit", "line_final", "unit_cost"
    ]
    load_table(cursor, "FactSalesItem", sales_items_df, sales_item_cols, int_columns=["invoice_no", "invoice_row_index", "item_code"])

    # 5. فواتير المشتريات (FactPurchaseInvoice)
    purch_inv_df = pd.read_csv(processed_data_dir / "cleaned_purchase_invoices.csv")
    purch_inv_df["purchase_time"] = purch_inv_df["time"]
    purch_inv_df["account_name"] = purch_inv_df["account"].dropna().astype(str).str.strip()
    purch_inv_df["acct_no"] = purch_inv_df["account_name"].map(acct_map)
    purch_inv_df["total_discount"] = purch_inv_df["total_discount"].fillna(0.0)
    purch_inv_cols = [
        "invoice_no", "counter", "purchase_date", "purchase_time", "acct_no", "account_name",
        "payment_method", "total_qty", "total_discount", "final_total", "cash_drawer",
        "paid_cash", "deferred", "due", "warehouse", "added_by"
    ]
    load_table(cursor, "FactPurchaseInvoice", purch_inv_df, purch_inv_cols, int_columns=["invoice_no", "counter", "acct_no"])

    # 6. بنود المشتريات (FactPurchaseItem)
    purch_items_df = pd.read_csv(processed_data_dir / "cleaned_purchase_items.csv")
    purch_items_df["discount"] = purch_items_df["discount"].fillna(0.0)
    purch_item_cols = [
        "invoice_no", "invoice_row_index", "item_code", "item_name", "available_qty",
        "qty", "price", "discount", "line_final"
    ]
    load_table(cursor, "FactPurchaseItem", purch_items_df, purch_item_cols, int_columns=["invoice_no", "invoice_row_index", "item_code"])

    # 7. فواتير مرتجع المبيعات (FactSalesReturnInvoice)
    returns_inv_df = pd.read_csv(processed_data_dir / "cleaned_sales_returns_invoices.csv")
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
    returns_inv_ints = ["return_invoice_no", "counter", "return_year", "return_month", "original_invoice_no", "is_linked_to_sales", "is_retail_sale", "acct_no"]
    load_table(cursor, "FactSalesReturnInvoice", returns_inv_df, returns_inv_cols, int_columns=returns_inv_ints)

    # 8. بنود مرتجع المبيعات (FactSalesReturnItem)
    returns_items_df = pd.read_csv(processed_data_dir / "cleaned_sales_returns_items.csv")
    returns_items_df["discount"] = returns_items_df["discount"].fillna(0.0)
    returns_item_cols = [
        "return_invoice_no", "invoice_row_index", "item_code", "item_name", "available_qty",
        "qty", "price", "discount", "profit", "line_final"
    ]
    load_table(cursor, "FactSalesReturnItem", returns_items_df, returns_item_cols, int_columns=["return_invoice_no", "invoice_row_index", "item_code"])

    # 9. التقويم الزمني وفجوات الفواتير
    generate_dim_date(cursor)
    log_missing_invoices(cursor)

    # 10. إنشاء الفهارس والـ Views
    print("Creating performance indexes and analytical views")
    run_sql_file(cursor, schema_sql_dir / "03_create_indexes.sql")
    run_sql_file(cursor, schema_sql_dir / "04_create_views.sql")
    print("Indexes and analytical views created successfully.")


def run_pre_commit_validations(cursor):
    # اختبارات الجودة والمطابقة المالية والتكامل المرجعي قبل حفظ التغييرات
    errors = []
    print("Running pre-commit integrity and financial reconciliation checks")

    # 1. مطابقة أعداد الصفوف بالضبط
    expected_row_counts = {
        "DimAccount": 37, "DimProduct": 1437, "FactSalesInvoice": 5505,
        "FactSalesItem": 10891, "FactPurchaseInvoice": 32, "FactPurchaseItem": 1658,
        "FactSalesReturnInvoice": 127, "FactSalesReturnItem": 157, "MissingInvoicesLog": 26
    }
    for tbl, expected_cnt in expected_row_counts.items():
        cursor.execute(f"SELECT COUNT(*) FROM dbo.{tbl};")
        actual_cnt = cursor.fetchone()[0]
        if actual_cnt != expected_cnt:
            errors.append(f"Row count mismatch on {tbl}: {actual_cnt} != {expected_cnt}")

    # 2. مطابقة الأرقام المالية مع المعايير الدفترية المعتمدة
    cursor.execute("SELECT * FROM dbo.vw_StoreNetSalesSummary;")
    row = cursor.fetchone()
    cols = [c[0] for c in cursor.description]
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

    for name, actual_val, expected_val in benchmarks:
        if abs(actual_val - expected_val) > 0.05:
            errors.append(f"Financial check failed on {name}: {actual_val} != {expected_val}")
        else:
            print(f"Verified {name:<26}: {actual_val:>12,.2f} EGP (Matches benchmark)")

    # 3. التأكد من خلو الجداول من أي سجلات يتيمة
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
        cursor.execute(query_str)
        orphans = cursor.fetchone()[0]
        if orphans != 0:
            errors.append(f"Orphan records found in {rel_name}: {orphans}")

    return errors


def main():
    print(f"Starting ETL rebuild on database: {database_name} at server: {database_server_name}")

    try:
        connection = pyodbc.connect(sql_connection_string, autocommit=False)
        cursor = connection.cursor()
        cursor.fast_executemany = True
    except pyodbc.Error as e:
        print(f"Database connection error: {e}")
        sys.exit(1)

    try:
        rebuild_database_data(cursor)
        errors = run_pre_commit_validations(cursor)

        if errors:
            print("Validation errors detected:")
            for err in errors:
                print(f" * {err}")
            connection.rollback()
            print("Transaction rolled back")
            sys.exit(1)

        print("All validations passed. Committing transaction")
        connection.commit()
        print("ETL completed successfully")

    except Exception as e:
        print(f"Runtime error during ETL: {e}")
        connection.rollback()
        sys.exit(1)
    finally:
        connection.close()


if __name__ == "__main__":
    main()
