# ------------------------------------------------------------------------------
# 1 LIBRARIES 
# ------------------------------------------------------------------------------
import sys  #--> sys.exit() --> بيوقف تنفيذ البرنامج لو حصل خطأ
import os  #--> os.getenv() --> بيقرأ إعدادات من متغيرات البيئة في الجهاز
from pathlib import Path  #--> Path() --> للتعامل مع مسارات الملفات والمجلدات
import numpy as np  #--> numpy --> للتعامل مع القيم المفقودة والمصفوفات
import pandas as pd  #--> pandas --> لقراءة ومعالجة ملفات البيانات DataFrames
import pyodbc  #--> pyodbc --> للاتصال بقاعدة بيانات SQL Server وتنفيذ الأوامر

PROCESSED_DIR = Path(__file__).resolve().parent.parent.parent / "data" / "processed"  #--> resolve() --> بيحدد المسار الكامل لمجلد البيانات النظيفة
SQL_SERVER = os.getenv("SQL_SERVER", r"localhost\SQLEXPRESS")  #--> getenv() --> بيقرأ اسم السيرفر من الجهاز ولو مش موجود بيستخدم القيمة الافتراضية
SQL_DRIVER = os.getenv("SQL_DRIVER", "ODBC Driver 18 for SQL Server")  #--> بيقرأ اسم الـ Driver بنفس الطريقة
CONN_STR = (  #--> إعدادات الاتصال بقاعدة البيانات
    f"Driver={{{SQL_DRIVER}}};"
    f"Server={SQL_SERVER};"
    "Database=cosmetics_store;"
    "Trusted_Connection=yes;"
    "TrustServerCertificate=yes;"
)


# ------------------------------------------------------------------------------
# 2 DATABASE CONNECTION 
# ------------------------------------------------------------------------------
def get_connection():  #--> دالة لفتح الاتصال مع الداتابيز
    conn = pyodbc.connect(CONN_STR, autocommit=False)  #--> connect() --> بيفتح اتصال جديد مع تعطيل الحفظ التلقائي عشان المعاملات
    cursor = conn.cursor()  #--> cursor() --> بيعمل مؤشر لتنفيذ أوامر SQL
    cursor.fast_executemany = True  #--> تفعيل الإدخال السريع للبيانات لتحسين الأداء
    return conn, cursor  #--> بيرجع كائن الاتصال والمؤشر


def insert_table(cursor, table, columns, df, int_cols=None):  #--> دالة لإدخال بيانات الجدول في الداتابيز
    int_set = set(int_cols or [])  #--> set() --> بيحول قائمة الأعمدة الصحيحة لمجموعة للبحث السريع
    records = [  #--> تجهيز الصفوف كـ Tuples مع معالجة القيم الفارغة والأنواع
        tuple(
            None if pd.isna(val) else int(val) if col in int_set else val  #--> isna() --> بيحول القيم المفقودة لـ NULL في SQL
            for col, val in zip(columns, row)  #--> zip() --> بيربط أسماء الأعمدة بقيم الصف
        )
        for row in df[columns].itertuples(index=False)  #--> itertuples() --> بيمر على صفوف DataFrame كـ Tuples
    ]
    placeholders = ", ".join(["?"] * len(columns))  #--> join() --> بيجهز علامات الاستفهام كمعاملات للأمر
    sql = f"INSERT INTO dbo.{table} ({', '.join(columns)}) VALUES ({placeholders})"  #--> صياغة أمر الإدخال بأسماء الأعمدة
    cursor.executemany(sql, records)  #--> executemany() --> بينفذ أمر الإدخال على كل الصفوف دفعة واحدة
    print(f" {table}: {len(records):,} rows inserted")  #--> len() --> بيرجع عدد السجلات , print() --> بيطبع عدد الصفوف اللي دخلت الجدول


# ------------------------------------------------------------------------------
# 3 LOAD ALL DATASETS
# ------------------------------------------------------------------------------
def load_all_tables(cursor):  #--> دالة لتفريغ وتحميل كل الجداول بترتيب المفاتيح الأجنبية
    print("1. Clearing existing tables")  #--> print() --> بيطبع بدء خطوة تفريغ الجداول القديمة
    tables_to_clear = [  #--> قائمة الجداول بترتيب الحذف العكسي عشان قيود Foreign Key
        "FactSalesReturnItem", "FactSalesReturnInvoice",
        "FactPurchaseItem", "FactPurchaseInvoice",
        "FactSalesItem", "FactSalesInvoice",
        "DimProduct", "DimAccount"
    ]
    for table in tables_to_clear:  #--> حلقة تكرارية على كل جدول لتفريغه
        cursor.execute(f"DELETE FROM dbo.{table};")  #--> execute() --> بينفذ أمر حذف كل البيانات من الجدول

    print("2. Loading tables from data/processed")  #--> print() --> بيطبع بدء خطوة تحميل البيانات النظيفة

    # 1. DimAccount
    df_acc = pd.read_csv(PROCESSED_DIR / "cleaned_accounts.csv").replace({np.nan: None})  #--> read_csv() --> بيقرأ ملف الحسابات , replace() --> بيستبدل NaN بـ None
    acc_map = dict(zip(df_acc["acct_name"].astype(str).str.strip(), df_acc["acct_no"].astype(int)))  #--> zip() --> dict() --> بيعمل قاموس لربط اسم الحساب برقمه
    acc_cols = [
        "acct_no", "acct_name", "nature", "category", "balance_debit", "balance_credit",
        "discount_pct", "sell_price", "last_sale_date", "last_sale_total"
    ]
    insert_table(cursor, "DimAccount", acc_cols, df_acc, int_cols=["acct_no"])  #--> استدعاء دالة الإدخال لجدول الحسابات

    # 2. DimProduct
    df_prod = pd.read_csv(PROCESSED_DIR / "cleaned_products.csv", dtype={"barcode": str}).replace({np.nan: None})  #--> read_csv() --> بيقرأ ملف المنتجات
    df_prod["barcode"] = df_prod["barcode"].dropna().astype(str).str.strip().str.replace(r"\.0$", "", regex=True)  #--> replace() --> بيحذف أي كسر عشري من الباركود
    prod_cols = [
        "item_code", "item_name", "normalized_item_name", "product_scope", "product_category",
        "source_category", "barcode", "total_qty", "sell_price", "avg_purchase_price",
        "last_purchase_price", "stock_cost_valuation"
    ]
    insert_table(cursor, "DimProduct", prod_cols, df_prod, int_cols=["item_code"])  #--> استدعاء دالة الإدخال لجدول المنتجات

    # 3. FactSalesInvoice
    df_sinv = pd.read_csv(PROCESSED_DIR / "cleaned_sales_invoices.csv").replace({np.nan: None})  #--> read_csv() --> بيقرأ فواتير المبيعات
    df_sinv["order_time"] = df_sinv["time"]  #--> توحيد اسم عمود الوقت
    df_sinv["account_name"] = df_sinv["account"].dropna().astype(str).str.strip()  #--> تنظيف نص اسم العميل
    df_sinv["is_weekend"] = df_sinv["is_weekend"].astype(int)  #--> تحويل قيمة الويك إند لعدد صحيح
    df_sinv["is_internal_account"] = df_sinv["is_internal_account"].astype(int)  #--> تحويل عمود حسابات الشركاء لصحيح
    df_sinv["is_retail_sale"] = df_sinv.get("is_retail_sale", df_sinv["customer_type"] == "Walk-in Retail").astype(int)  #--> get() --> بيحدد لو العملية بيع قطاعي
    df_sinv["total_discount"] = df_sinv["total_discount"].fillna(0.0)  #--> fillna() --> بيعوض عن الخصم بـ 0 لو فارغ
    sinv_cols = [
        "invoice_no", "counter", "invoice_date", "order_time", "order_hour", "order_year",
        "order_month", "order_day_name", "is_weekend", "acct_no", "account_name", "customer_type",
        "internal_account_status", "is_internal_account", "is_retail_sale", "payment_method",
        "total_qty", "total_discount", "final_total", "profit", "cash_drawer", "credit_card",
        "treasury", "paid_cash", "deferred", "due", "warehouse", "added_by"
    ]
    sinv_int = ["invoice_no", "counter", "order_hour", "order_year", "order_month", "is_weekend", "acct_no", "is_internal_account", "is_retail_sale"]
    insert_table(cursor, "FactSalesInvoice", sinv_cols, df_sinv, int_cols=sinv_int)  #--> إدخال فواتير المبيعات

    # 4. FactSalesItem
    df_sitem = pd.read_csv(PROCESSED_DIR / "cleaned_sales_items.csv").replace({np.nan: None})  #--> read_csv() --> بيقرأ بنود فواتير المبيعات
    df_sitem["discount"] = df_sitem["discount"].fillna(0.0)  #--> fillna() --> بيعوض عن الخصم الفارغ بـ 0
    sitem_cols = [
        "invoice_no", "invoice_row_index", "item_code", "item_name", "available_qty",
        "qty", "price", "discount", "profit", "line_final", "unit_cost"
    ]
    sitem_int = ["invoice_no", "invoice_row_index", "item_code"]
    insert_table(cursor, "FactSalesItem", sitem_cols, df_sitem, int_cols=sitem_int)  #--> إدخال بنود المبيعات

    # 5. FactPurchaseInvoice
    df_pinv = pd.read_csv(PROCESSED_DIR / "cleaned_purchase_invoices.csv").replace({np.nan: None})  #--> read_csv() --> بيقرأ فواتير المشتريات
    df_pinv["purchase_time"] = df_pinv["time"]  #--> توحيد اسم عمود وقت الشراء
    df_pinv["account_name"] = df_pinv["account"].dropna().astype(str).str.strip()  #--> تنظيف اسم المورد
    df_pinv["acct_no"] = df_pinv["account_name"].map(acc_map)  #--> map() --> بيجلب رقم الحساب للمورد من قاموس الحسابات
    df_pinv["total_discount"] = df_pinv["total_discount"].fillna(0.0)  #--> fillna() --> بيعوض عن الخصم بـ 0
    pinv_cols = [
        "invoice_no", "counter", "purchase_date", "purchase_time", "acct_no", "account_name",
        "payment_method", "total_qty", "total_discount", "final_total", "cash_drawer",
        "paid_cash", "deferred", "due", "warehouse", "added_by"
    ]
    pinv_int = ["invoice_no", "counter", "acct_no"]
    insert_table(cursor, "FactPurchaseInvoice", pinv_cols, df_pinv, int_cols=pinv_int)  #--> إدخال فواتير المشتريات

    # 6. FactPurchaseItem
    df_pitem = pd.read_csv(PROCESSED_DIR / "cleaned_purchase_items.csv").replace({np.nan: None})  #--> read_csv() --> بيقرأ بنود المشتريات
    df_pitem["discount"] = df_pitem["discount"].fillna(0.0)  #--> fillna() --> بيعوض عن الخصم بـ 0
    pitem_cols = [
        "invoice_no", "invoice_row_index", "item_code", "item_name", "available_qty",
        "qty", "price", "discount", "line_final"
    ]
    pitem_int = ["invoice_no", "invoice_row_index", "item_code"]
    insert_table(cursor, "FactPurchaseItem", pitem_cols, df_pitem, int_cols=pitem_int)  #--> إدخال بنود المشتريات

    # 7. FactSalesReturnInvoice
    df_srinv = pd.read_csv(PROCESSED_DIR / "cleaned_sales_returns_invoices.csv").replace({np.nan: None})  #--> read_csv() --> بيقرأ فواتير المرتجعات
    df_srinv["return_time"] = df_srinv["time"]  #--> توحيد اسم وقت المرتجع
    df_srinv["account_name"] = df_srinv["account"].dropna().astype(str).str.strip()  #--> تنظيف اسم العميل
    df_srinv["acct_no"] = df_srinv["account_name"].map(acc_map)  #--> map() --> بيجلب رقم الحساب للعميل
    df_srinv["total_discount"] = df_srinv["total_discount"].fillna(0.0)  #--> fillna() --> تعويض الخصم بـ 0
    srinv_cols = [
        "return_invoice_no", "counter", "return_date", "return_time", "return_year",
        "return_month", "return_day_name", "original_invoice_no", "acct_no", "account_name",
        "payment_method", "total_qty", "total_discount", "final_total", "profit",
        "cash_drawer", "warehouse"
    ]
    srinv_int = ["return_invoice_no", "counter", "return_year", "return_month", "original_invoice_no", "acct_no"]
    insert_table(cursor, "FactSalesReturnInvoice", srinv_cols, df_srinv, int_cols=srinv_int)  #--> إدخال فواتير المرتجعات

    # 8. FactSalesReturnItem
    df_sritem = pd.read_csv(PROCESSED_DIR / "cleaned_sales_returns_items.csv").replace({np.nan: None})  #--> read_csv() --> بيقرأ بنود المرتجعات
    df_sritem["discount"] = df_sritem["discount"].fillna(0.0)  #--> fillna() --> تعويض الخصم بـ 0
    sritem_cols = [
        "return_invoice_no", "invoice_row_index", "item_code", "item_name", "available_qty",
        "qty", "price", "discount", "profit", "line_final"
    ]
    sritem_int = ["return_invoice_no", "invoice_row_index", "item_code"]
    insert_table(cursor, "FactSalesReturnItem", sritem_cols, df_sritem, int_cols=sritem_int)  #--> إدخال بنود المرتجعات


# ------------------------------------------------------------------------------
# 4 PRE-COMMIT VALIDATIONS
# ------------------------------------------------------------------------------
def run_validations(cursor):  #--> دالة لتنفيذ فحوصات المطابقة الستة قبل الاعتماد النهائي
    errors = []  #--> قائمة لتجميع أي أخطاء تظهر أثناء الفحص
    print("3. Running Pre-Commit Validations")  #--> print() --> بيطبع بدء خطوة التدقيق والمطابقة

    # 1. Row counts
    expected_rows = {  #--> القاموس المعياري لأعداد صفوف كل الجداول
        "DimAccount": 37, "DimProduct": 1437, "FactSalesInvoice": 5505,
        "FactSalesItem": 10891, "FactPurchaseInvoice": 32, "FactPurchaseItem": 1658,
        "FactSalesReturnInvoice": 127, "FactSalesReturnItem": 157
    }
    for table, exp in expected_rows.items():  #--> حلقة للمرور على كل جدول ومطابقة عدد صفوفه
        cursor.execute(f"SELECT COUNT(*) FROM dbo.{table};")  #--> execute() --> بيحسب عدد الصفوف الفعلي في الجدول
        act = cursor.fetchone()[0]  #--> fetchone() --> بيرجع نتيجة العد
        if act != exp:  #--> شرط للتأكد من تطابق عدد الصفوف مع الرقم المعتمد
            errors.append(f"Row count mismatch on {table}: {act} != {exp}")  #--> append() --> بيسجل الخطأ في حالة عدم التطابق

    # 2. Financial benchmarks
    cursor.execute("SELECT SUM(final_total), SUM(profit) FROM dbo.FactSalesInvoice;")  #--> execute() --> بيجمع إجمالي المبيعات والأرباح من الفواتير
    sales_hdr, profit_hdr = cursor.fetchone()  #--> fetchone() --> بيستخرج ناتج المجموعين
    cursor.execute("SELECT SUM(line_final), SUM(profit) FROM dbo.FactSalesItem;")  #--> execute() --> بيجمع الإيراد والربح من بنود الفواتير
    sales_lines, profit_lines = cursor.fetchone()  #--> fetchone() --> بيستخرج ناتج بنود المبيعات
    cursor.execute("SELECT SUM(final_total) FROM dbo.FactPurchaseInvoice;")  #--> execute() --> بيحسب إجمالي قيمة المشتريات
    purchases = cursor.fetchone()[0]  #--> fetchone() --> بيستخرج مجموع المشتريات
    cursor.execute("SELECT SUM(final_total) FROM dbo.FactSalesReturnInvoice;")  #--> execute() --> بيحسب إجمالي قيمة المرتجعات
    returns = cursor.fetchone()[0]  #--> fetchone() --> بيستخرج مجموع المرتجعات
    cursor.execute("SELECT SUM(stock_cost_valuation) FROM dbo.DimProduct;")  #--> execute() --> بيحسب صافي تقييم المخزون المالي
    inventory = cursor.fetchone()[0]  #--> fetchone() --> بيستخرج تقييم المخزون

    financial_checks = [  #--> قائمة المعايير المالية المعتمدة للتحقق منها
        ("Gross Sales (Header)", float(sales_hdr), 978248.29),
        ("Gross Sales (Lines)", float(sales_lines), 978248.29),
        ("Gross Profit (Header)", float(profit_hdr), 198590.41),
        ("Gross Profit (Lines)", float(profit_lines), 198590.41),
        ("Purchases Total", float(purchases), 1118614.71),
        ("Returns Total", float(returns), -13779.78),
        ("Inventory Valuation", float(inventory), 322251.11),
    ]
    for name, act, exp in financial_checks:  #--> حلقة للمرور على المعايير المالية ومطابقتها
        if abs(act - exp) > 0.05:  #--> abs() --> بيتأكد إن الفرق أقل من 5 قروش
            errors.append(f"Financial check failed on {name}: {act} != {exp}")  #--> append() --> بيضيف رسالة الخطأ المالي

    # 3. Customer segmentation
    expected_segments = {  #--> المعايير المعتمدة لشرائح العملاء (عدد الفواتير، الإيراد)
        "Walk-in Retail": (5417, 859532.14),
        "Registered Commercial": (57, 53161.65),
        "Internal Partner": (26, 54684.50),
        "Supplier Settlement": (5, 10870.00),
    }
    cursor.execute("SELECT customer_type, COUNT(*), SUM(final_total) FROM dbo.FactSalesInvoice GROUP BY customer_type;")  #--> execute() --> تجميع مبيعات كل شريحة
    act_segments = {r[0]: (r[1], float(r[2])) for r in cursor.fetchall()}  #--> fetchall() --> بيحول نتائج الشرائح لقاموس للمقارنة
    for seg, (exp_invs, exp_rev) in expected_segments.items():  #--> فحص ومطابقة كل شريحة عملاء
        if seg not in act_segments:  #--> التأكد من وجود الشريحة في البيانات
            errors.append(f"Missing customer segment: {seg}")  #--> append() --> تسجيل غياب الشريحة
        elif act_segments[seg][0] != exp_invs or abs(act_segments[seg][1] - exp_rev) > 0.05:  #--> التأكد من عدد الفواتير والإيراد
            errors.append(f"Segment mismatch on {seg}: {act_segments[seg]} != ({exp_invs}, {exp_rev})")  #--> تسجيل أي عدم تطابق

    # 4. Product taxonomy
    cursor.execute("SELECT COUNT(DISTINCT product_category), COUNT(DISTINCT product_scope) FROM dbo.DimProduct;")  #--> execute() --> بيحسب عدد الأقسام والنطاقات الفريدة
    cats, scopes = cursor.fetchone()  #--> fetchone() --> استخراج أعداد الأقسام والنطاقات
    if cats != 7 or scopes != 5:  #--> التأكد من وجود 7 أقسام و 5 نطاقات بالضبط
        errors.append(f"Taxonomy mismatch: categories={cats} (exp 7), scopes={scopes} (exp 5)")  #--> تسجيل خطأ التصنيف

    # 5. Referential integrity (orphan checks)
    orphan_queries = [  #--> استعلامات فحص تكامل العلاقات بين الجداول والتأكد من عدم وجود سجلات يتيمة
        ("Sales Items -> Invoices", "SELECT COUNT(*) FROM dbo.FactSalesItem si LEFT JOIN dbo.FactSalesInvoice s ON si.invoice_no = s.invoice_no WHERE s.invoice_no IS NULL;"),
        ("Sales Items -> Products", "SELECT COUNT(*) FROM dbo.FactSalesItem si LEFT JOIN dbo.DimProduct p ON si.item_code = p.item_code WHERE p.item_code IS NULL;"),
        ("Sales Invoices -> Accounts", "SELECT COUNT(*) FROM dbo.FactSalesInvoice s LEFT JOIN dbo.DimAccount a ON s.acct_no = a.acct_no WHERE s.acct_no IS NOT NULL AND a.acct_no IS NULL;"),
        ("Purchase Items -> Invoices", "SELECT COUNT(*) FROM dbo.FactPurchaseItem pi LEFT JOIN dbo.FactPurchaseInvoice p ON pi.invoice_no = p.invoice_no WHERE p.invoice_no IS NULL;"),
        ("Purchase Items -> Products", "SELECT COUNT(*) FROM dbo.FactPurchaseItem pi LEFT JOIN dbo.DimProduct pr ON pi.item_code = pr.item_code WHERE pr.item_code IS NULL;"),
        ("Purchase Invoices -> Accounts", "SELECT COUNT(*) FROM dbo.FactPurchaseInvoice p LEFT JOIN dbo.DimAccount a ON p.acct_no = a.acct_no WHERE p.acct_no IS NOT NULL AND a.acct_no IS NULL;"),
        ("Return Items -> Invoices", "SELECT COUNT(*) FROM dbo.FactSalesReturnItem ri LEFT JOIN dbo.FactSalesReturnInvoice r ON ri.return_invoice_no = r.return_invoice_no WHERE r.return_invoice_no IS NULL;"),
        ("Return Items -> Products", "SELECT COUNT(*) FROM dbo.FactSalesReturnItem ri LEFT JOIN dbo.DimProduct pr ON ri.item_code = pr.item_code WHERE pr.item_code IS NULL;"),
        ("Return Invoices -> Accounts", "SELECT COUNT(*) FROM dbo.FactSalesReturnInvoice r LEFT JOIN dbo.DimAccount a ON r.acct_no = a.acct_no WHERE r.acct_no IS NOT NULL AND a.acct_no IS NULL;"),
    ]
    for desc, query in orphan_queries:  #--> حلقة لتنفيذ كل فحص علاقات
        cursor.execute(query)  #--> execute() --> تنفيذ استعلام فحص السجلات اليتيمة
        if cursor.fetchone()[0] != 0:  #--> fetchone() --> لو طلع أي سجل ملوش أب يعتبر خطأ
            errors.append(f"Orphan records found: {desc}")  #--> تسجيل الخطأ

    # 6. Foreign keys status
    cursor.execute("SELECT name FROM sys.foreign_keys WHERE is_disabled = 1 OR is_not_trusted = 1;")  #--> execute() --> فحص حالة تفعيل وثقة المفاتيح الأجنبية
    bad_fks = cursor.fetchall()  #--> fetchall() --> استخراج أي مفتاح غير مفعل
    if bad_fks:  #--> شرط في حالة وجود مفاتيح معطلة
        errors.append(f"Disabled/untrusted foreign keys: {[f[0] for f in bad_fks]}")  #--> تسجيل أسماء المفاتيح المعطلة

    return errors  #--> بيرجع قائمة الأخطاء كاملة


# ------------------------------------------------------------------------------
# 5 MAIN EXECUTION
# ------------------------------------------------------------------------------
def main():  #--> الدالة الرئيسية لتشغيل السكربت بالكامل
    print("Cosmetics Store SQL Data Loader")  #--> print() --> بيطبع عنوان تشغيل البرنامج

    try:  #--> بيحاول يفتح الاتصال بقاعدة البيانات
        conn, cursor = get_connection()  #--> استدعاء دالة فتح الاتصال والمؤشر
    except pyodbc.Error as e:  #--> pyodbc.Error --> أي خطأ في الاتصال بـ SQL Server
        print(f"Connection failed: {e}")  #--> بيطبع سبب فشل الاتصال
        print("Set SQL_SERVER and SQL_DRIVER, see README")  #--> بيقول للمستخدم يراجع إعدادات السيرفر
        sys.exit(1)  #--> بيوقف البرنامج كحالة فشل

    try:  #--> تجربة تنفيذ التحميل مع حماية Transaction
        load_all_tables(cursor)  #--> استدعاء دالة تحميل كافة الجداول
        errors = run_validations(cursor)  #--> استدعاء دالة إجراء الفحوصات

        if errors:  #--> في حالة وجود أي خطأ أثناء المطابقة
            print("Validation FAILED:")  #--> print() --> بيطبع رسالة فشل التحقق
            for err in errors:  #--> حلقة لعرض كل خطأ ظهر
                print(f"* {err}")  #--> print() --> بيطبع تفاصيل الخطأ
            print("Rolling back all changes")  #--> print() --> بيطبع التراجع عن كل التغييرات
            conn.rollback()  #--> rollback() --> بيتراجع عن كل العمليات لحماية الداتابيز
            sys.exit(1)  #--> exit(1) --> بيوقف التنفيذ كحالة فشل

        print("All 6 validation checks PASSED! Committing transaction")  #--> print() --> بيطبع نجاح كافة الفحوصات والاعتماد
        conn.commit()  #--> commit() --> بيعتمد ويحفظ كل البيانات المدخلة في قاعدة البيانات
        print("ETL completed successfully")  #--> print() --> بيطبع رسالة إتمام العملية بنجاح

    except Exception as e:  #--> في حالة حدوث استثناء غير متوقع أثناء التشغيل
        print(f"ETL Error: {e}")  #--> print() --> بيطبع نوع ورسالة الخطأ
        conn.rollback()  #--> rollback() --> بيتراجع عن التغييرات لحماية البيانات
        sys.exit(1)  #--> exit(1) --> بيوقف البرنامج
    finally:  #--> كتلة التنفيذ الإلزامية في النهاية دائماً
        conn.close()  #--> close() --> بيقفل الاتصال بقاعدة البيانات

if __name__ == "__main__":
    main()  #--> تشغيل الدالة الرئيسية عند استدعاء الملف مباشرة
