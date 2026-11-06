-- *****************************************************************************
-- 03_create_indexes.sql
-- فهارس تحسين أداء استعلامات التقارير والتحليلات لقاعدة بيانات cosmetics_store
-- *****************************************************************************

use cosmetics_store;
go

-- 1. فهرس فواتير المبيعات: تسريع الفلترة بالتاريخ ونطاق التجزئة (FactSalesInvoice)
if exists (select 1 from sys.indexes where name = 'IX_FactSalesInvoice_Date_Retail' and object_id = object_id('dbo.FactSalesInvoice'))
    drop index IX_FactSalesInvoice_Date_Retail on dbo.FactSalesInvoice;
create nonclustered index IX_FactSalesInvoice_Date_Retail
    on dbo.FactSalesInvoice (invoice_date, is_retail_sale) --> مفاتيح الفهرسة الأساسية للبحث الزمني وفلترة التجزئة
    include (final_total, profit, total_qty, acct_no, sale_type); --> include لتضمين الأعمدة المالية وتجنب Key Lookup
go

-- 2. فهرس فواتير المبيعات: تسريع تحليل حسابات وسلوكيات العملاء (FactSalesInvoice)
if exists (select 1 from sys.indexes where name = 'IX_FactSalesInvoice_Account' and object_id = object_id('dbo.FactSalesInvoice'))
    drop index IX_FactSalesInvoice_Account on dbo.FactSalesInvoice;
create nonclustered index IX_FactSalesInvoice_Account
    on dbo.FactSalesInvoice (acct_no, is_retail_sale) --> تسريع تجميع مشتريات الحسابات المسجلة
    include (final_total, profit, invoice_date);
go

-- 3. فهرس بنود المبيعات: تسريع ربط الفواتير وتحليل مبيعات الأصناف (FactSalesItem)
if exists (select 1 from sys.indexes where name = 'IX_FactSalesItem_Item_Invoice' and object_id = object_id('dbo.FactSalesItem'))
    drop index IX_FactSalesItem_Item_Invoice on dbo.FactSalesItem;
create nonclustered index IX_FactSalesItem_Item_Invoice
    on dbo.FactSalesItem (item_code, invoice_no) --> تسريع حساب إجمالي الكميات والإيرادات لكل صنف
    include (qty, line_final, profit);
go

-- 4. فهرس فواتير مرتجع المبيعات: تسريع تجميع المرتجعات زمنياً (FactSalesReturnInvoice)
if exists (select 1 from sys.indexes where name = 'IX_FactSalesReturnInvoice_Date' and object_id = object_id('dbo.FactSalesReturnInvoice'))
    drop index IX_FactSalesReturnInvoice_Date on dbo.FactSalesReturnInvoice;
create nonclustered index IX_FactSalesReturnInvoice_Date
    on dbo.FactSalesReturnInvoice (return_date, is_retail_sale) --> تسريع حساب صافي المبيعات لكل شهر
    include (final_total, profit, original_invoice_no);
go

-- 5. فهرس بنود مرتجع المبيعات: تسريع حساب نسب ومبالغ الأصناف المستردة (FactSalesReturnItem)
if exists (select 1 from sys.indexes where name = 'IX_FactSalesReturnItem_Item' and object_id = object_id('dbo.FactSalesReturnItem'))
    drop index IX_FactSalesReturnItem_Item on dbo.FactSalesReturnItem;
create nonclustered index IX_FactSalesReturnItem_Item
    on dbo.FactSalesReturnItem (item_code, return_invoice_no) --> تسريع ربط المرتجع بكتالوج الأصناف
    include (qty, line_final, profit);
go

-- 6. فهرس بنود المشتريات: تسريع تتبع التوريدات وحركات الأصناف (FactPurchaseItem)
if exists (select 1 from sys.indexes where name = 'IX_FactPurchaseItem_Item' and object_id = object_id('dbo.FactPurchaseItem'))
    drop index IX_FactPurchaseItem_Item on dbo.FactPurchaseItem;
create nonclustered index IX_FactPurchaseItem_Item
    on dbo.FactPurchaseItem (item_code, invoice_no) --> تسريع حساب كميات وتكلفة توريد كل صنف
    include (qty, line_final);
go
