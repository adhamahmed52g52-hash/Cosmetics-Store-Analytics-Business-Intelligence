-- ******************************************************
--                        Indexes
-- ******************************************************

use cosmetics_store;
go

--1) فهارس جدول فواتير المبيعات FactSalesInvoice
---------------------------------------------
create nonclustered index IX_FactSalesInvoice_Date --> index لتسريع الفلترة والبحث حسب تاريخ الفاتورة
on dbo.FactSalesInvoice (invoice_date)
include (final_total, profit); --> include عشان يجيب المبيعات والربح بسرعة بدون ما يرجع للجدول الأصلي

create nonclustered index IX_FactSalesInvoice_Hour --> تسريع التجميع حسب ساعات اليوم
on dbo.FactSalesInvoice (order_hour)
include (final_total);

create nonclustered index IX_FactSalesInvoice_CustomerType --> تسريع تقارير شرائح العملاء
on dbo.FactSalesInvoice (customer_type)
include (final_total);

create nonclustered index IX_FactSalesInvoice_Account --> تسريع الاستعلامات الخاصة بالحسابات المسجلة
on dbo.FactSalesInvoice (acct_no)
include (final_total);

create nonclustered index IX_FactSalesInvoice_InternalStatus --> تسريع تصفية حسابات الشركاء والتسويات
on dbo.FactSalesInvoice (internal_account_status)
include (final_total);

--2) فهارس جدول بنود المبيعات FactSalesItem
---------------------------------------------
create nonclustered index IX_FactSalesItem_Invoice --> تسريع ربط البنود بالفاتورة
on dbo.FactSalesItem (invoice_no)
include (item_code, qty, line_final, profit);

create nonclustered index IX_FactSalesItem_Product --> تسريع تحليل مبيعات الأصناف والكميات
on dbo.FactSalesItem (item_code)
include (qty, line_final, profit);

--3) فهارس جدول كتالوج المنتجات DimProduct
---------------------------------------------
create nonclustered index IX_DimProduct_Category --> تسريع الفلترة والتجميع حسب قسم الصنف
on dbo.DimProduct (product_category)
include (item_name, sell_price, avg_purchase_price, stock_cost_valuation);

create nonclustered index IX_DimProduct_Scope --> تسريع تقارير نطاق المنتجات وتقييم المخزون
on dbo.DimProduct (product_scope)
include (product_category, item_name, stock_cost_valuation);

--4) فهارس جدول فواتير وبنود المشتريات
---------------------------------------------
create nonclustered index IX_FactPurchaseInvoice_Date --> تسريع البحث بتاريخ التوريد
on dbo.FactPurchaseInvoice (purchase_date)
include (final_total);

create nonclustered index IX_FactPurchaseItem_Invoice --> تسريع ربط بنود الشراء بالفاتورة
on dbo.FactPurchaseItem (invoice_no)
include (item_code, qty, line_final);

create nonclustered index IX_FactPurchaseItem_Product --> تسريع متابعة أسعار وتوريدات الأصناف
on dbo.FactPurchaseItem (item_code)
include (qty, line_final);

--5) فهارس جدول فواتير وبنود المرتجعات
---------------------------------------------
create nonclustered index IX_FactSalesReturnInvoice_Date --> تسريع تقارير المرتجعات الشهرية
on dbo.FactSalesReturnInvoice (return_date)
include (final_total, profit);

create nonclustered index IX_FactSalesReturnItem_Invoice --> تسريع ربط بنود المرتجع بإشعار الإرجاع
on dbo.FactSalesReturnItem (return_invoice_no)
include (item_code, qty, line_final);
go
