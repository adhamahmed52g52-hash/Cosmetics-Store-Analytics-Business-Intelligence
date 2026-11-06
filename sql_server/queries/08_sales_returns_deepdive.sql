-- *****************************************************************************
-- 08_sales_returns_deepdive.sql
-- تقرير تحليل مرتجعات المبيعات والتحقق من نسبة الاسترداد وتتبع الفواتير الأصلية
-- *****************************************************************************

use cosmetics_store;
go

-- 1) مؤشر معدل الاسترداد المالي المعتمد لمرتجعات التجزئة (Return Rate KPI)
--------------------------------------------------------------------------------
select 
    (select sum(final_total) from dbo.FactSalesInvoice where is_retail_sale = 1) as [RetailGrossSales], --> إجمالي مبيعات التجزئة (915.7 ألف)
    (select abs(sum(final_total)) from dbo.FactSalesReturnInvoice where is_retail_sale = 1) as [TotalReturnsValue], --> إجمالي قيمة المرتجعات (13.7 ألف)
    (select sum(final_total) from dbo.FactSalesInvoice where is_retail_sale = 1)
        - (select abs(sum(final_total)) from dbo.FactSalesReturnInvoice where is_retail_sale = 1) as [RetailNetSales], --> صافي مبيعات التجزئة (901.9 ألف)
    round((select abs(sum(final_total)) from dbo.FactSalesReturnInvoice where is_retail_sale = 1) / 
          nullif((select sum(final_total) from dbo.FactSalesInvoice where is_retail_sale = 1), 0) * 100.0, 2) as [AuditedRetailReturnRatePct], --> النسبة المعتمدة الصحيحة (1.50%)
    round((select abs(sum(final_total)) from dbo.FactSalesReturnInvoice) / 
          nullif((select sum(final_total) from dbo.FactSalesInvoice), 0) * 100.0, 2) as [UnfilteredBookReturnRatePct] --> النسبة المشوهة بدفاتر الحسابات (1.41%)
;
go

-- 2) تدقيق إمكانية تتبع المرتجعات وتفسير الـ 4 فواتير مرتجع غير المربوطة
--------------------------------------------------------------------------------
select 
    r.original_invoice_status as [TraceabilityStatus], --> حالة الربط بالفاتورة الأصلية
    count(r.return_invoice_no) as [ReturnsCount], --> عدد فواتير المرتجع في كل حالة
    round(count(r.return_invoice_no) * 100.0 / (select count(*) from dbo.FactSalesReturnInvoice), 2) as [ShareOfReturnsPct], --> نسبة فواتير المرتجع
    abs(sum(r.final_total)) as [RefundValueEGP], --> إجمالي المبالغ المستردة للزبائن
    abs(sum(r.profit)) as [ProfitImpactEGP] --> الأثر السلبي على الأرباح
from dbo.FactSalesReturnInvoice r
group by r.original_invoice_status
order by [ReturnsCount] desc;
go

-- فحص تفصيلي للمرتجعات الأربعة غير المربوطة لتوضيح أسبابها في المناقشة
select 
    r.return_invoice_no as [ReturnInvoiceNo], --> رقم إشعار المرتجع
    r.return_date as [ReturnDate], --> تاريخ المرتجع
    r.original_invoice_no as [OriginalInvoiceNo_Source], --> رقم الفاتورة الأصلية كما ورد في المصدر
    r.original_invoice_status as [AuditExplanation], --> التفسير الرقابي للحالة
    abs(r.final_total) as [RefundAmountEGP], --> قيمة المبلغ المسترد
    r.account_name as [CustomerName] --> اسم العميل إن وجد
from dbo.FactSalesReturnInvoice r
where r.original_invoice_status <> N'Found in sales_invoices'; --> عزل الفواتير غير المربوطة فقط
go

-- 3) أعلى 10 أصناف تم إرجاعها واسترداد مبالغها من المحل
--------------------------------------------------------------------------------
select top 10
    r.item_code as [ItemCode], --> كود الصنف
    p.item_name as [ItemName], --> اسم الصنف
    p.product_category as [ProductCategory], --> قسم الصنف
    sum(r.qty) as [UnitsReturnedCount], --> إجمالي عدد القطع المرتجعة من هذا الصنف
    abs(sum(r.line_final)) as [TotalRefundValueEGP], --> إجمالي المبالغ المستردة لهذا الصنف
    abs(sum(r.profit)) as [ProfitLossImpactEGP], --> الأثر السلبي على أرباح الصنف
    dense_rank() over (order by abs(sum(r.line_final)) desc) as [RefundRank] --> ترتيب الأصناف حسب قيمة المبالغ المستردة
from dbo.FactSalesReturnItem r
left join dbo.DimProduct p on r.item_code = p.item_code
group by r.item_code, p.item_name, p.product_category
order by TotalRefundValueEGP desc;
go
