import sys  #--> sys.exit() --> لإيقاف تشغيل البرنامج عند حدوث خطأ جسيم
from pathlib import Path  #--> Path() --> للتعامل مع مسارات الملفات والمجلدات بطريقة مرنة
import numpy as np  #--> numpy --> للعمليات الحسابية ومقارنة الأرقام التقريبية
import pandas as pd  #--> pandas --> لقراءة ومعالجة جداول البيانات DataFrames
from parse_utils import parse_transactions, parse_goods, parse_accounts, parse_returns  #--> دوال التحليل المخصصة

# إعداد المسارات والمتغيرات العامة
base_project_dir = Path(__file__).resolve().parent.parent  #--> المسار الجذري للمشروع
source_excel_dir = base_project_dir.parent / "glossy for her"  #--> مسار مجلد ملفات الإكسيل الأصلية
target_raw_csv_dir = base_project_dir / "data" / "raw"  #--> مسار مجلد تصدير ملفات الـ CSV الخام

target_raw_csv_dir.mkdir(parents=True, exist_ok=True)  #--> إنشاء المجلد تلقائياً في حال عدم وجوده

# قائمة الأعمدة التي يجب تحويلها لأرقام صحيحة Int64 لتجنب ظهور الكسور العشرية
integer_columns_set = {
    "idx", "acct_no", "item_code", "invoice_no", "original_invoice_no",
    "return_invoice_no", "row_index", "counter", "invoice_row_index", "acct_code"
}

# قائمة الأعمدة النصية الحساسة للحفاظ على أصفار البداية وعدم تغييرها
text_columns_set = {"barcode", "mobile", "acct_code"}


def sanitize_dataframe_for_sql(input_df: pd.DataFrame) -> pd.DataFrame:
    """
    تنظيف أنواع البيانات وإزالة الكسور العشرية الخاطئة من الباركود والأرقام الصحيحة
    """
    clean_df = input_df.copy()  #--> أخذ نسخة مستقلة لعدم التأثير على الجدول الأصلي
    for col_name in clean_df.columns:
        if col_name in text_columns_set:
            #--> تحويل النص إلى String وإزالة أي .0 تظهر بالخطأ في الباركود
            clean_df[col_name] = (
                clean_df[col_name]
                .astype("string")
                .str.replace(r"\.0$", "", regex=True)
            )
        elif col_name in integer_columns_set:
            #--> تحويل الأرقام إلى Int64 بأمان
            clean_df[col_name] = pd.to_numeric(
                clean_df[col_name], errors="coerce"
            ).astype("Int64")
    return clean_df


def run_extraction_pipeline():
    print("Step 1: Extracting raw POS Excel workbooks to flat CSV files")
    print(f"Source directory: {source_excel_dir}")
    print(f"Target directory: {target_raw_csv_dir}")

    # 1. استخراج فواتير وبنود المبيعات
    sales_excel_file = source_excel_dir / "بيع.xlsx"
    print(f"Parsing {sales_excel_file.name} (Sales invoices)")
    sales_invoices_df, sales_items_df, sales_grand_total, sales_diagnostics = parse_transactions(
        str(sales_excel_file), "sale"
    )
    #--> التأكد من تفكيك كافة الفواتير بدون صفوف مهملة أو فروق في المجاميع
    assert not sales_diagnostics["unparsed_rows"], f"Unparsed sales rows: {sales_diagnostics['unparsed_rows']}"
    assert not sales_diagnostics["summary_mismatches"], f"Sales summary mismatches: {sales_diagnostics['summary_mismatches']}"
    print(f"Extracted {len(sales_invoices_df):,} sales invoices and {len(sales_items_df):,} sales item rows.")
    print(f"Sales gross revenue: {sales_invoices_df['final_total'].sum():,.2f} EGP")

    # 2. استخراج فواتير وبنود المشتريات
    purchase_excel_file = source_excel_dir / "شراء.xlsx"
    print(f"Parsing {purchase_excel_file.name} (Purchase invoices)")
    purchase_invoices_df, purchase_items_df, purchase_grand_total, purchase_diagnostics = parse_transactions(
        str(purchase_excel_file), "purchase"
    )
    assert not purchase_diagnostics["unparsed_rows"], f"Unparsed purchase rows: {purchase_diagnostics['unparsed_rows']}"
    assert not purchase_diagnostics["summary_mismatches"], f"Purchase summary mismatches: {purchase_diagnostics['summary_mismatches']}"
    print(f"Extracted {len(purchase_invoices_df):,} purchase invoices and {len(purchase_items_df):,} purchase item rows.")
    print(f"Purchases total cost: {purchase_invoices_df['final_total'].sum():,.2f} EGP")

    # 3. استخراج فواتير وبنود مرتجع المبيعات
    returns_excel_file = (
        source_excel_dir / "مرتجع بيع.xlsx"
        if (source_excel_dir / "مرتجع بيع.xlsx").exists()
        else source_excel_dir / "مرتجع_بيع.xlsx"
    )
    print(f"Parsing {returns_excel_file.name} (Sales returns)")
    returns_invoices_df, returns_items_df, returns_grand_total, returns_diagnostics = parse_returns(
        str(returns_excel_file)
    )
    assert not returns_diagnostics["unparsed_rows"], f"Unparsed return rows: {returns_diagnostics['unparsed_rows']}"
    assert not returns_diagnostics["summary_mismatches"], f"Return summary mismatches: {returns_diagnostics['summary_mismatches']}"
    print(f"Extracted {len(returns_invoices_df):,} return invoices and {len(returns_items_df):,} return item rows")
    print(f"Returns total value: {returns_invoices_df['final_total'].sum():,.2f} EGP")

    # 4. استخراج جدول كتالوج الأصناف الرئيسي
    products_excel_file = source_excel_dir / "البضاعه.xlsx"
    print(f"Parsing {products_excel_file.name} (Product catalog)")
    products_master_df = parse_goods(str(products_excel_file))
    print(f"Extracted {len(products_master_df):,} products from catalog")

    # 5. استخراج دليل الحسابات
    accounts_excel_file = source_excel_dir / "الحسابات.xlsx"
    print(f"Parsing {accounts_excel_file.name} (Accounts master)")
    accounts_master_df = parse_accounts(str(accounts_excel_file))
    print(f"Extracted {len(accounts_master_df):,} accounts from ledger")

    # تصدير الجداول إلى ملفات CSV
    tables_to_export = {
        "raw_sales_invoices.csv": sales_invoices_df,
        "raw_sales_items.csv": sales_items_df,
        "raw_purchase_invoices.csv": purchase_invoices_df,
        "raw_purchase_items.csv": purchase_items_df,
        "raw_sales_returns_invoices.csv": returns_invoices_df,
        "raw_sales_returns_items.csv": returns_items_df,
        "raw_products.csv": products_master_df,
        "raw_accounts.csv": accounts_master_df,
    }

    print("Saving CSV files to target directory")
    for filename, df_table in tables_to_export.items():
        sanitized_table = sanitize_dataframe_for_sql(df_table)  #--> تنظيف أنواع الأعمدة قبل التصدير
        target_filepath = target_raw_csv_dir / filename
        sanitized_table.to_csv(target_filepath, index=False, encoding="utf-8-sig")  #--> حفظ الملف بترميز UTF-8-SIG
        print(f"Saved {filename} ({len(sanitized_table):,} rows)")

    print("Extraction completed successfully with all assertions passed")


if __name__ == "__main__":
    run_extraction_pipeline()  #--> بدء تشغيل السكربت
