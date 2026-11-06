# دوال مساعدة لقراءة وتجهيز ملفات الإكسيل
import re
import datetime as dt
import numpy as np
import pandas as pd


def is_ts(v):
    # بيتأكد لو القيمة تاريخ
    return isinstance(v, (pd.Timestamp, dt.datetime, dt.date))


def parse_transactions(path, kind):
    # قراءة فواتير البيع أو الشراء
    raw = pd.read_excel(path, sheet_name="Sheet1", header=None) # قراءة الملف بدون هيدر
    n = len(raw)

    invoices, items = [], []
    diagnostics = {"unparsed_rows": [], "summary_mismatches": [], "no_summary_row": [], "no_blank_sep": []}

    i = 3 # بداية البيانات بعد الهيدر
    grand_total_row = None

    while i < n:
        row = raw.iloc[i]
        if pd.notna(row[0]) and is_ts(row[1]):
            inv = {
                "row_index": i, "counter": row[0], "date": row[1], "time": row[2],
                "invoice_no": row[3], "account": row[4], "payment_method": row[5],
                "total_qty": row[6], "total_discount": row[7], "final_total": row[8],
                "cash_drawer": row[9], "credit_card": row[10], "treasury": row[11],
                "paid_cash": row[12], "deferred": row[13], "due": row[14],
            }
            if kind == "sale":
                inv.update({"profit": row[15], "warehouse": row[16], "sales_rep": row[17],
                            "added_by": row[18], "added_time": row[19],
                            "modified_by": row[20], "modified_time": row[21]})
            else:
                inv.update({"warehouse": row[15], "added_by": row[16], "added_time": row[17],
                            "modified_by": row[18], "modified_time": row[19]})
            invoices.append(inv)
            i += 1

            if i < n and raw.iloc[i][1] == "رقم الصنف":
                i += 1
            else:
                diagnostics["unparsed_rows"].append(("missing_subheader", i))

            while i < n and pd.notna(raw.iloc[i][2]):
                r = raw.iloc[i]
                item = {"invoice_row_index": inv["row_index"], "invoice_no": inv["invoice_no"],
                        "item_code": r[1], "item_name": r[2], "unit": r[3],
                        "available_qty": r[4], "qty": r[5], "price": r[6], "discount": r[7]}
                if kind == "sale":
                    item["profit"] = r[8]
                    item["line_final"] = r[9]
                else:
                    item["line_final"] = r[8]
                items.append(item)
                i += 1

            if i < n and pd.isna(raw.iloc[i][2]) and (pd.notna(raw.iloc[i][5]) or pd.notna(raw.iloc[i][8])):
                srow = raw.iloc[i]
                sum_qty, sum_discount = srow[5], srow[7]
                sum_final = srow[9] if kind == "sale" else srow[8]
                if not np.isclose(pd.to_numeric(sum_qty, errors="coerce") or 0,
                                   pd.to_numeric(inv["total_qty"], errors="coerce") or 0, atol=0.01):
                    diagnostics["summary_mismatches"].append((inv["invoice_no"], "qty", sum_qty, inv["total_qty"]))
                if not np.isclose(pd.to_numeric(sum_final, errors="coerce") or 0,
                                   pd.to_numeric(inv["final_total"], errors="coerce") or 0, atol=0.5):
                    diagnostics["summary_mismatches"].append((inv["invoice_no"], "final", sum_final, inv["final_total"]))
                i += 1
            else:
                diagnostics["no_summary_row"].append(inv["invoice_no"])

            if i < n:
                nxt = raw.iloc[i]
                if nxt.isna().all():
                    i += 1
                elif pd.notna(nxt[0]) and is_ts(nxt[1]):
                    diagnostics["no_blank_sep"].append(inv["invoice_no"])
        else:
            if i == n - 1:
                grand_total_row = row
                i += 1
            elif row.isna().all():
                i += 1
            else:
                diagnostics["unparsed_rows"].append(("stray", i, row.tolist()))
                i += 1

    return pd.DataFrame(invoices), pd.DataFrame(items), grand_total_row, diagnostics


def parse_goods(path):
    # قراءة شيت البضاعة
    goods = pd.read_excel(path, sheet_name="Sheet1", header=None, skiprows=3) # تخطي أول 3 صفوف
    goods.columns = ["idx", "item_code", "item_name", "total_qty", "unit", "sell_price",
                      "avg_purchase_price", "last_purchase_price", "barcode",
                      "item_code_1_MISLABELED", "source_category"]
    goods = goods[goods["item_code"].notna()].copy()
    goods["item_code"] = pd.to_numeric(goods["item_code"], errors="coerce").astype(int)
    return goods.reset_index(drop=True)


def parse_accounts(path):
    # قراءة شيت الحسابات
    accounts = pd.read_excel(path, sheet_name="Sheet1", header=None, skiprows=4) # تخطي أول 4 صفوف
    accounts.columns = ["idx", "acct_no", "acct_name", "balance_debit", "balance_credit",
                         "checks_debit", "checks_credit", "nature", "category", "acct_code",
                         "mobile", "address", "discount_pct", "sell_price", "review_date",
                         "last_sale_date", "last_sale_total", "last_receipt_date", "last_receipt_value"]
    accounts = accounts[accounts["acct_no"].notna()].copy()
    return accounts.reset_index(drop=True)


def parse_returns(path):
    # قراءة فواتير مرتجع البيع
    raw = pd.read_excel(path, sheet_name="Sheet1", header=None)
    n = len(raw)
    invoices, items = [], []
    diagnostics = {"unparsed_rows": [], "summary_mismatches": [], "no_summary_row": []}

    i = 3
    grand_total_row = None
    while i < n:
        row = raw.iloc[i]
        if pd.notna(row[0]) and is_ts(row[1]):
            inv = {
                "row_index": i, "counter": row[0], "date": row[1], "time": row[2],
                "return_invoice_no": row[3], "original_invoice_no": row[4],
                "account": row[5], "payment_method": row[6],
                "total_qty": row[7], "total_discount": row[8], "final_total": row[9],
                "cash_drawer": row[10], "credit_card": row[11], "treasury": row[12],
                "paid_cash": row[13], "deferred": row[14], "due": row[15], "profit": row[16],
                "warehouse": row[17], "sales_rep": row[18],
                "added_by": row[19], "added_time": row[20],
                "modified_by": row[21], "modified_time": row[22],
            }
            invoices.append(inv)
            i += 1
            if i < n and raw.iloc[i][1] == "رقم الصنف":
                i += 1
            else:
                diagnostics["unparsed_rows"].append(("missing_subheader", i))
            while i < n and pd.notna(raw.iloc[i][2]):
                r = raw.iloc[i]
                items.append({
                    "invoice_row_index": inv["row_index"], "return_invoice_no": inv["return_invoice_no"],
                    "item_code": r[1], "item_name": r[2], "unit": r[3],
                    "available_qty": r[4], "qty": r[5], "price": r[6], "discount": r[7],
                    "profit": r[8], "line_final": r[9],
                })
                i += 1
            if i < n and pd.isna(raw.iloc[i][2]) and (pd.notna(raw.iloc[i][5]) or pd.notna(raw.iloc[i][9])):
                srow = raw.iloc[i]
                sum_qty, sum_final = srow[5], srow[9]
                if not np.isclose(pd.to_numeric(sum_qty, errors="coerce") or 0,
                                   pd.to_numeric(inv["total_qty"], errors="coerce") or 0, atol=0.01):
                    diagnostics["summary_mismatches"].append((inv["return_invoice_no"], "qty", sum_qty, inv["total_qty"]))
                if not np.isclose(pd.to_numeric(sum_final, errors="coerce") or 0,
                                   pd.to_numeric(inv["final_total"], errors="coerce") or 0, atol=0.5):
                    diagnostics["summary_mismatches"].append((inv["return_invoice_no"], "final", sum_final, inv["final_total"]))
                i += 1
            else:
                diagnostics["no_summary_row"].append(inv["return_invoice_no"])
            if i < n and raw.iloc[i].isna().all():
                i += 1
        else:
            if i == n - 1:
                grand_total_row = row
                i += 1
            elif row.isna().all():
                i += 1
            else:
                diagnostics["unparsed_rows"].append(("stray", i, row.tolist()))
                i += 1

    return pd.DataFrame(invoices), pd.DataFrame(items), grand_total_row, diagnostics


def normalize_arabic(name):
    # توحيد الحروف وحذف المسافات لمقارنة الأسماء
    if name is None or (isinstance(name, float) and np.isnan(name)):
        return ""
    s = str(name).strip()
    s = re.sub(r"\s+", "", s)
    s = s.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
    s = s.replace("ة", "ه")
    s = s.replace("ى", "ي")
    return s


# كلمات مفتاحية لتصنيف الأصناف
CATEGORY_RULES = [
    ("Tools", ["امواس", "اموس حواجب", "شفرات حواجب", "مقص حواجب"]),
    ("Nails", ["مناكير", "مانكير", "نيل ارت", "جل نيل", "طلاء اظافر", "ريموفر مناكير",
               "اظافر", "نيلات", "بوليش", "مبرد اظافر", "NAIL"]),
    ("Perfumes", ["برفان", "عطر ", "عطور", "او دي بارفيوم", "او دي تواليت", "كولونيا",
                  "كلونيا", "مسك ", "بارفان", "برفانات", "فو كلونيا", "مخمرية", "مخمريه", "PERFUME"]),
    ("Haircare", ["شامبو", "بلسم", "حمام كريم", "كيراتين", "صبغة شعر", "صبغه شعر", "صبغة",
                  "صبغه", "فرد الشعر", "مثبت الشعر", "جل شعر", "سبراي شعر", "حناء", "حنة",
                  "بروتين شعر", "زيت شعر", "سيروم شعر", "بديل الزيت", "تساقط الشعر",
                  "نمو الشعر", "تطويل الشعر", "ماسك شعر", "كرمب", "كريم شعر", "مكينة حلاقة",
                  "سشوار", "مكواة شعر", "ليف ان", "كانتو", "علاج الشعر", "حمام زيت",
                  "زيت الشعر", "بخاخ شعر", "واقي حراري", "سيروم للشعر", "فاتيكا", "كاريس",
                  "كلبس شعر", "كليبس شعر", "برطمان الشعر", "خلطة الحرير", "القطران", "تساقط "]),
    ("Makeup", ["ميكب", "ميك اب", "ميكاب", "مكياج", "روج ", "احمر شفاه", "كونسيلر",
                "فاونديشن", "كريم اساس", "بودرة", "بودره", "باودر", "بدرة", "بودر ", "كحل",
                "ايلاينر", "ماسكرا", "مسكرا", "مسكرة", "هايلايتر", "هيلايتر", "هيليتر",
                "هاي لايتر", "بلاشر", "برونزر", "ايشادو", "شادو", "برايمر", "باليت", "بالیت",
                "كونتور", "كنتور", "ليب", "تحديد شفايف", "استيك", "فيلر شفايف", "حواجب",
                "ايبرو", "قرمز الوان", "شنطة ميكب", "حقيبة ميكب", "لاش سيرم", "رموش",
                "خدود", "عدسات", "LIP", "MASCARA", "BLUSH", "FOUNDATION", "CONCEALER",
                "HIGHLIGHT", "EYESHADOW", "GLOSS", "LASH", "BROW", "CONTOUR", "PRIMER",
                "POWDER", "LINER", "STICK", "SHADE", "BOUQUET", "MATTE", "GLAM",
                "BEAUTY BLENDER", "بيوتى بلندر", "COLOR", "COLLOR", "CORRECTION"]),
    ("Skincare", ["غسول", "سيروم", "سيرم", "مرطب", "تقشير", "سكراب", "ماسك", "ماسكة",
                  "تونر", "مزيل مكياج", "كولاجين", "فيتامين سي", "صن سكرين", "واقي شمس",
                  "مضاد للتجاعيد", "انتي ايجنج", "كريم للوجه", "كريم الوجه", "منظف بشرة",
                  "قناع", "بشرة دهنية", "بشرة جافة", "حب الشباب", "بقع", "فازلين",
                  "تشققات الكعبين", "ملح حليب", "تفتيح البشرة", "حول العين", "غاسول", "ميسلر"]),
    ("Personal Care", ["مزيل عرق", "ديودرانت", "صابون استحمام", "لوشن الجسم", "لوشن",
                        "معطر جسم", "كريم جسم", "جسم كريم", "غسول الجسم", "صابون",
                        "دهون الجسم", "بادي", "بدي ", "استحمام", "معطر الملابس",
                        "مزيل العرق", "رول اون", "صنفرة قدم", "اسبلاش", "سبلاش", "ليفة",
                        "ليفه", "مناديل مبلله", "ازالة واكس", "نيفيا", "سيجنال", "قطن",
                        "بيكيني", "شاور"]),
    ("Gift/Packaging", ["هدايا", "هديه", "هدية", "بوكس هدايا", "شنطة هدايا", "طقم هدايا",
                         "علبة تغليف", "تغليف"]),
    ("Tools", ["فرشاة", "فرشة", "مقص", "ملقط", "مبرد", "اسفنجة", "سفنج", "بف ", "مشط",
               "ادوات", "استاند", "مرايه", "مرآة", "ماكينة حريمي", "ماكينة ازالة",
               "فرشة اسنان", "صنفرة", "شفرات", "شفراتت", "شفاره", "مكنة", "جيليت",
               "دوركو", "تاتوة"]),
    ("Accessories", ["اكسسوار", "طوق شعر", "دبوس شعر", "كليبس", "كلبس", "توكة", "حزام",
                      "حلق", "اسورة", "خاتم", "قلادة", "سلسلة", "شنطة", "حقيبة", "خرز"]),
    ("Haircare", ["فك تشابك", "اسبراي ملمع", "اسبراى ملمع", "سنيور", "برفيوم للشعر"]),
    ("Personal Care", ["واكس", "شمع", "شمعية", "جهاز شمع", "اسبراي ازالة", "اسبراى ازالة"]),
    ("Nails", ["اسيتون", "اسيتن"]),
    ("Skincare", ["اسبراي تفتيح", "اسبراى تفتيح", "ميسيل", "ميسلار", "كلينسر", "كيور ايد", "فير اند لافلي",
                  "باتشات", "مقشر", "طمي مغربي", "الحمام المغربي", "موس تنظيف", "كبسولات للبشرة",
                  "اسكرين", "جل ليلي", "غسوا", "فيتامين", "ترطيب للبشرة", "حفاضة"]),
    ("Tools", ["فرشه", "فرش اسنان", "بيوتي بلندر", "بلندر", "ماكينة", "قصافه", "شفره", "حجر قدم"]),
    ("Personal Care", ["بليه", "هاند ووش", "هاند واش", "هاند وش", "صنفره", "اولد سبايس", "ريكسونا",
                       "دوف ", "جونسون", "بخاخ", "اسبراي", "اسبراى", "اسبرى", "سبراي", "ليف ", "دولفين",
                       "معجون", "كلوز اب", "اورال", "ستارفيل", "بيور "]),
    ("Haircare", ["بديل زيت", "زيت", "زيوت", "كيرلي", "هيرفود", "هيرتونك", "مايونيز شعر", "فك تشابك",
                  "ببندانه", "بالبندانه", "جيل بالبندانه", "بانتين", "صانسيلك", "فيانسيه", "تريشوب",
                  "املا", "نونو", "ايمامي", "فلكسيد", "بيو سوفت", "باشن بيبي", "هير"]),
    ("Makeup", ["مايت سينما", "ام ان ", "ساندرا", "منايا", "شيجلام", "بريتي", "روز جولد", "اكلادور",
                "مسكره", "ملمع", "ليفتر", "تنت", "ايلينر", "ريشه", "كجال", "دينامك", "دايناميك", "اساس"]),
    ("Accessories", ["خلخال", "انسيال", "طوق", "شال", "طرحه", "طرحة", "اورجانزا", "مودال", "شاش",
                     "شنطه", "وشاح", "بنس"]),
    ("Haircare", ["الشعر"]),
    ("Skincare", ["كريم"]),
]


def classify_category(name):
    # تصنيف الصنف حسب الكلمات المفتاحية
    if name is None:
        return "Other/Unknown"
    n = str(name)
    n_upper = n.upper()
    for cat, kws in CATEGORY_RULES:
        for kw in kws:
            if kw.isupper() and kw.isascii():
                if kw in n_upper:
                    return cat
            elif kw in n:
                return cat
    return "Other/Unknown"
