import pandas as pd
import numpy as np
import re # --> للتعامل مع النصوص والبحث فيها واستبدال أجزاء منه
from pathlib import Path #--> للتعامل مع مسارات الملفات والفولدرات 
import filecmp  # --> لمقارنة الملفات ومعرفة هل ملفان متطابقان أم لا

base_dir = Path(__file__).resolve().parent.parent
raw_dir = base_dir / "data" / "raw"
proc_dir = base_dir / "data" / "processed"
clean_dir = base_dir / "cleaned"
rep_dir = base_dir / "reports"

proc_dir.mkdir(parents=True , exist_ok=True)#--> إنشاء الفولدرات
clean_dir.mkdir(parents=True, exist_ok=True)

print("STAGE 1 DATA PIPELINE STANDARDIZATION & TAXONOMY GENERATOR")
# ------------------------------------------------------------------------------
# 1 ACCOUNTS MASTER
# ------------------------------------------------------------------------------
print("\n Processing Accounts Master")
accounts = pd.read_csv(raw_dir / "raw_accounts.csv")#--> بنقرأ ملف raw_accounts.csv من فولدر raw
accounts['acct_name'] = accounts['acct_name'].astype(str).str.strip()  #  astype(str) --> بيحوّل القيم لنوع String , str.strip()--> بتحذف المسافات الزائدة من بداية ونهاية النص
accounts['acct_no'] = accounts['acct_no'].astype(int) 

# Mapping dictionary for sales invoices
acc_map = accounts.set_index('acct_name')['acct_no'].to_dict() #--> بنحدد عمود acct_name ليكون Index للجدول, to_dict--> بنحوّل البيانات إلى Dictionary

accounts.to_csv(proc_dir / "cleaned_accounts.csv", index=False, encoding="utf-8-sig")
accounts.to_csv(clean_dir / "cleaned_accounts.csv", index=False, encoding="utf-8-sig")
print(f" Processed {len(accounts)} accounts")

# ------------------------------------------------------------------------------
# 2 PRODUCTS MASTER (Dual-Level Taxonomy: Scope & Category)
# ------------------------------------------------------------------------------
print("\n Processing Products Master (product_scope & product_category)")
products = pd.read_csv(raw_dir / "raw_products.csv", dtype={"barcode": str}) #--> بنحدد نوع البيانات للعمود barcode إنه String
products['stock_cost_valuation'] = (products['total_qty'] * products['avg_purchase_price']).round(4) #--> بنضيف عمود جديد اسمه: stock_cost_valuation 

# Text normalization helper
def norm(text):
    if not isinstance(text, str): return '' #--> لتأكد إن القيمة نص, isinstance() بتختبر نوع البيانات
    text = text.replace('\xa0', ' ').replace('\u200f', '').replace('\u200e', '') #--> إزالة المسافات, \u200f --> علامة اتجاه النص من اليمين لليسار, \u200e -->علامة اتجاه النص من اليسار لليمين  
    text = re.sub(r'[\u064B-\u065F\u0670\u0640]', '', text) #-->إزالة التشكيل 
    text = re.sub(r'[إأآا]', 'ا', text)#--> توحيد أشكال الألف
    text = re.sub(r'ى', 'ي', text)#--> توحيد الياء
    text = re.sub(r'ة', 'ه', text)#-->توحيد التاء المربوطة والهاء
    text = re.sub(r'[^\w\s]', ' ', text)#--> مسح علامات الترقيم والرموز
    return re.sub(r'\s+', ' ', text).strip().lower() #--> إزالة المسافات الزائدة وتحويل الحروف إلى Lowercase

products['normalized_item_name'] = products['item_name'].apply(norm) #--> تطبيق دالة Normalization على المنتجات

# Load uncertain segregated set (252 SKUs)
uncert = pd.read_csv(rep_dir / "uncertain_products_review.csv")
uncert_codes = set(uncert['item_code'])#--> بنحول عمود item_code إلى Set

personal_care_tokens = ['كلوز اب', 'سيجنال', 'معجون', 'شفر', 'جيليت', 'دوركو', 'صابون', 'صابونة', 'مناديل', 'وايبس']
pkg_tokens = ['شنطة هدايا', 'بوكس هدايا', 'ميدالية', 'ماديليا']
fashion_tokens = ['مودال', 'شاش تيلاندي']

def assign_product_scope(row):
    item_code = row['item_code']#--> بنجيب كود المنتج من الصف الحالي
    if item_code in uncert_codes: #--> هل المنتج موجود ضمن الـ 252 منتج اللي محتاجين مراجعة
        n = str(row['item_name'])
        if any(k in n for k in personal_care_tokens):
            return 'Out-of-Scope (Personal Care)'
        if any(k in n for k in pkg_tokens):
            return 'Out-of-Scope (Packaging)'
        if any(k in n for k in fashion_tokens):
            return 'In-Scope (Fashion)'
        return 'Pending Review' #--> المنتجات غير المحسومة
    return 'In-Scope (Beauty)'

products['product_scope'] = products.apply(assign_product_scope, axis=1) #-->axis=1 معناها إن العملية بتتم على مستوى الصفوف
# Categorization rules for the 6 Beauty Departments
def assign_product_category(row): 
    # Items that are Out-of-Scope or Pending Review remain Uncategorized
    if row['product_scope'] != 'In-Scope (Beauty)': #--> أول حاجة بنعملها هي التأكد إن المنتج داخل نطاق Beauty
        return 'Uncategorized' #-->  المنتج خارج النطاق
        
    t = row['normalized_item_name'] # -->  اسم المنتج بعد الـ Normalization
    
    # Priority 1: Nail Care
    nail_tokens = [
        'اكلادور', 'مانيكير', 'مانكير', 'اسيتون', 'طلاء اظافر', 'مزيل طلاء',
        'لزق اظافر', 'جل اظافر', 'نيل ارت', 'اظافر', 'نايلز', 'nail', 'بوليش'
    ]
    if any(k in t for k in nail_tokens) and not any(k in t for k in ['قصافه', 'قصاف']):
        return 'Nail Care'
        
    # Priority 2: Tools & Accessories
    tool_tokens = [  
        'فرشاه', 'فرشه', 'فرش', 'بيوتي بلندر', 'بلندر', 'سفنجه', 'سفنج', 'سفينجه', 'سبونج',
        'قصافه', 'قصاف', 'ملقاط', 'مقص', 'عدسات', 'رموش', 'بنس', 'بينز', 'توكه', 'توكتين',
        'مشط', 'حجر قدم', 'بونيه', 'مرايه', 'برايه', 'صاروخ', 'مبرد', 'باديكير', 'باديكر',
        'ابره', 'سلسله', 'انسيال', 'خاتم', 'حلق', 'شارمز', 'طوق', 'brush', 'sponge'
    ]
    if any(k in t for k in tool_tokens): #--> هنا بنبحث عن أسماء الأدوات والإكسسوارات
        return 'Accessories & Tools'
        
    # Priority 3: Fragrances & Deodorants
    frag_tokens = [
        'مخمريه', 'برفان', 'عطر', 'سبلاش', 'اسبلاش', 'ميست', 'بدي ميست', 'معطر', 'بليه', 'بلية',
        'مزيل عرق', 'ديودرنت', 'ديودرانت', 'رول اون', 'او دو', 'او دي بارفيوم', 'او دي تواليت', 'كولونيا',
        'perfume', 'splash', 'mist', 'deodorant'
    ]
    if any(k in t for k in frag_tokens) and not any(k in t for k in ['شعر', 'كيرلي', 'فك تشابك', 'هيرتونك']):
        return 'Fragrances & Deodorants'
        
    # Priority 4: Haircare
    hair_tokens = [
        'شامبو', 'بلسم', 'حمام كريم', 'ليف ان', 'بديل زيت', 'بديل الزيت', 'سيرم شعر', 'سيروم شعر',
        'زيت شعر', 'كريم شعر', 'كريم فرد', 'ماسك شعر', 'هير ماسك', 'اسبراي شعر', 'فك تشابك',
        'امبولات شعر', 'جيل كيرلي', 'صبغه شعر', 'صبغة شعر', 'صبغه', 'صبغة', 'هيرتونك', 'سشوار', 'مكواة شعر',
        'كيراتين', 'بروتين شعر', 'شعر', 'shampoo', 'conditioner'
    ]
    hair_brands = [
        'بانتين', 'صانسيلك', 'فيانسيه', 'تريشوب', 'املا', 'نونو', 'ايمامي', 'فلكسيد', 'بيو سوفت', 'باشن بيبي', 'كانتو', 'فاتيكا', 'كاريس'
    ]
    if any(k in t for k in hair_tokens) or any(k in t for k in hair_brands):
        return 'Haircare'
        
    # Priority 5: Makeup & Cosmetics
    makeup_tokens = [
        'كريم اساس', 'فاونديشن', 'فونديشن', 'كونسيلر', 'بودره', 'بودرة', 'باودر', 'بدره', 'بودر',
        'برايمر', 'فيكسر', 'كونتور', 'كنتور', 'هايلايتر', 'هيلايتر', 'هيليتر', 'برونزر', 'بلاشر', 'بلشر',
        'ايلاينر', 'ايلينر', 'ايشادو', 'شادو', 'ظلال', 'ماسكرا', 'ماسكارا', 'مسكره', 'مسكرا', 'حواجب',
        'ايبرو', 'روج', 'تنت', 'جليتر', 'كحل', 'كجال', 'باليت', 'مكياج', 'ميكب', 'ميك اب', 'تحديد شفايف',
        'زبده شفايف', 'روج ستيك', 'ليب جلوس', 'ليب ستيك', 'ليب اويل', 'ليب بالم', 'مورد خدود', 'مورد شفايف',
        'ليب', 'blush', 'eyeshadow', 'mascara', 'foundation', 'highlighter', 'bronzer', 'contour', 'lipstick'
    ]
    makeup_brands = [
        'مايت سينما', 'ام ان', 'ساندرا', 'منايا', 'بريتي', 'روز جولد', 'روز بيري'
    ]
    if any(k in t for k in makeup_tokens) or any(k in t for k in makeup_brands) or ('شيجلام' in t and not any(k in t for k in ['اسبراي', 'سبراي', 'فرشاه', 'فرشه'])):
        return 'Makeup & Cosmetics'
        
    # Priority 6: Skincare & Body
    skin_tokens = [
        'غسول', 'سكراب', 'سكرب', 'اسكرب', 'سنفره', 'صنفره', 'تقشير', 'تونر', 'بانثينول', 'فازلين',
        'جلسرين', 'مقشر', 'طمي', 'صن بلوك', 'سن بلوك', 'واقي شمس', 'صن سكرين', 'شاور جل', 'كريم مرطب',
        'كريم تفتيح', 'كريم وجه', 'كريم عين', 'ماسك وجه', 'شيت ماسك', 'ماء ورد', 'ملح حليب', 'كعب غزال',
        'بدي لوشن', 'بدي بتر', 'زبدة شيا', 'كريم يد', 'كريم قدم', 'مرطب شفايف', 'سيروم', 'سيرم', 'لوشن', 'مرطب',
        'cleanser', 'scrub', 'lotion', 'moisturizer'
    ]
    skin_brands = [
        'ستارفيل', 'ايفا', 'بوبانا', 'شان', 'دراكون', 'كير بيبي'
    ]
    if any(k in t for k in skin_tokens) or any(k in t for k in skin_brands):
        return 'Skincare & Body'
        
    # No broad catch-all for كريم alone or زيت alone!
    return 'Uncategorized' # -->لو المنتج داخل نطاق Beauty لكنه مش مطابق لأي قاعدة، هنسيبه Uncategorized بدل ما نخمن تصنيفه
products['product_category'] = products.apply(assign_product_category, axis=1) #--> بنطبق دالة التصنيف على كل صف، ونحفظ النتيجة في عمود جديد اسمه: product_category

cols_prod = [
    'idx', 'item_code', 'item_name', 'total_qty', 'unit', 'sell_price',
    'avg_purchase_price', 'last_purchase_price', 'barcode', 'item_code_1_MISLABELED',
    'source_category', 'normalized_item_name', 'product_scope', 'product_category',
    'stock_cost_valuation'
] #--> List فيها أسماء الأعمدة اللي عايزين نحتفظ بيه
products = products[cols_prod] #--> بنحتفظ بالأعمدة الموجودة في cols_prod فقط

products.to_csv(proc_dir / "cleaned_products.csv", index=False, encoding="utf-8-sig")
products.to_csv(clean_dir / "cleaned_products.csv", index=False, encoding="utf-8-sig")
print(f" Processed {len(products)} products")

# ------------------------------------------------------------------------------
# 3 SALES INVOICES (Standardized Customer Segmentation & Account Mapping)
# ------------------------------------------------------------------------------
print("\n Processing Sales Invoices (Customer Segmentation)")
s_inv = pd.read_csv(raw_dir / "raw_sales_invoices.csv") #--> بنقرأ ملف فواتير البيع ونحفظه في s_inv
s_inv['invoice_date'] = pd.to_datetime(s_inv['date'], format='%Y-%m-%d') # -->  تحويل التاريخ إلى DateTime
s_inv['order_hour'] = pd.to_datetime(s_inv['time'], format='%H:%M:%S').dt.hour #--> بنقرأ الوقت ونستخرج الساعة فقط
s_inv['order_year'] = s_inv['invoice_date'].dt.year #--> إستخراج السنة 
s_inv['order_month'] = s_inv['invoice_date'].dt.month #--. إستخراج الشهر
s_inv['order_day_name'] = s_inv['invoice_date'].dt.day_name() #--> إستخراج إسم اليوم
s_inv['is_weekend'] = s_inv['order_day_name'].isin(['Friday', 'Saturday']) # --> تحديد عطلة أيام الأسبوع
s_inv['payment_method'] = s_inv['payment_method'].astype(str).str.strip() #-->  تحويل القيم لنصوص , إزالة المسافات الزائدة من البداية والنهاية

# Account mapping
s_inv['account_clean'] = s_inv['account'].astype(str).str.strip().replace({'nan': None}) #--> ربط اسم الحساب برقم الحساب
s_inv['acct_no'] = s_inv['account_clean'].map(acc_map) #--> Map() --> تبحث عن كل قيمة في الـ Dictionary وترجع القيمة المرتبطة بيها

# Verified Segment IDs
partner_ids = [21, 26, 30, 32, 35, 36] #--> الشركاء الداخليين
supplier_ids = [3, 4] #--> الموردون
commercial_ids = [7, 16, 17, 20, 23, 24, 25, 27, 28, 29, 31, 33] #--> العملاء التجاريون

def classify_customer(row): #--> دالة بتحدد نوع العميل من خلال رقم الحساب
    aid = row['acct_no']
    if pd.isna(aid):
        return 'Walk-in Retail'
    aid = int(aid) #--> بنحول رقم الحساب إلى Integer
    if aid in partner_ids:
        return 'Internal Partner'
    if aid in supplier_ids:
        return 'Supplier Settlement'
    if aid in commercial_ids:
        return 'Registered Commercial'
    return 'Other' #--> لو رقم الحساب مش موجود في أي قائمة بنصنفه Other

s_inv['customer_type'] = s_inv.apply(classify_customer, axis=1) #--> نطبق دالة التصنيف على كل فاتورة ونحفظ النتيجة في عمود جديد

# Partner status
s_inv['internal_account_status'] = np.where(s_inv['acct_no'].isin(partner_ids), 'confirmed', 'none')
s_inv['is_internal_account'] = s_inv['internal_account_status'] == 'confirmed'
s_inv['is_retail_sale'] = s_inv['customer_type'].isin(['Walk-in Retail', 'Registered Commercial'])

cols_sinv = [
    'counter', 'date', 'time', 'invoice_no', 'acct_no', 'account', 'customer_type',
    'internal_account_status', 'is_internal_account', 'is_retail_sale',
    'payment_method', 'total_qty', 'total_discount', 'final_total', 'profit',
    'cash_drawer', 'credit_card', 'treasury', 'paid_cash', 'deferred', 'due',
    'warehouse', 'sales_rep', 'added_by', 'added_time', 'modified_by', 'modified_time',
    'invoice_date', 'order_hour', 'order_year', 'order_month', 'order_day_name', 'is_weekend'
]
s_inv = s_inv[cols_sinv]

s_inv.to_csv(proc_dir / "cleaned_sales_invoices.csv", index=False, encoding="utf-8-sig")
s_inv.to_csv(clean_dir / "cleaned_sales_invoices.csv", index=False, encoding="utf-8-sig")
print(f" Processed {len(s_inv)} sales invoices")

# ------------------------------------------------------------------------------
# 4 SALES ITEMS
# ------------------------------------------------------------------------------
print("\n Processing Sales Items")
s_items = pd.read_csv(raw_dir / "raw_sales_items.csv")
s_items['unit_cost'] = ((s_items['line_final'] - s_items['profit']) / s_items['qty']).round(4) 

s_items.to_csv(proc_dir / "cleaned_sales_items.csv", index=False, encoding="utf-8-sig")
s_items.to_csv(clean_dir / "cleaned_sales_items.csv", index=False, encoding="utf-8-sig")
print(f"  Processed {len(s_items)} sales items")

# ------------------------------------------------------------------------------
# 5 PURCHASE INVOICES
# ------------------------------------------------------------------------------
print("\n Processing Purchase Invoices")
p_inv = pd.read_csv(raw_dir / "raw_purchase_invoices.csv")
p_inv['purchase_date'] = pd.to_datetime(p_inv['date'], format='%Y-%m-%d')
p_inv['payment_method'] = p_inv['payment_method'].astype(str).str.strip()

p_inv.to_csv(proc_dir / "cleaned_purchase_invoices.csv", index=False, encoding="utf-8-sig")
p_inv.to_csv(clean_dir / "cleaned_purchase_invoices.csv", index=False, encoding="utf-8-sig")
print(f" Processed {len(p_inv)} purchase invoices")

# ------------------------------------------------------------------------------
# 6 PURCHASE ITEMS
# ------------------------------------------------------------------------------
print("\n Processing Purchase Items")
p_items = pd.read_csv(raw_dir / "raw_purchase_items.csv")

p_items.to_csv(proc_dir / "cleaned_purchase_items.csv", index=False, encoding="utf-8-sig")
p_items.to_csv(clean_dir / "cleaned_purchase_items.csv", index=False, encoding="utf-8-sig")
print(f"  -> Processed {len(p_items)} purchase items")

# ------------------------------------------------------------------------------
# 7. SALES RETURNS INVOICES
# ------------------------------------------------------------------------------
print("\n Processing Sales Returns Invoices")
sr_inv = pd.read_csv(raw_dir / "raw_sales_returns_invoices.csv")
sr_inv['return_date'] = pd.to_datetime(sr_inv['date'], format='%Y-%m-%d')
sr_inv['return_year'] = sr_inv['return_date'].dt.year
sr_inv['return_month'] = sr_inv['return_date'].dt.month
sr_inv['return_day_name'] = sr_inv['return_date'].dt.day_name()
valid_invs = set(s_inv['invoice_no'])
sr_inv['is_linked_to_sales'] = sr_inv['original_invoice_no'].isin(valid_invs)

sr_inv.to_csv(proc_dir / "cleaned_sales_returns_invoices.csv", index=False, encoding="utf-8-sig")
sr_inv.to_csv(clean_dir / "cleaned_sales_returns_invoices.csv", index=False, encoding="utf-8-sig")
print(f"  -> Processed {len(sr_inv)} sales return invoices")

# ------------------------------------------------------------------------------
# 8 SALES RETURNS ITEMS
# ------------------------------------------------------------------------------
print("\n Processing Sales Returns Items")
sr_items = pd.read_csv(raw_dir / "raw_sales_returns_items.csv")

sr_items.to_csv(proc_dir / "cleaned_sales_returns_items.csv", index=False, encoding="utf-8-sig")
sr_items.to_csv(clean_dir / "cleaned_sales_returns_items.csv", index=False, encoding="utf-8-sig")
print(f" Processed {len(sr_items)} sales return items")

#-------------------------------------------------------------
print("VERIFYING SYNCHRONIZATION EQUALITY (data/processed/ vs cleaned/)")
csv_files = [
    "cleaned_accounts.csv", "cleaned_products.csv", "cleaned_sales_invoices.csv",
    "cleaned_sales_items.csv", "cleaned_purchase_invoices.csv", "cleaned_purchase_items.csv",
    "cleaned_sales_returns_invoices.csv", "cleaned_sales_returns_items.csv"
]

all_equal = True # --> افتراض إن كل الملفات متطابق
for f in csv_files:
    f_proc = proc_dir / f #--> تحديد مسار النسختين
    f_clean = clean_dir / f
    is_match = filecmp.cmp(f_proc, f_clean, shallow=False) #--> مقارنة الملفين
    print(f"  {f:<35}: {'IDENTICAL (Byte-for-byte match)' if is_match else 'MISMATCH'}")
    if not is_match: all_equal = False #--> لو ملف واحد مختلف، النتيجة النهائية هتفضل False حتى لو باقي الملفات متطابقة

print(f"\nAll 8 CSV pairs perfectly synchronized: {all_equal}")
