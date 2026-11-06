-- *****************************************************************************
-- 01_monthly_financial_trends.sql
-- تقرير الاتجاهات المالية الشهرية لصافي مبيعات التجزئة والتسوية مع دفاتر المحاسبة
-- *****************************************************************************

use cosmetics_store;
go

-- 1) تحليل الاتجاهات الشهرية للمبيعات والأرباح والمرتجعات الصافية
--------------------------------------------------------------------------------
with MonthlyRetailSales as ( --> CTE جدول مؤقت بنجمع فيه مبيعات التجزئة الفعلية لكل شهر
    select 
        d.year_month as [YearMonth], --> صيغة السنة والشهر YYYY-MM
        max(d.days_in_month) as [DaysInMonth], --> إجمالي عدد أيام الشهر في التقويم
        count(distinct i.invoice_date) as [TradingDays], --> عدد أيام البيع الفعلية للمحل
        count(i.invoice_no) as [RetailInvoicesCount], --> عدد فواتير التجزئة في الشهر
        sum(i.final_total) as [RetailGrossSales], --> إجمالي مبيعات التجزئة قبل خصم المرتجعات
        sum(i.profit) as [RetailGrossProfit] --> إجمالي مجمل أرباح التجزئة
    from dbo.FactSalesInvoice i
    join dbo.DimDate d on d.full_date = i.invoice_date --> ربط الفاتورة بجدول التقويم الزمني
    where i.is_retail_sale = 1 --> فلترة مبيعات التجزئة فقط واستبعاد المسحوبات والتسويات
    group by d.year_month
),
MonthlyGrossBookSales as ( --> CTE بنحسب فيه إجمالي مبيعات الدفاتر كلها للمقارنة والمطابقة
    select 
        d.year_month as [YearMonth],
        count(i.invoice_no) as [TotalBookInvoicesCount], --> إجمالي كل فواتير الدفاتر
        sum(i.final_total) as [TotalBookGrossSales], --> إجمالي مبيعات الدفاتر الكاملة
        sum(i.profit) as [TotalBookGrossProfit] --> إجمالي أرباح الدفاتر
    from dbo.FactSalesInvoice i
    join dbo.DimDate d on d.full_date = i.invoice_date
    group by d.year_month
),
MonthlyReturns as ( --> CTE بنحسب فيه مرتجعات مبيعات التجزئة لكل شهر
    select 
        d.year_month as [YearMonth],
        count(r.return_invoice_no) as [ReturnOrdersCount], --> عدد فواتير المرتجع
        abs(sum(r.final_total)) as [ReturnsAmount], --> abs لتحويل قيمة المرتجع من سالب لموجب لسهولة العرض
        abs(sum(r.profit)) as [ReturnsProfitImpact] --> الأثر المالي للمرتجع على الأرباح
    from dbo.FactSalesReturnInvoice r
    join dbo.DimDate d on d.full_date = r.return_date
    where r.is_retail_sale = 1 --> مرتجعات زبائن التجزئة
    group by d.year_month
)
select 
    rs.[YearMonth] as [YearMonth], --> الشهر والسنة
    case 
        when rs.[TradingDays] < 0.8 * rs.[DaysInMonth] then 'Partial Month' --> تمييز الشهور الجزئية (نوفمبر 2025 وسبتمبر 2026) ديناميكياً
        else 'Full Month' --> الشهور التشغيلية الكاملة
    end as [OperatingStatus],
    rs.[TradingDays] as [TradingDays], --> عدد أيام العمل
    rs.[RetailInvoicesCount] as [RetailOrders], --> عدد فواتير التجزئة
    rs.[RetailGrossSales] as [RetailGrossSales], --> مبيعات التجزئة قبل المرتجع
    isnull(mr.[ReturnsAmount], 0) as [ReturnsValue], --> قيمة المرتجعات (0 لو مفيش مرتجع)
    rs.[RetailGrossSales] - isnull(mr.[ReturnsAmount], 0) as [RetailNetSales], --> صافي مبيعات التجزئة بعد خصم المرتجعات (~902K إجمالي)
    rs.[RetailGrossProfit] - isnull(mr.[ReturnsProfitImpact], 0) as [RetailNetProfit], --> صافي أرباح التجزئة الفعلية (~192.5K إجمالي)
    round(100.0 * (rs.[RetailGrossProfit] - isnull(mr.[ReturnsProfitImpact], 0))
          / nullif(rs.[RetailGrossSales] - isnull(mr.[ReturnsAmount], 0), 0), 2) as [RetailNetMarginPct], --> هامش الربح الصافي الفعلي (21.35%)
    round(rs.[RetailGrossSales] / nullif(rs.[RetailInvoicesCount], 0), 2) as [AverageTicketValue], --> متوسط قيمة الفاتورة AOV
    round((rs.[RetailGrossSales] - isnull(mr.[ReturnsAmount], 0)) / nullif(rs.[TradingDays], 0), 2) as [DailyNetSalesRate], --> معدل مبيعات اليوم الواحد
    gs.[TotalBookGrossSales] as [Reconciliation_GrossBookSales], --> رقم الدفاتر المحاسبية (978K) للتسوية
    gs.[TotalBookGrossSales] - rs.[RetailGrossSales] as [Reconciliation_NonRetailExcluded] --> الحركات غير التشغيلية المستبعدة (62.4K)
from MonthlyRetailSales rs
left join MonthlyReturns mr on rs.[YearMonth] = mr.[YearMonth] --> ربط المبيعات بالمرتجعات لنفس الشهر
left join MonthlyGrossBookSales gs on rs.[YearMonth] = gs.[YearMonth] --> ربط مبيعات التجزئة بمبيعات الدفاتر
order by rs.[YearMonth]; --> ترتيب الشهور تصاعدياً من الأقدم للأحدث
go
