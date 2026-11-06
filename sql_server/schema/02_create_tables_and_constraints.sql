-- *****************************************************************************
-- 02_create_tables_and_constraints.sql
-- مخطط الجداول والقيود والعلاقات لقاعدة بيانات متجر مستحضرات التجميل (cosmetics_store)
-- مبادرة مصر الرقمية (DEPI) - مسار تحليل البيانات Data Analytics
-- *****************************************************************************

use cosmetics_store;
go

-- حذف الجداول الفرعية أولاً لتجنب تعارض قيود المفاتيح الأجنبية (FK Dependencies)
if object_id('dbo.FactSalesReturnItem', 'U') is not null drop table dbo.FactSalesReturnItem;
if object_id('dbo.FactSalesReturnInvoice', 'U') is not null drop table dbo.FactSalesReturnInvoice;
if object_id('dbo.FactPurchaseItem', 'U') is not null drop table dbo.FactPurchaseItem;
if object_id('dbo.FactPurchaseInvoice', 'U') is not null drop table dbo.FactPurchaseInvoice;
if object_id('dbo.FactSalesItem', 'U') is not null drop table dbo.FactSalesItem;
if object_id('dbo.FactSalesInvoice', 'U') is not null drop table dbo.FactSalesInvoice;
if object_id('dbo.DimProduct', 'U') is not null drop table dbo.DimProduct;
if object_id('dbo.DimAccount', 'U') is not null drop table dbo.DimAccount;
if object_id('dbo.DimDate', 'U') is not null drop table dbo.DimDate;
if object_id('dbo.MissingInvoicesLog', 'U') is not null drop table dbo.MissingInvoicesLog;
go

-- =============================================================================
-- 1. جداول الأبعاد (Dimension Tables)
-- =============================================================================

-- 1.1 جدول دليل الحسابات الرئيسي (DimAccount)
--------------------------------------------------------------------------------
create table dbo.DimAccount (
    acct_no int not null, --> رقم الحساب التعريفي الفريد
    acct_name nvarchar(255) not null, --> اسم الحساب أو العميل أو المورد
    nature nvarchar(50) not null, --> طبيعة الحساب الأصلية في النظام (عميل / مورد / أخرى)
    account_classification nvarchar(50) not null, --> التصنيف المحاسبي المعتمد (Customer, Supplier, Staff, Partner, Expense)
    classification_rationale nvarchar(255) null, --> توثيق سبب التصنيف والدليل المحاسبي
    is_internal bit not null constraint DF_DimAccount_is_internal default (0), --> علامة تمييز الحسابات الداخلية (1 للداخلي، 0 للعملاء والموردين)
    balance_debit decimal(18, 4) null, --> رصيد مدين للحساب
    balance_credit decimal(18, 4) null, --> رصيد دائن للحساب
    discount_pct decimal(18, 4) null, --> نسبة الخصم الممنوحة للحساب
    mobile nvarchar(50) null, --> رقم الهاتف المحمول إن وجد
    address nvarchar(500) null, --> عنوان الحساب
    last_sale_date date null, --> تاريخ آخر فاتورة بيع للحساب
    last_sale_total decimal(18, 4) null, --> قيمة آخر فاتورة بيع
    last_receipt_date date null, --> تاريخ آخر إيصال سداد
    last_receipt_value decimal(18, 4) null, --> قيمة آخر إيصال سداد
    constraint PK_DimAccount primary key clustered (acct_no) --> المفتاح الأساسي للجدول
);
go

-- 1.2 جدول كتالوج الأصناف والمنتجات (DimProduct)
--------------------------------------------------------------------------------
create table dbo.DimProduct (
    item_code int not null, --> كود الصنف الفريد في النظام
    item_name nvarchar(500) not null, --> اسم الصنف الأصلي كما هو مدخل
    normalized_item_name nvarchar(500) null, --> اسم الصنف بعد توحيد الحروف وإزالة المسافات والتشكيل
    product_scope nvarchar(100) not null, --> نطاق المنتج (In-Scope Beauty, Fashion, Personal Care, Packaging)
    product_category nvarchar(100) not null, --> القسم التجميلي (Makeup, Haircare, Fragrances, Skincare, Tools, Nails, Uncategorized)
    source_category nvarchar(100) null, --> التصنيف الأصلي من نظام نقاط البيع
    total_qty decimal(18, 4) not null, --> الرصيد الحالي للقطعة بالمخزن
    unit nvarchar(50) null, --> وحدة القياس (قطعة، علبة...)
    sell_price decimal(18, 4) not null, --> سعر بيع الوحدة للجمهور
    avg_purchase_price decimal(18, 4) not null, --> متوسط سعر تكلفة الشراء للوحدة
    last_purchase_price decimal(18, 4) not null, --> آخر سعر تم الشراء به
    barcode nvarchar(100) null, --> الباركود الدولي أو المحلي للصنف
    item_code_1_MISLABELED nvarchar(100) null, --> كود إضافي بديل تم تصديره من النظام
    stock_cost_valuation decimal(18, 4) not null, --> القيمة المالية للمخزون بالتكلفة (الرصيد * متوسط الشراء)
    is_out_of_stock bit not null constraint DF_DimProduct_is_out_of_stock default (0), --> علامة نفاد الرصيد أو كونه سالباً (1 للنافد، 0 للمتوفر)
    constraint PK_DimProduct primary key clustered (item_code) --> المفتاح الأساسي للكتالوج
);
go

-- 1.3 جدول التواريخ والتقويم الزمني (DimDate)
--------------------------------------------------------------------------------
create table dbo.DimDate (
    date_key int not null primary key, --> المفتاح الرقمي للتاريخ بصيغة yyyymmdd
    full_date date not null, --> التاريخ الفعلي بصيغة YYYY-MM-DD
    [year] int not null, --> السنة الميلادية
    [quarter] int not null, --> الربع السنوي من 1 إلى 4
    [month] int not null, --> رقم الشهر من 1 إلى 12
    year_month char(7) not null, --> صيغة السنة والشهر YYYY-MM لتسهيل التجميع
    month_name nvarchar(20) not null, --> اسم الشهر بالإنجليزية
    days_in_month int not null, --> إجمالي عدد أيام الشهر لمعرفة الشهور الجزئية
    iso_week int not null, --> رقم أسبوع السنة وفقاً لمعيار ISO
    weekday_no int not null, --> رقم اليوم في الأسبوع (1 = الإثنين ... 7 = الأحد)
    weekday_name nvarchar(20) not null, --> اسم يوم الأسبوع بالإنجليزية
    is_weekend bit not null --> علامة عطلة نهاية الأسبوع في مصر (1 للجمعة والسبت)
);
go

-- 1.4 جدول رصد الفواتير المفقودة في التسلسل (MissingInvoicesLog)
--------------------------------------------------------------------------------
create table dbo.MissingInvoicesLog (
    missing_invoice_no int not null primary key, --> رقم الفاتورة المفقود في التسلسل الزمني
    gap_after_invoice int not null, --> رقم آخر فاتورة سابقة موجودة قبل الفجوة
    gap_before_invoice int not null, --> رقم أول فاتورة تالية موجودة بعد الفجوة
    detected_at datetime not null default getdate() --> توقيت رصد واكتشاف الفجوة
);
go

-- =============================================================================
-- 2. جداول الحقائق - فواتير وبنود المبيعات (Sales Fact Tables)
-- =============================================================================

-- 2.1 جدول فواتير المبيعات الرئيسية (FactSalesInvoice)
--------------------------------------------------------------------------------
create table dbo.FactSalesInvoice (
    invoice_no int not null, --> رقم فاتورة البيع الفريد
    counter int null, --> عداد الفاتورة التسلسلي اليومي
    invoice_date date not null, --> تاريخ إجراء الفاتورة
    order_time time null, --> توقيت إصدار الفاتورة بالساعة والدقيقة
    order_hour int null, --> ساعة اليوم من 0 إلى 23 لتحليل ساعات الذروة
    order_year int null, --> سنة إصدار الفاتورة
    order_month int null, --> شهر إصدار الفاتورة
    order_day_name nvarchar(20) null, --> اسم يوم الأسبوع للفاتورة
    is_weekend bit not null constraint DF_FactSalesInvoice_is_weekend default (0), --> هل الفاتورة صدرت في يوم عطلة
    acct_no int null, --> رقم حساب العميل المسجل إن وجد (NULL لعملاء التجزئة الكاش)
    account_name nvarchar(255) null, --> اسم العميل المسجل كما ورد بالفاتورة
    customer_account_classification nvarchar(50) not null, --> تصنيف حساب العميل
    sale_type nvarchar(50) not null, --> نوع المعاملة (Walk-in cash, Named customer, Partner, Staff, Expense, Supplier)
    internal_account_status nvarchar(20) not null constraint DF_FactSalesInvoice_internal_status default ('none'), --> حالة الحساب الداخلي
    is_internal_account bit not null constraint DF_FactSalesInvoice_is_internal default (0), --> علامة تمييز الحركات الداخلية
    is_retail_sale bit not null constraint DF_FactSalesInvoice_is_retail default (1), --> علامة البيع القطاعي الفعلي المعتمد للتحليل
    payment_method nvarchar(50) null, --> طريقة السداد (نقدي، آجل...)
    total_qty decimal(18, 4) not null, --> إجمالي عدد القطع المباعة في الفاتورة
    total_discount decimal(18, 4) not null constraint DF_FactSalesInvoice_total_discount default (0), --> إجمالي الخصم الممنوح
    final_total decimal(18, 4) not null, --> القيمة الصافية النهائية للفاتورة بعد الخصم
    profit decimal(18, 4) not null, --> مجمل ربح الفاتورة (الإيراد - التكلفة)
    cash_drawer decimal(18, 4) null, --> المدفوع في درج الكاشير
    credit_card decimal(18, 4) null, --> المدفوع بالفيزا أو البطاقة
    treasury decimal(18, 4) null, --> المدفوع في الخزينة
    paid_cash decimal(18, 4) null, --> إجمالي المسدد نقداً
    deferred decimal(18, 4) null, --> الجزء الآجل أو المتبقي على الحساب
    due decimal(18, 4) null, --> المستحق
    warehouse nvarchar(100) null, --> اسم المخزن الذي خرجت منه البضاعة
    sales_rep nvarchar(100) null, --> مندوب البيع المسئول
    added_by nvarchar(100) null, --> اسم المستخدم الذي أدخل الفاتورة
    added_time time null, --> وقت إدخال الفاتورة
    modified_by nvarchar(100) null, --> اسم المستخدم الذي عدل الفاتورة
    modified_time time null, --> وقت تعديل الفاتورة
    constraint PK_FactSalesInvoice primary key clustered (invoice_no), --> المفتاح الأساسي للفواتير
    constraint FK_FactSalesInvoice_DimAccount foreign key (acct_no) references dbo.DimAccount(acct_no) --> ربط الفاتورة بدليل الحسابات
);
go

-- 2.2 جدول بنود وتفاصيل فواتير المبيعات (FactSalesItem)
--------------------------------------------------------------------------------
create table dbo.FactSalesItem (
    sales_item_id int identity(1, 1) not null, --> identity(1,1) ترقيم تلقائي فريد لكل سطر بند بيع
    invoice_no int not null, --> رقم الفاتورة التابع لها البند
    invoice_row_index int null, --> ترتيب السطر داخل الفاتورة
    item_code int not null, --> كود الصنف المباع من الكتالوج
    item_name nvarchar(500) not null, --> اسم الصنف كما ورد في الفاتورة
    available_qty decimal(18, 4) null, --> الرصيد المتاح لحظة البيع
    qty decimal(18, 4) not null, --> الكمية المباعة من الصنف في هذا السطر
    price decimal(18, 4) not null, --> سعر بيع الوحدة قبل الخصم
    discount decimal(18, 4) not null constraint DF_FactSalesItem_discount default (0), --> قيمة الخصم الممنوح على البند
    profit decimal(18, 4) not null, --> مجمل الربح المحقق من هذا السطر
    line_final decimal(18, 4) not null, --> إجمالي قيمة السطر النهائية بعد الخصم
    unit_cost decimal(18, 4) not null constraint DF_FactSalesItem_unit_cost default (0), --> تكلفة الوحدة المحسوبة بأمان
    constraint PK_FactSalesItem primary key clustered (sales_item_id), --> المفتاح الأساسي للبند
    constraint FK_FactSalesItem_FactSalesInvoice foreign key (invoice_no) references dbo.FactSalesInvoice(invoice_no), --> ربط البند برأس الفاتورة
    constraint FK_FactSalesItem_DimProduct foreign key (item_code) references dbo.DimProduct(item_code) --> ربط البند بكتالوج الأصناف
);
go

-- =============================================================================
-- 3. جداول الحقائق - فواتير وبنود المشتريات (Purchase Fact Tables)
-- =============================================================================

-- 3.1 جدول فواتير المشتريات الرئيسية (FactPurchaseInvoice)
--------------------------------------------------------------------------------
create table dbo.FactPurchaseInvoice (
    invoice_no int not null, --> رقم فاتورة الشراء الفريد
    counter int null, --> عداد الفاتورة
    purchase_date date not null, --> تاريخ إجراء عملية الشراء والتوريد
    purchase_time time null, --> وقت تسجيل فاتورة الشراء
    acct_no int null, --> رقم حساب المورد في دليل الحسابات
    account_name nvarchar(255) null, --> اسم المورد
    payment_method nvarchar(50) null, --> طريقة السداد للمورد (نقدي / آجل)
    total_qty decimal(18, 4) not null, --> إجمالي عدد القطع المشتراة
    total_discount decimal(18, 4) not null constraint DF_FactPurchaseInvoice_total_discount default (0), --> إجمالي الخصم الممنوح من المورد
    final_total decimal(18, 4) not null, --> إجمالي قيمة فاتورة الشراء بالتكلفة
    cash_drawer decimal(18, 4) null, --> المدفوع من درج الكاشير
    credit_card decimal(18, 4) null, --> المدفوع ببطاقة الدفع
    treasury decimal(18, 4) null, --> المدفوع من الخزينة الرئيسية
    paid_cash decimal(18, 4) null, --> إجمالي المسدد نقداً للمورد
    deferred decimal(18, 4) null, --> المتبقي آجل على حساب المورد
    due decimal(18, 4) null, --> المستحق
    warehouse nvarchar(100) null, --> المخزن المستلم للبضاعة
    added_by nvarchar(100) null, --> المستخدم الذي سجل الشراء
    added_time time null, --> وقت التسجيل
    modified_by nvarchar(100) null, --> المستخدم الذي عدل الفاتورة
    modified_time time null, --> وقت التعديل
    constraint PK_FactPurchaseInvoice primary key clustered (invoice_no), --> المفتاح الأساسي لفواتير الشراء
    constraint FK_FactPurchaseInvoice_DimAccount foreign key (acct_no) references dbo.DimAccount(acct_no) --> ربط الشراء بدليل الحسابات
);
go

-- 3.2 جدول بنود وتفاصيل فواتير المشتريات (FactPurchaseItem)
--------------------------------------------------------------------------------
create table dbo.FactPurchaseItem (
    purchase_item_id int identity(1, 1) not null, --> ترقيم تسلسلي تلقائي فريد لكل سطر بند شراء
    invoice_no int not null, --> رقم فاتورة الشراء التابع لها البند
    invoice_row_index int null, --> ترتيب السطر في فاتورة الشراء
    item_code int not null, --> كود الصنف المورد
    item_name nvarchar(500) not null, --> اسم الصنف المورد
    available_qty decimal(18, 4) null, --> الرصيد المتاح وقت التوريد
    qty decimal(18, 4) not null, --> الكمية المشتراة من الصنف
    price decimal(18, 4) not null, --> سعر شراء الوحدة من المورد
    discount decimal(18, 4) not null constraint DF_FactPurchaseItem_discount default (0), --> الخصم الممنوح على البند
    line_final decimal(18, 4) not null, --> إجمالي تكلفة البند بعد الخصم
    constraint PK_FactPurchaseItem primary key clustered (purchase_item_id), --> المفتاح الأساسي لبند الشراء
    constraint FK_FactPurchaseItem_FactPurchaseInvoice foreign key (invoice_no) references dbo.FactPurchaseInvoice(invoice_no), --> ربط البند بفاتورة الشراء
    constraint FK_FactPurchaseItem_DimProduct foreign key (item_code) references dbo.DimProduct(item_code) --> ربط البند بكتالوج الأصناف
);
go

-- =============================================================================
-- 4. جداول الحقائق - فواتير وبنود مرتجع المبيعات (Sales Returns Fact Tables)
-- =============================================================================

-- 4.1 جدول فواتير مرتجع المبيعات الرئيسية (FactSalesReturnInvoice)
--------------------------------------------------------------------------------
create table dbo.FactSalesReturnInvoice (
    return_invoice_no int not null, --> رقم إشعار أو فاتورة المرتجع الفريد
    counter int null, --> عداد المرتجع
    return_date date not null, --> تاريخ إجراء المرتجع
    return_time time null, --> وقت تسجيل المرتجع
    return_year int null, --> سنة المرتجع
    return_month int null, --> شهر المرتجع
    return_day_name nvarchar(20) null, --> اسم يوم الأسبوع للمرتجع
    original_invoice_no int null, --> رقم فاتورة البيع الأصلية إن وجدت (مرجع منطقي)
    original_invoice_status nvarchar(100) not null, --> حالة الفاتورة الأصلية (Found, No original 0, Cutoff)
    is_linked_to_sales bit not null constraint DF_FactSalesReturnInvoice_is_linked default (1), --> هل المرتجع مربوط بفاتورة بيع معتمدة
    is_retail_sale bit not null constraint DF_FactSalesReturnInvoice_is_retail default (1), --> علامة تخصيص المرتجع لمبيعات التجزئة
    acct_no int null, --> رقم حساب العميل الذي أرجع البضاعة
    account_name nvarchar(255) null, --> اسم العميل
    payment_method nvarchar(50) null, --> طريقة رد المبلغ (نقدي...)
    total_qty decimal(18, 4) not null, --> إجمالي عدد القطع المرتجعة
    total_discount decimal(18, 4) not null constraint DF_FactSalesReturnInvoice_total_discount default (0), --> الخصم المسترد
    final_total decimal(18, 4) not null, --> إجمالي قيمة المرتجع المستردة بالسالب
    profit decimal(18, 4) not null, --> الأثر على مجمل الربح بالسالب
    cash_drawer decimal(18, 4) null, --> المسترد من درج الكاشير
    credit_card decimal(18, 4) null, --> المسترد على بطاقة الدفع
    treasury decimal(18, 4) null, --> المسترد من الخزينة
    paid_cash decimal(18, 4) null, --> المسدد نقداً للزبون
    deferred decimal(18, 4) null, --> المخصوم من الحساب الآجل
    due decimal(18, 4) null, --> المستحق
    warehouse nvarchar(100) null, --> المخزن الذي دخلت إليه البضاعة المرتجعة
    sales_rep nvarchar(100) null, --> مندوب المبيعات
    added_by nvarchar(100) null, --> مدخل حركة المرتجع
    added_time time null, --> وقت الإدخال
    modified_by nvarchar(100) null, --> معدل المرتجع
    modified_time time null, --> وقت التعديل
    constraint PK_FactSalesReturnInvoice primary key clustered (return_invoice_no), --> المفتاح الأساسي لفواتير المرتجع
    constraint FK_FactSalesReturnInvoice_DimAccount foreign key (acct_no) references dbo.DimAccount(acct_no) --> ربط المرتجع بدليل الحسابات
);
go

-- 4.2 جدول بنود وتفاصيل فواتير مرتجع المبيعات (FactSalesReturnItem)
--------------------------------------------------------------------------------
create table dbo.FactSalesReturnItem (
    return_item_id int identity(1, 1) not null, --> ترقيم تسلسلي تلقائي فريد لكل سطر بند مرتجع
    return_invoice_no int not null, --> رقم فاتورة المرتجع التابع لها البند
    invoice_row_index int null, --> ترتيب السطر في فاتورة المرتجع
    item_code int not null, --> كود الصنف المرتجع
    item_name nvarchar(500) not null, --> اسم الصنف المرتجع
    available_qty decimal(18, 4) null, --> الرصيد المتاح وقت الإرجاع
    qty decimal(18, 4) not null, --> الكمية المرتجعة
    price decimal(18, 4) not null, --> سعر بيع الوحدة المسترد
    discount decimal(18, 4) not null constraint DF_FactSalesReturnItem_discount default (0), --> الخصم المسترد على البند
    profit decimal(18, 4) not null, --> الأثر السلبي على الربح لهذا السطر
    line_final decimal(18, 4) not null, --> إجمالي قيمة السطر المرتجعة بالسالب
    constraint PK_FactSalesReturnItem primary key clustered (return_item_id), --> المفتاح الأساسي لبند المرتجع
    constraint FK_FactSalesReturnItem_FactSalesReturnInvoice foreign key (return_invoice_no) references dbo.FactSalesReturnInvoice(return_invoice_no), --> ربط البند بفاتورة المرتجع
    constraint FK_FactSalesReturnItem_DimProduct foreign key (item_code) references dbo.DimProduct(item_code) --> ربط البند بكتالوج الأصناف
);
go
