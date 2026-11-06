-- *****************************************************************************
-- 12_stock_availability_and_restock_lift.sql
-- تقرير التشخيص الجذري لسلسلة الإمداد: انهيار توفر المخزون وأثر إعادة التوريد (Restock Lift)
-- يثبت بالأدلة الرياضية أن تراجع المبيعات نتج عن توقف الشراء ونفاد بضاعة الكتالوج
-- *****************************************************************************

use cosmetics_store;
go

-- 1) تتبع انهيار نسبة توفر بضاعة الكتالوج في المخزن شهرياً (من 98% إلى 63%)
--------------------------------------------------------------------------------
select 
    s.year_month as [YearMonth], --> الشهر والسنة
    s.catalogue_skus as [TotalActiveCatalogueSKUs], --> إجمالي أصناف الكتالوج النشطة
    s.in_stock_skus as [InStockAvailableSKUs], --> الأصناف المتوفرة برصيد موجب
    s.out_or_negative_skus as [OutOfStockOrNegativeSKUs], --> الأصناف النافدة تماماً أو السالبة
    s.pct_in_stock as [InStockAvailabilityPct] --> النسبة المئوية للأصناف المتوفرة للبيع
from dbo.vw_StockAvailabilityMonthly s
order by s.year_month; --> ترتيب تسلسلي
go

-- 2) التجربة الطبيعية لإعادة التوريد (Restock Lift Natural Experiment)
-- مقارنة مبيعات الـ 45 يوماً بعد الشراء مقابل الـ 45 يوماً السابقة لكل توريد شمل 20 صنفاً فأكثر
--------------------------------------------------------------------------------
with MajorRestockOrders as ( --> CTE حصر فواتير الشراء الكبرى التي شملت 20 صنفاً أو أكثر
    select distinct 
        pinv.invoice_no,
        pinv.purchase_date,
        count(distinct x.item_code) as [RestockedSKUCount] --> عدد الأصناف المختلفة التي تم توريدها في الفاتورة
    from dbo.FactPurchaseItem x
    join dbo.FactPurchaseInvoice pinv on pinv.invoice_no = x.invoice_no
    group by pinv.invoice_no, pinv.purchase_date
    having count(distinct x.item_code) >= 20 --> شرط أن تكون شحنة كبرى
),
RestockPerformanceComparison as ( --> CTE حساب مبيعات الأصناف الموردة في الـ 45 يوم قبل الشراء والـ 45 يوم بعد الشراء
    select 
        r.invoice_no,
        r.purchase_date,
        r.RestockedSKUCount,
        sum(case when i.invoice_date >= dateadd(day, -45, r.purchase_date) and i.invoice_date < r.purchase_date then s.line_final else 0 end) as [Pre45DaysSalesRevenue], --> مبيعات الـ 45 يوماً قبل وصول التوريد
        sum(case when i.invoice_date > r.purchase_date and i.invoice_date <= dateadd(day, 45, r.purchase_date) then s.line_final else 0 end) as [Post45DaysSalesRevenue] --> مبيعات الـ 45 يوماً بعد نزول البضاعة على الرف
    from MajorRestockOrders r
    join dbo.FactPurchaseItem pi on pi.invoice_no = r.invoice_no
    join dbo.FactSalesItem s on s.item_code = pi.item_code
    join dbo.FactSalesInvoice i on i.invoice_no = s.invoice_no
    where i.is_retail_sale = 1 --> مبيعات التجزئة فقط
    group by r.invoice_no, r.purchase_date, r.RestockedSKUCount
)
select 
    rs.purchase_date as [RestockExecutionDate], --> تاريخ استلام شحنة البضاعة
    rs.RestockedSKUCount as [SKUsRestockedCount], --> عدد الأصناف التي تم تغذيتها
    rs.Pre45DaysSalesRevenue as [Pre45DaysSalesEGP], --> المبيعات قبل التوريد (فترة الشح ونفاد البضاعة)
    rs.Post45DaysSalesRevenue as [Post45DaysSalesEGP], --> المبيعات بعد التوريد (فترة توفر البضاعة)
    round((rs.Post45DaysSalesRevenue - rs.Pre45DaysSalesRevenue) * 100.0 / nullif(rs.Pre45DaysSalesRevenue, 0), 1) as [SalesLiftGrowthPct] --> نسبة القفزة البيعية المتحققة بعد التوريد مباشرة
from RestockPerformanceComparison rs
order by rs.purchase_date; --> الترتيب الزمني لحركات التوريد
go
