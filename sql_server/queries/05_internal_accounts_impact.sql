-- *****************************************************************************
-- 05_internal_accounts_impact.sql
-- تدقيق الحسابات المسجلة والحركات غير التشغيلية المستبعدة وأثرها على النتائج المالية
-- *****************************************************************************

use cosmetics_store;
go

-- 1) توزيع مبيعات المتجر حسب نوع المعاملة وقنوات البيع
--------------------------------------------------------------------------------
select 
    s.sale_type as [TransactionType], --> نوع المعاملة (جمهور كاش، عميل مسجل، شريك، موظف، مصاريف، مورد)
    s.is_retail_sale as [IsRetailSale], --> هل هي مبيعات تجزئة فعلية معتمدة (1 نعم، 0 لا)
    count(s.invoice_no) as [InvoicesCount], --> عدد الفواتير
    round(count(s.invoice_no) * 100.0 / (select count(*) from dbo.FactSalesInvoice), 2) as [InvoicesSharePct], --> نسبة عدد الفواتير من الإجمالي
    sum(s.final_total) as [TotalRevenue], --> إجمالي القيمة بالجنيه
    round(sum(s.final_total) * 100.0 / (select sum(final_total) from dbo.FactSalesInvoice), 2) as [RevenueSharePct], --> نسبة المساهمة في إجمالي مبيعات الدفاتر
    round(avg(s.final_total), 2) as [AverageOrderValue], --> متوسط قيمة الفاتورة
    sum(s.profit) as [TotalProfit], --> مجمل الربح المحقق
    round(sum(s.profit) / nullif(sum(s.final_total), 0) * 100.0, 2) as [ProfitMarginPct] --> نسبة مجمل الربح
from dbo.FactSalesInvoice s
group by s.sale_type, s.is_retail_sale
order by s.is_retail_sale desc, TotalRevenue desc;
go

-- 2) تدقيق تفصيلي للـ 24 فاتورة غير التشغيلية المستبعدة بقيمة 62,482 ج.م
--------------------------------------------------------------------------------
select 
    s.sale_type as [NonRetailCategory], --> نوع الحركة المستبعدة
    s.acct_no as [AccountNo], --> رقم الحساب في الدليل
    isnull(a.acct_name, s.account_name) as [AccountName], --> اسم الحساب المسجل
    a.classification_rationale as [AuditRationale], --> توثيق سبب التصنيف والدليل المحاسبي للاستبعاد
    count(s.invoice_no) as [InvoicesCount], --> عدد الفواتير المستبعدة
    sum(s.final_total) as [ExcludedRevenue], --> القيمة المستبعدة من المبيعات
    sum(s.profit) as [ExcludedProfit], --> الأثر المستبعد من الأرباح
    round(sum(s.profit) / nullif(sum(s.final_total), 0) * 100.0, 2) as [ProfitMarginPct] --> هامش ربح الحركة
from dbo.FactSalesInvoice s
left join dbo.DimAccount a on s.acct_no = a.acct_no --> ربط الفاتورة بدليل الحسابات
where s.is_retail_sale = 0 --> فلترة الحركات غير التشغيلية فقط
group by s.sale_type, s.acct_no, a.acct_name, s.account_name, a.classification_rationale
order by ExcludedRevenue desc;
go

-- 3) جدول مقارنة الحساسية الرقابي: دفاتر المحاسبة الكاملة مقابل صافي نشاط التجزئة الفعلي
--------------------------------------------------------------------------------
select 
    [MetricName], --> اسم المؤشر المالي
    [GrossBookValue], --> القيمة بدفاتر المحاسبة قبل الاستبعاد (978K)
    [RetailNetValue], --> القيمة الصافية لنشاط التجزئة الفعلي بعد الاستبعاد والمرتجع (902K)
    [VarianceEGP], --> قيمة الفارق بالجنيه
    [VariancePct] --> نسبة الفارق المئوية
from (
    values
        ('Sales Revenue (EGP)', 978248.29, 901986.51, 978248.29 - 901986.51, round((978248.29 - 901986.51) / 978248.29 * 100.0, 2)),
        ('Gross Profit (EGP)', 198590.41, 192534.06, 198590.41 - 192534.06, round((198590.41 - 192534.06) / 198590.41 * 100.0, 2)),
        ('Profit Margin (%)', 20.30, 21.35, -1.05, -5.17)
) as ComparisonTable([MetricName], [GrossBookValue], [RetailNetValue], [VarianceEGP], [VariancePct]);
go
