-- ******************************************************
--               Create Tables & Constraints
-- ******************************************************

use cosmetics_store;
go

-- ******************************************************
--                 1. Dimension Tables
-- ******************************************************

--1) جدول بيانات الحسابات والعملاء والموردين
---------------------------------------------
if object_id('dbo.DimAccount', 'U') is not null drop table dbo.DimAccount;
go

create table dbo.DimAccount (
    acct_no int not null, --> رقم الحساب وهو المفتاح الأساسي للجدول
    acct_name nvarchar(255) not null, /* nvarchar عشان يقبل النصوص والعربي */
    nature nvarchar(50) null, --> طبيعة الحساب
    category nvarchar(100) null, --> تصنيف الحساب
    balance_debit decimal(18, 4) not null constraint DF_DimAccount_balance_debit default (0), /* decimal للأرقام المالية والكسور */
    balance_credit decimal(18, 4) not null constraint DF_DimAccount_balance_credit default (0), --> رصيد دائن وافتراضياً 0
    discount_pct decimal(10, 4) not null constraint DF_DimAccount_discount_pct default (0), --> نسبة الخصم الممنوحة
    sell_price decimal(18, 4) not null constraint DF_DimAccount_sell_price default (0),
    last_sale_date date null, --> تاريخ آخر فاتورة بيع
    last_sale_total decimal(18, 4) not null constraint DF_DimAccount_last_sale_total default (0),
    constraint PK_DimAccount primary key clustered (acct_no) --> Primary Key المفتاح الأساسي للجدول
);
go

--2) جدول كتالوج المنتجات وتصنيفاتها
---------------------------------------------
if object_id('dbo.DimProduct', 'U') is not null drop table dbo.DimProduct;
go

create table dbo.DimProduct (
    item_code int not null, --> كود الصنف وهو المفتاح الأساسي
    item_name nvarchar(500) not null, --> اسم المنتج التجاري
    normalized_item_name nvarchar(500) null, --> اسم المنتج بعد التنظيف والتوحيد
    product_scope nvarchar(100) not null, --> نطاق العمل للمنتج
    product_category nvarchar(100) not null, --> القسم الرئيسي التابع له المنتج Category
    source_category nvarchar(100) null, --> التصنيف الأصلي من السيستم قبل التوحيد
    barcode nvarchar(50) null, /* nvarchar عشان الباركود ممكن يبدأ بأصفار */
    total_qty decimal(18, 4) not null, --> إجمالي رصيد المخزون المتبقي
    sell_price decimal(18, 4) not null, --> سعر بيع القطعة للجمهور
    avg_purchase_price decimal(18, 4) not null, --> متوسط تكلفة الشراء للقطعة
    last_purchase_price decimal(18, 4) not null, --> آخر سعر شراء تم التوريد به
    stock_cost_valuation decimal(18, 4) not null, --> التقييم المالي للمخزون
    constraint PK_DimProduct primary key clustered (item_code) --> Primary Key المفتاح الأساسي
);
go

-- ******************************************************
--                 2. Fact Tables - Sales
-- ******************************************************

--1) جدول فواتير المبيعات الرئيسية
---------------------------------------------
if object_id('dbo.FactSalesInvoice', 'U') is not null drop table dbo.FactSalesInvoice;
go

create table dbo.FactSalesInvoice (
    invoice_no int not null, --> رقم فاتورة المبيعات
    counter int null,
    invoice_date date not null, --> تاريخ الفاتورة
    order_time time null, --> توقيت إجراء الفاتورة
    order_hour int null, --> ساعة اليوم من 0 إلى 23
    order_year int null, --> سنة الفاتورة
    order_month int null, --> شهر الفاتورة
    order_day_name nvarchar(20) null, --> اسم يوم الأسبوع
    is_weekend bit not null constraint DF_FactSalesInvoice_is_weekend default (0), --> bit بيقبل 1 أو 0 لو ويك إند
    acct_no int null, --> رقم حساب العميل
    account_name nvarchar(255) null,
    customer_type nvarchar(50) not null, --> شريحة ونوع العميل
    internal_account_status nvarchar(20) not null constraint DF_FactSalesInvoice_internal_status default ('none'),
    is_internal_account bit not null constraint DF_FactSalesInvoice_is_internal default (0),
    is_retail_sale bit not null constraint DF_FactSalesInvoice_is_retail default (0),
    payment_method nvarchar(50) null, --> طريقة الدفع (كاش، فيزا...)
    total_qty decimal(18, 4) not null, --> إجمالي عدد القطع المباعة في الفاتورة
    total_discount decimal(18, 4) not null constraint DF_FactSalesInvoice_total_discount default (0), --> إجمالي الخصم
    final_total decimal(18, 4) not null, --> القيمة الصافية النهائية للفاتورة
    profit decimal(18, 4) not null, --> مجمل ربح الفاتورة
    cash_drawer decimal(18, 4) null,
    credit_card decimal(18, 4) null,
    treasury decimal(18, 4) null,
    paid_cash decimal(18, 4) null,
    deferred decimal(18, 4) null,
    due decimal(18, 4) null,
    warehouse nvarchar(100) null,
    added_by nvarchar(100) null,
    constraint PK_FactSalesInvoice primary key clustered (invoice_no), --> Primary Key المفتاح الأساسي للفواتير
    constraint FK_FactSalesInvoice_DimAccount foreign key (acct_no) references dbo.DimAccount(acct_no) --> ربط الفاتورة بالحساب Foreign Key
);
go

--2) جدول بنود وتفاصيل فواتير المبيعات
---------------------------------------------
if object_id('dbo.FactSalesItem', 'U') is not null drop table dbo.FactSalesItem;
go

create table dbo.FactSalesItem (
    sales_item_id int identity(1, 1) not null, --> identity(زود كام كل مره , أبدا من كام )
    invoice_no int not null, --> رقم الفاتورة التابع لها البند
    invoice_row_index int null,
    item_code int not null, --> كود الصنف المباع
    item_name nvarchar(500) not null,
    available_qty decimal(18, 4) null,
    qty decimal(18, 4) not null, --> الكمية المباعة من الصنف في هذا السطر
    price decimal(18, 4) not null, --> سعر بيع الوحدة
    discount decimal(18, 4) not null constraint DF_FactSalesItem_discount default (0),
    profit decimal(18, 4) not null, --> ربح السطر
    line_final decimal(18, 4) not null, --> إجمالي قيمة السطر بعد الخصم
    unit_cost decimal(18, 4) null, --> تكلفة شراء الوحدة
    constraint PK_FactSalesItem primary key clustered (sales_item_id), --> Primary Key المفتاح الأساسي للبند
    constraint FK_FactSalesItem_FactSalesInvoice foreign key (invoice_no) references dbo.FactSalesInvoice(invoice_no), --> ربط البند برأس الفاتورة
    constraint FK_FactSalesItem_DimProduct foreign key (item_code) references dbo.DimProduct(item_code) --> ربط البند بكود الصنف في الكتالوج
);
go

-- ******************************************************
--               3. Fact Tables - Purchases
-- ******************************************************

--1) جدول فواتير المشتريات والتوريدات الرئيسية
---------------------------------------------
if object_id('dbo.FactPurchaseInvoice', 'U') is not null drop table dbo.FactPurchaseInvoice;
go

create table dbo.FactPurchaseInvoice (
    invoice_no int not null, --> رقم فاتورة الشراء
    counter int null,
    purchase_date date not null, --> تاريخ أمر الشراء والتوريد
    purchase_time time null,
    acct_no int null, --> رقم حساب المورد
    account_name nvarchar(255) null,
    payment_method nvarchar(50) null,
    total_qty decimal(18, 4) not null, --> إجمالي عدد القطع المشتراة
    total_discount decimal(18, 4) not null constraint DF_FactPurchaseInvoice_total_discount default (0),
    final_total decimal(18, 4) not null, --> إجمالي قيمة فاتورة الشراء
    cash_drawer decimal(18, 4) null,
    paid_cash decimal(18, 4) null,
    deferred decimal(18, 4) null,
    due decimal(18, 4) null,
    warehouse nvarchar(100) null,
    added_by nvarchar(100) null,
    constraint PK_FactPurchaseInvoice primary key clustered (invoice_no), --> Primary Key المفتاح الأساسي لفواتير الشراء
    constraint FK_FactPurchaseInvoice_DimAccount foreign key (acct_no) references dbo.DimAccount(acct_no) --> ربط الفاتورة بجدول الحسابات للموردين
);
go

--2) جدول بنود وتفاصيل فواتير المشتريات
---------------------------------------------
if object_id('dbo.FactPurchaseItem', 'U') is not null drop table dbo.FactPurchaseItem;
go

create table dbo.FactPurchaseItem (
    purchase_item_id int identity(1, 1) not null, --> identity(زود كام كل مره , أبدا من كام )
    invoice_no int not null, --> رقم فاتورة الشراء
    invoice_row_index int null,
    item_code int not null, --> كود الصنف المورد
    item_name nvarchar(500) not null,
    available_qty decimal(18, 4) null,
    qty decimal(18, 4) not null, --> كمية الشراء
    price decimal(18, 4) not null, --> سعر شراء الوحدة
    discount decimal(18, 4) not null constraint DF_FactPurchaseItem_discount default (0),
    line_final decimal(18, 4) not null, --> إجمالي قيمة بند الشراء
    constraint PK_FactPurchaseItem primary key clustered (purchase_item_id), --> Primary Key المفتاح الأساسي لبند الشراء
    constraint FK_FactPurchaseItem_FactPurchaseInvoice foreign key (invoice_no) references dbo.FactPurchaseInvoice(invoice_no), --> ربط البند بفاتورة الشراء
    constraint FK_FactPurchaseItem_DimProduct foreign key (item_code) references dbo.DimProduct(item_code) --> ربط البند بالكتالوج
);
go

-- ******************************************************
--              4. Fact Tables - Sales Returns
-- ******************************************************

--1) جدول فواتير مرتجعات المبيعات الرئيسية
---------------------------------------------
if object_id('dbo.FactSalesReturnInvoice', 'U') is not null drop table dbo.FactSalesReturnInvoice;
go

create table dbo.FactSalesReturnInvoice (
    return_invoice_no int not null, --> رقم إشعار أو فاتورة المرتجع
    counter int null,
    return_date date not null, --> تاريخ إجراء المرتجع
    return_time time null,
    return_year int null,
    return_month int null,
    return_day_name nvarchar(20) null,
    original_invoice_no int null, --> رقم فاتورة البيع الأصلية إن وجدت
    acct_no int null, --> رقم حساب العميل
    account_name nvarchar(255) null,
    payment_method nvarchar(50) null,
    total_qty decimal(18, 4) not null, --> إجمالي القطع المرتجعة
    total_discount decimal(18, 4) not null constraint DF_FactSalesReturnInvoice_total_discount default (0),
    final_total decimal(18, 4) not null, --> إجمالي قيمة المرتجع بالسالب
    profit decimal(18, 4) not null, --> الأثر على الربح بالسالب
    cash_drawer decimal(18, 4) null,
    warehouse nvarchar(100) null,
    constraint PK_FactSalesReturnInvoice primary key clustered (return_invoice_no), --> Primary Key المفتاح الأساسي لفواتير المرتجعات
    constraint FK_FactSalesReturnInvoice_DimAccount foreign key (acct_no) references dbo.DimAccount(acct_no) --> ربط المرتجع بالحساب
);
go

--2) جدول بنود وتفاصيل فواتير المرتجعات
---------------------------------------------
if object_id('dbo.FactSalesReturnItem', 'U') is not null drop table dbo.FactSalesReturnItem;
go

create table dbo.FactSalesReturnItem (
    return_item_id int identity(1, 1) not null, --> identity(زود كام كل مره , أبدا من كام )
    return_invoice_no int not null, --> رقم فاتورة المرتجع
    invoice_row_index int null,
    item_code int not null, --> كود الصنف المرتجع
    item_name nvarchar(500) not null,
    available_qty decimal(18, 4) null,
    qty decimal(18, 4) not null, --> كمية المرتجع
    price decimal(18, 4) not null, --> سعر القطعة عند الإرجاع
    discount decimal(18, 4) not null constraint DF_FactSalesReturnItem_discount default (0),
    profit decimal(18, 4) not null, --> أثر الربح المسترد بالسالب
    line_final decimal(18, 4) not null, --> إجمالي قيمة البند المرتجع
    constraint PK_FactSalesReturnItem primary key clustered (return_item_id), --> Primary Key المفتاح الأساسي لبند المرتجع
    constraint FK_FactSalesReturnItem_FactSalesReturnInvoice foreign key (return_invoice_no) references dbo.FactSalesReturnInvoice(return_invoice_no), --> ربط البند بفاتورة المرتجع
    constraint FK_FactSalesReturnItem_DimProduct foreign key (item_code) references dbo.DimProduct(item_code) --> ربط البند بكتالوج الأصناف
);
go
