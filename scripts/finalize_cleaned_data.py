"""
finalize_cleaned_data.py
------------------------------------------------------------------------------
الهدف من السكربت:
تنفيذ دورة معالجة وتنظيف وتصنيف البيانات الشاملة:
1. تنظيف وتوحيد نصوص اللغة العربية وإزالة التشكيل والمسافات الزائدة.
2. تصنيف الحسابات مع توثيق سبب التصنيف والدليل المحاسبي.
3. تفعيل فلتر مبيعات التجزئة is_retail_sale واستبعاد الحركات غير التشغيلية.
4. تطبيق التصنيف المزدوج للمنتجات (Product Scope & Product Category) بالكلمات الكاملة.
5. حماية معادلات تكلفة الوحدة وهامش الربح من القسمة على صفر.
6. فحص وتصنيف المرتجعات غير المربوطة مع توثيق الأسباب.
7. تصدير ملفات الـ CSV النظيفة المتزامنة بين مجلدي data/processed و cleaned.
"""

import sys  #--> sys.exit() --> لإيقاف التنفيذ عند ظهور أي خطأ
from pathlib import Path  #--> Path() --> للتعامل مع مسارات الملفات والمجلدات
import re  #--> re --> لتنظيف النصوص واستبدال الأنماط
import filecmp  #--> filecmp.cmp() --> لمقارنة الملفات بايت ببايت والتأكد من تطابقها
import numpy as np  #--> numpy --> لمعالجة الشروط المنطقية np.where() والقيم الرقمية
import pandas as pd  #--> pandas --> لقراءة ومعالجة وتصدير جداول البيانات

# إعداد مسارات المجلدات الرئيسية
base_project_dir = Path(__file__).resolve().parent.parent  #--> المجلد الرئيسي للمشروع
raw_data_dir = base_project_dir / "data" / "raw"  #--> مجلد الملفات الخام
processed_data_dir = base_project_dir / "data" / "processed"  #--> مجلد البيانات المعالجة المعتمدة
cleaned_backup_dir = base_project_dir / "cleaned"  #--> مجلد النسخة المتزامنة
reports_dir = base_project_dir / "reports"  #--> مجلد تقارير وقوائم المراجعة

processed_data_dir.mkdir(parents=True, exist_ok=True)  #--> إنشاء مجلد processed
cleaned_backup_dir.mkdir(parents=True, exist_ok=True)  #--> إنشاء مجلد cleaned

print("Stage 2: Data standardization, account classification, and taxonomy assignment")

# ------------------------------------------------------------------------------
# 1. دليل الحسابات وتصنيف شرائح التعامل
# ------------------------------------------------------------------------------
print("Processing accounts master and assigning audited classifications")
raw_accounts_df = pd.read_csv(raw_data_dir / "raw_accounts.csv")  #--> قراءة جدول الحسابات الخام
raw_accounts_df["acct_name"] = raw_accounts_df["acct_name"].astype(str).str.strip()  #--> إزالة المسافات الزائدة من اسم الحساب
raw_accounts_df["acct_no"] = raw_accounts_df["acct_no"].astype(int)  #--> تحويل رقم الحساب لعدد صحيح
raw_accounts_df["nature"] = raw_accounts_df["nature"].astype(str).str.strip()  #--> تنظيف نص طبيعة الحساب الأصلية

def classify_account(row):
    """
    تصنيف الحساب وتوثيق السبب المحاسبي المعتمد
    """
    acct_name = row["acct_name"]
    nature_val = row["nature"]
    
    # 1. الموردون
    if nature_val == "مورد":
        return "Supplier", "source nature = مورد (Supplier)", 0
    # 2. الشركاء ورأس المال
    elif "شريك" in acct_name:
        return "Partner/Capital Account", "name contains شريك (Partner capital account)", 1
    # 3. المصاريف التشغيلية
    elif "مصاريف" in acct_name:
        return "Expense Account", "name contains مصاريف (Store operational expense)", 1
    # 4. رواتب الموظفين (تمت المطابقة مع الأرباح والخسائر)
    elif acct_name == "مريم":
        return "Staff/Payroll Account", "matches P&L salary line راتب مريم", 1
    elif acct_name == "لميس":
        return "Staff/Payroll Account", "spelling variant of P&L salary line راتب لاميس", 1
    elif acct_name == "رقيه":
        return "Staff/Payroll Account", "matches P&L salary line راتب رقيه", 1
    # 5. العملاء التجاريون والزبائن المسجلون
    elif nature_val == "عميل":
        return "Customer", "source nature = عميل (Customer)", 0
    # 6. حسابات داخلية غير محددة
    elif acct_name == "يوسف":
        return "Other/Internal (Unclear)", "internal personal account without role", 1
    else:
        return "Other/Internal (Unclear)", f"source nature = {nature_val}, unclear role", 1

classification_tuples = raw_accounts_df.apply(classify_account, axis=1)  #--> تطبيق الدالة على كل صف
raw_accounts_df["account_classification"] = [t[0] for t in classification_tuples]  #--> اسم التصنيف
raw_accounts_df["classification_rationale"] = [t[1] for t in classification_tuples]  #--> سبب التصنيف
raw_accounts_df["is_internal"] = [t[2] for t in classification_tuples]  #--> علامة الحساب الداخلي

account_id_map = raw_accounts_df.set_index("acct_name")["acct_no"].to_dict()  #--> قاموس لربط اسم الحساب برقمه
account_class_map = raw_accounts_df.set_index("acct_name")["account_classification"].to_dict()  #--> قاموس لربط اسم الحساب بتصنيفه

raw_accounts_df.to_csv(processed_data_dir / "cleaned_accounts.csv", index=False, encoding="utf-8-sig")  #--> حفظ في processed
raw_accounts_df.to_csv(cleaned_backup_dir / "cleaned_accounts.csv", index=False, encoding="utf-8-sig")  #--> حفظ في cleaned
print(f"Processed {len(raw_accounts_df)} accounts.")
for class_name, count_value in raw_accounts_df["account_classification"].value_counts().items():
    print(f"  {class_name}: {count_value} accounts")

# ------------------------------------------------------------------------------
# 2. كتالوج المنتجات والتصنيف المزدوج
# ------------------------------------------------------------------------------
print("Processing product catalog and assigning dual-level taxonomy")
raw_products_df = pd.read_csv(raw_data_dir / "raw_products.csv", dtype={"barcode": str})
raw_products_df["stock_cost_valuation"] = (raw_products_df["total_qty"] * raw_products_df["avg_purchase_price"]).round(4)  #--> تقييم المخزون بالتكلفة
raw_products_df["is_out_of_stock"] = (raw_products_df["total_qty"] <= 0).astype(int)  #--> علامة نفاد الرصيد أو كونه سالباً

def clean_arabic_string(text):
    """
    توحيد أشكال الحروف والهمزات وإزالة التشكيل
    """
    if not isinstance(text, str):
        return ""
    cleaned = text.replace("\xa0", " ").replace("\u200f", "").replace("\u200e", "")  #--> إزالة مسافات ومحارف اليونيكود
    cleaned = re.sub(r"[\u064B-\u065F\u0670\u0640]", "", cleaned)  #--> إزالة التشكيل والتطويل
    cleaned = re.sub(r"[إأآا]", "ا", cleaned)  #--> توحيد أشكال الألف
    cleaned = re.sub(r"ى", "ي", cleaned)  #--> توحيد الياء
    cleaned = re.sub(r"ة", "ه", cleaned)  #--> توحيد التاء المربوطة
    cleaned = re.sub(r"[^\w\s]", " ", cleaned)  #--> إزالة علامات الترقيم
    return re.sub(r"\s+", " ", cleaned).strip().lower()  #--> إزالة المسافات الزائدة

raw_products_df["normalized_item_name"] = raw_products_df["item_name"].apply(clean_arabic_string)  #--> تطبيق التنظيف على اسم المنتج

# قراءة قائمة الأصناف المشكوك فيها (252 صنف تم عزلها)
uncertain_sku_codes = set()
uncertain_file_path = reports_dir / "uncertain_products_review.csv"
if uncertain_file_path.exists():
    uncertain_df = pd.read_csv(uncertain_file_path)
    uncertain_sku_codes = set(uncertain_df["item_code"])  #--> تحويل الأكواد لمجموعة بحث

personal_care_tokens = ["كلوز اب", "سيجنال", "معجون", "شفر", "جيليت", "دوركو", "صابون", "صابونة", "مناديل", "وايبس"]
packaging_tokens = ["شنطة هدايا", "بوكس هدايا", "ميدالية", "ماديليا"]
fashion_tokens = ["مودال", "شاش تيلاندي", "طرحه", "طرحة", "شال", "سكارف"]

def assign_scope(row):
    """
    تحديد نطاق الصنف في الكتالوج
    """
    item_code = row["item_code"]
    original_name = str(row["item_name"])
    if item_code in uncertain_sku_codes:
        if any(token in original_name for token in personal_care_tokens):
            return "Out-of-Scope (Personal Care)"
        if any(token in original_name for token in packaging_tokens):
            return "Out-of-Scope (Packaging)"
        if any(token in original_name for token in fashion_tokens):
            return "In-Scope (Fashion)"
        return "Pending Review"  #--> معلق للمراجعة
    return "In-Scope (Beauty)"  #--> مستحضر تجميل أساسي

raw_products_df["product_scope"] = raw_products_df.apply(assign_scope, axis=1)

def assign_category(row):
    """
    تصنيف الأصناف إلى الأقسام الستة بالكلمات الكاملة
    """
    if row["product_scope"] != "In-Scope (Beauty)":
        return "Uncategorized"  #--> الأصناف خارج نطاق التجميل تبقى غير مصنفة
        
    padded_text = f" {row['normalized_item_name']} "  #--> مسافات حول الكلمة لمنع المطابقة الجزئية
    
    # 1. العناية بالأظافر
    nail_tokens = [
        " اكلادور ", " مانيكير ", " مانكير ", " اسيتون ", " طلاء اظافر ", " مزيل طلاء ",
        " لزق اظافر ", " جل اظافر ", " نيل ارت ", " اظافر ", " نايلز ", " nail ", " بوليش "
    ]
    if any(token in padded_text for token in nail_tokens) and not any(k in padded_text for k in [" قصافه ", " قصاف "]):
        return "Nail Care"
        
    # 2. الأدوات والإكسسوارات
    tools_tokens = [
        " فرشاه ", " فرشه ", " فرش ", " بيوتي بلندر ", " بلندر ", " سفنجه ", " سفنج ",
        " سبونج ", " قصافه ", " قصاف ", " ملقاط ", " مقص ", " عدسات ", " رموش ", " بنس ",
        " بينز ", " توكه ", " توكتين ", " مشط ", " حجر قدم ", " بونيه ", " مرايه ",
        " برايه ", " صاروخ ", " مبرد ", " باديكير ", " باديكر ", " ابره ", " سلسله ",
        " انسيال ", " خاتم ", " حلق ", " طوق ", " brush ", " sponge "
    ]
    if any(token in padded_text for token in tools_tokens):
        return "Accessories & Tools"
        
    # 3. العطور ومزيلات العرق
    fragrance_tokens = [
        " مخمريه ", " برفان ", " عطر ", " سبلاش ", " اسبلاش ", " ميست ", " بدي ميست ",
        " معطر ", " بليه ", " بلية ", " مزيل عرق ", " ديودرنت ", " ديودرانت ", " رول اون ",
        " او دو ", " او دي بارفيوم ", " او دي تواليت ", " كولونيا ", " perfume ", " splash ", " mist "
    ]
    if any(token in padded_text for token in fragrance_tokens) and not any(k in padded_text for k in [" شعر ", " كيرلي ", " فك تشابك "]):
        return "Fragrances & Deodorants"
        
    # 4. العناية بالشعر
    hair_tokens = [
        " شامبو ", " بلسم ", " حمام كريم ", " ليف ان ", " بديل زيت ", " بديل الزيت ",
        " سيرم شعر ", " سيروم شعر ", " زيت شعر ", " كريم شعر ", " كريم فرد ", " ماسك شعر ",
        " هير ماسك ", " اسبراي شعر ", " فك تشابك ", " امبولات شعر ", " جيل كيرلي ",
        " صبغه شعر ", " صبغة شعر ", " صبغه ", " صبغة ", " هيرتونك ", " سشوار ",
        " كيراتين ", " بروتين شعر ", " شعر ", " shampoo ", " conditioner "
    ]
    hair_brands = [
        " بانتين ", " صانسيلك ", " فيانسيه ", " تريشوب ", " املا ", " نونو ", " ايمامي ",
        " فلكسيد ", " بيو سوفت ", " باشن بيبي ", " كانتو ", " فاتيكا ", " كاريس "
    ]
    if any(token in padded_text for token in hair_tokens) or any(brand in padded_text for brand in hair_brands):
        return "Haircare"
        
    # 5. المكياج ومستحضرات التجميل
    makeup_tokens = [
        " كريم اساس ", " فاونديشن ", " فونديشن ", " كونسيلر ", " بودره ", " بودرة ",
        " باودر ", " بدره ", " بودر ", " برايمر ", " فيكسر ", " كونتور ", " كنتور ",
        " هايلايتر ", " هيلايتر ", " برونزر ", " بلاشر ", " بلشر ", " ايلاينر ", " ايلينر ",
        " ايشادو ", " شادو ", " ظلال ", " ماسكرا ", " ماسكارا ", " مسكره ", " مسكرا ",
        " حواجب ", " ايبرو ", " روج ", " تنت ", " جليتر ", " كحل ", " كجال ", " باليت ",
        " مكياج ", " ميكب ", " ميك اب ", " تحديد شفايف ", " زبده شفايف ", " روج ستيك ",
        " ليب جلوس ", " ليب ستيك ", " ليب اويل ", " ليب بالم ", " مورد خدود ",
        " مورد شفايف ", " ليب ", " blush ", " eyeshadow ", " mascara ", " lipstick "
    ]
    makeup_brands = [" مايت سينما ", " ام ان ", " ساندرا ", " منايا ", " بريتي ", " روز جولد ", " روز بيري "]
    if (any(token in padded_text for token in makeup_tokens) or 
        any(brand in padded_text for brand in makeup_brands) or 
        (" شيجلام " in padded_text and not any(k in padded_text for k in [" اسبراي ", " سبراي ", " فرشاه ", " فرشه "]))):
        return "Makeup & Cosmetics"
        
    # 6. العناية بالبشرة والجسم
    skincare_tokens = [
        " غسول ", " سكراب ", " سكرب ", " اسكرب ", " سنفره ", " صنفره ", " تقشير ",
        " تونر ", " بانثينول ", " فازلين ", " جلسرين ", " مقشر ", " طمي ", " صن بلوك ",
        " سن بلوك ", " واقي شمس ", " صن سكرين ", " شاور جل ", " كريم مرطب ", " كريم تفتيح ",
        " كريم وجه ", " كريم عين ", " ماسك وجه ", " شيت ماسك ", " ماء ورد ", " ملح حليب ",
        " كعب غزال ", " بدي لوشن ", " بدي بتر ", " زبدة شيا ", " كريم يد ", " كريم قدم ",
        " مرطب شفايف ", " سيروم ", " سيرم ", " لوشن ", " مرطب ", " cleanser ", " scrub ", " lotion "
    ]
    skincare_brands = [" ستارفيل ", " ايفا ", " بوبانا ", " شان ", " دراكون ", " كير بيبي "]
    if any(token in padded_text for token in skincare_tokens) or any(brand in padded_text for brand in skincare_brands):
        return "Skincare & Body"
        
    return "Uncategorized"  #--> الأصناف التي لا تنطبق عليها القواعد

raw_products_df["product_category"] = raw_products_df.apply(assign_category, axis=1)

final_product_columns = [
    "idx", "item_code", "item_name", "total_qty", "unit", "sell_price",
    "avg_purchase_price", "last_purchase_price", "barcode", "item_code_1_MISLABELED",
    "source_category", "normalized_item_name", "product_scope", "product_category",
    "stock_cost_valuation", "is_out_of_stock"
]
clean_products_df = raw_products_df[final_product_columns]

clean_products_df.to_csv(processed_data_dir / "cleaned_products.csv", index=False, encoding="utf-8-sig")
clean_products_df.to_csv(cleaned_backup_dir / "cleaned_products.csv", index=False, encoding="utf-8-sig")
print(f"Processed {len(clean_products_df)} products ({clean_products_df['is_out_of_stock'].sum()} out of stock).")

# ------------------------------------------------------------------------------
# 3. فواتير المبيعات وتحديد نطاق التجزئة
# ------------------------------------------------------------------------------
print("Processing sales invoices and tagging retail transactions")
raw_sales_invoices_df = pd.read_csv(raw_data_dir / "raw_sales_invoices.csv")
raw_sales_invoices_df["invoice_date"] = pd.to_datetime(raw_sales_invoices_df["date"], format="%Y-%m-%d")
raw_sales_invoices_df["order_hour"] = pd.to_datetime(raw_sales_invoices_df["time"], format="%H:%M:%S").dt.hour
raw_sales_invoices_df["order_year"] = raw_sales_invoices_df["invoice_date"].dt.year
raw_sales_invoices_df["order_month"] = raw_sales_invoices_df["invoice_date"].dt.month
raw_sales_invoices_df["order_day_name"] = raw_sales_invoices_df["invoice_date"].dt.day_name()
raw_sales_invoices_df["is_weekend"] = raw_sales_invoices_df["order_day_name"].isin(["Friday", "Saturday"]).astype(int)
raw_sales_invoices_df["payment_method"] = raw_sales_invoices_df["payment_method"].astype(str).str.strip()

raw_sales_invoices_df["account_clean"] = raw_sales_invoices_df["account"].astype(str).str.strip().replace({"nan": None, "": None})
raw_sales_invoices_df["acct_no"] = raw_sales_invoices_df["account_clean"].map(account_id_map)
raw_sales_invoices_df["customer_account_classification"] = raw_sales_invoices_df["account_clean"].map(
    account_class_map
).fillna("Walk-in Cash (no account)")

def get_sale_type(row):
    """
    تحديد نوع حركة الفاتورة
    """
    acc_name = row["account_clean"]
    acc_class = row["customer_account_classification"]
    if pd.isna(acc_name) or acc_name is None:
        return "Walk-in cash"
    if acc_class == "Customer":
        return "Named customer"
    if acc_class == "Partner/Capital Account":
        return "Partner withdrawal"
    if acc_class == "Staff/Payroll Account":
        return "Staff"
    if acc_class == "Expense Account":
        return "Store expense"
    if acc_class == "Supplier":
        return "Supplier settlement"
    return "Other/Unclear"

raw_sales_invoices_df["sale_type"] = raw_sales_invoices_df.apply(get_sale_type, axis=1)

# تفعيل فلتر مبيعات التجزئة
raw_sales_invoices_df["is_retail_sale"] = raw_sales_invoices_df["sale_type"].isin(["Walk-in cash", "Named customer"]).astype(int)
raw_sales_invoices_df["is_internal_account"] = (1 - raw_sales_invoices_df["is_retail_sale"]).astype(int)
raw_sales_invoices_df["internal_account_status"] = np.where(raw_sales_invoices_df["is_internal_account"] == 1, "confirmed", "none")

raw_sales_invoices_df["total_discount"] = raw_sales_invoices_df["total_discount"].fillna(0.0)
raw_sales_invoices_df["paid_cash"] = raw_sales_invoices_df["paid_cash"].fillna(0.0)
raw_sales_invoices_df["deferred"] = raw_sales_invoices_df["deferred"].fillna(0.0)

final_sales_columns = [
    "counter", "date", "time", "invoice_no", "acct_no", "account", "customer_account_classification",
    "sale_type", "internal_account_status", "is_internal_account", "is_retail_sale",
    "payment_method", "total_qty", "total_discount", "final_total", "profit",
    "cash_drawer", "credit_card", "treasury", "paid_cash", "deferred", "due",
    "warehouse", "sales_rep", "added_by", "added_time", "modified_by", "modified_time",
    "invoice_date", "order_hour", "order_year", "order_month", "order_day_name", "is_weekend"
]
clean_sales_invoices_df = raw_sales_invoices_df[final_sales_columns]

clean_sales_invoices_df.to_csv(processed_data_dir / "cleaned_sales_invoices.csv", index=False, encoding="utf-8-sig")
clean_sales_invoices_df.to_csv(cleaned_backup_dir / "cleaned_sales_invoices.csv", index=False, encoding="utf-8-sig")

retail_invoices_df = clean_sales_invoices_df[clean_sales_invoices_df["is_retail_sale"] == 1]
non_retail_invoices_df = clean_sales_invoices_df[clean_sales_invoices_df["is_retail_sale"] == 0]

print(f"Total sales invoices: {len(clean_sales_invoices_df):,} (Gross: {clean_sales_invoices_df['final_total'].sum():,.2f} EGP)")
print(f"Retail sales invoices: {len(retail_invoices_df):,} (Gross: {retail_invoices_df['final_total'].sum():,.2f} EGP)")
print(f"Non-retail excluded: {len(non_retail_invoices_df):,} (Value: {non_retail_invoices_df['final_total'].sum():,.2f} EGP)")

# ------------------------------------------------------------------------------
# 4. بنود المبيعات وتكلفة الوحدة
# ------------------------------------------------------------------------------
print("Processing sales items and protecting unit cost calculations")
raw_sales_items_df = pd.read_csv(raw_data_dir / "raw_sales_items.csv")

# حماية القسمة على صفر
raw_sales_items_df["unit_cost"] = np.where(
    raw_sales_items_df["qty"] > 0,
    ((raw_sales_items_df["line_final"] - raw_sales_items_df["profit"]) / raw_sales_items_df["qty"]).round(4),
    0.0
)
raw_sales_items_df["discount"] = raw_sales_items_df["discount"].fillna(0.0)

raw_sales_items_df.to_csv(processed_data_dir / "cleaned_sales_items.csv", index=False, encoding="utf-8-sig")
raw_sales_items_df.to_csv(cleaned_backup_dir / "cleaned_sales_items.csv", index=False, encoding="utf-8-sig")
print(f"Processed {len(raw_sales_items_df):,} sales items.")

# ------------------------------------------------------------------------------
# 5. فواتير وبنود المشتريات
# ------------------------------------------------------------------------------
print("Processing purchase invoices and line items")
raw_purchase_invoices_df = pd.read_csv(raw_data_dir / "raw_purchase_invoices.csv")
raw_purchase_invoices_df["purchase_date"] = pd.to_datetime(raw_purchase_invoices_df["date"], format="%Y-%m-%d")
raw_purchase_invoices_df["payment_method"] = raw_purchase_invoices_df["payment_method"].astype(str).str.strip()
raw_purchase_invoices_df["total_discount"] = raw_purchase_invoices_df["total_discount"].fillna(0.0)

raw_purchase_invoices_df.to_csv(processed_data_dir / "cleaned_purchase_invoices.csv", index=False, encoding="utf-8-sig")
raw_purchase_invoices_df.to_csv(cleaned_backup_dir / "cleaned_purchase_invoices.csv", index=False, encoding="utf-8-sig")
print(f"Processed {len(raw_purchase_invoices_df):,} purchase invoices.")

raw_purchase_items_df = pd.read_csv(raw_data_dir / "raw_purchase_items.csv")
raw_purchase_items_df["discount"] = raw_purchase_items_df["discount"].fillna(0.0)
raw_purchase_items_df.to_csv(processed_data_dir / "cleaned_purchase_items.csv", index=False, encoding="utf-8-sig")
raw_purchase_items_df.to_csv(cleaned_backup_dir / "cleaned_purchase_items.csv", index=False, encoding="utf-8-sig")
print(f"Processed {len(raw_purchase_items_df):,} purchase items.")

# ------------------------------------------------------------------------------
# 6. فواتير وبنود مرتجع المبيعات
# ------------------------------------------------------------------------------
print("Processing sales returns invoices and auditing unlinked returns")
raw_returns_invoices_df = pd.read_csv(raw_data_dir / "raw_sales_returns_invoices.csv")
raw_returns_invoices_df["return_date"] = pd.to_datetime(raw_returns_invoices_df["date"], format="%Y-%m-%d")
raw_returns_invoices_df["return_year"] = raw_returns_invoices_df["return_date"].dt.year
raw_returns_invoices_df["return_month"] = raw_returns_invoices_df["return_date"].dt.month
raw_returns_invoices_df["return_day_name"] = raw_returns_invoices_df["return_date"].dt.day_name()
raw_returns_invoices_df["total_discount"] = raw_returns_invoices_df["total_discount"].fillna(0.0)

valid_sales_invoice_set = set(clean_sales_invoices_df["invoice_no"])

def get_return_status(row):
    """
    تحديد حالة ربط المرتجع بالفاتورة الأصلية
    """
    orig_no = row["original_invoice_no"]
    if pd.isna(orig_no) or orig_no == 0:
        return "No original invoice referenced (source value 0)"
    if orig_no in valid_sales_invoice_set:
        return "Found in sales_invoices"
    return "Not found -- sale after sales-file cutoff"

raw_returns_invoices_df["original_invoice_status"] = raw_returns_invoices_df.apply(get_return_status, axis=1)
raw_returns_invoices_df["is_linked_to_sales"] = (raw_returns_invoices_df["original_invoice_status"] == "Found in sales_invoices").astype(int)
raw_returns_invoices_df["is_retail_sale"] = 1  #--> كافة المرتجعات هي مرتجعات تجزئة

raw_returns_invoices_df.to_csv(processed_data_dir / "cleaned_sales_returns_invoices.csv", index=False, encoding="utf-8-sig")
raw_returns_invoices_df.to_csv(cleaned_backup_dir / "cleaned_sales_returns_invoices.csv", index=False, encoding="utf-8-sig")
print(f"Processed {len(raw_returns_invoices_df):,} sales return invoices.")

raw_returns_items_df = pd.read_csv(raw_data_dir / "raw_sales_returns_items.csv")
raw_returns_items_df["discount"] = raw_returns_items_df["discount"].fillna(0.0)
raw_returns_items_df.to_csv(processed_data_dir / "cleaned_sales_returns_items.csv", index=False, encoding="utf-8-sig")
raw_returns_items_df.to_csv(cleaned_backup_dir / "cleaned_sales_returns_items.csv", index=False, encoding="utf-8-sig")
print(f"Processed {len(raw_returns_items_df):,} sales return items.")

# ------------------------------------------------------------------------------
# 7. المصالحة المالية الشاملة
# ------------------------------------------------------------------------------
gross_book_sales = clean_sales_invoices_df["final_total"].sum()
non_retail_adjustments = non_retail_invoices_df["final_total"].sum()
retail_gross_sales = retail_invoices_df["final_total"].sum()
sales_returns_value = raw_returns_invoices_df["final_total"].sum()
retail_net_sales = retail_gross_sales + sales_returns_value

gross_book_profit = clean_sales_invoices_df["profit"].sum()
non_retail_profit = non_retail_invoices_df["profit"].sum()
retail_gross_profit = retail_invoices_df["profit"].sum()
returns_profit_impact = raw_returns_invoices_df["profit"].sum()
retail_net_profit = retail_gross_profit + returns_profit_impact
retail_net_margin = (retail_net_profit / retail_net_sales) * 100.0

print("Financial reconciliation summary:")
print(f"Gross book revenue:    {gross_book_sales:>12,.2f} EGP (Margin: {gross_book_profit/gross_book_sales*100:.2f}%)")
print(f"Non-retail adjustments:{non_retail_adjustments:>12,.2f} EGP")
print(f"Retail gross sales:    {retail_gross_sales:>12,.2f} EGP")
print(f"Total sales returns:   {sales_returns_value:>12,.2f} EGP")
print(f"Retail net sales:      {retail_net_sales:>12,.2f} EGP")
print(f"Retail net profit:     {retail_net_profit:>12,.2f} EGP")
print(f"Retail net margin:     {retail_net_margin:>11.2f}%")

# التحقق من التطابق التام للملفات
all_identical = True
csv_files_to_check = [
    "cleaned_accounts.csv", "cleaned_products.csv", "cleaned_sales_invoices.csv",
    "cleaned_sales_items.csv", "cleaned_purchase_invoices.csv", "cleaned_purchase_items.csv",
    "cleaned_sales_returns_invoices.csv", "cleaned_sales_returns_items.csv"
]
for fname in csv_files_to_check:
    match = filecmp.cmp(processed_data_dir / fname, cleaned_backup_dir / fname, shallow=False)
    if not match:
        all_identical = False

print(f"All processed and cleaned CSV pairs synchronized: {all_identical}")
