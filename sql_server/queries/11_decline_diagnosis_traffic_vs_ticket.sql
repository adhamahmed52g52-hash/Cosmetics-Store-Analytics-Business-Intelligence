-- *****************************************************************************
-- 11_decline_diagnosis_traffic_vs_ticket.sql
-- تقرير التشخيص الجذري لانخفاض المبيعات: تفكيك حركة الزبائن (Traffic) مقابل سلة الشراء (Ticket)
-- يجاوب على سؤال المالك: هل المبيعات انخفضت بسبب الزبائن أم الأسعار أم حجم السلة؟
-- *****************************************************************************

use cosmetics_store;
go

-- 1) تفكيك مؤشرات المبيعات شهرياً لمعادلة التجزئة: Sales = Traffic x Ticket
--------------------------------------------------------------------------------
select 
    t.year_month as [YearMonth], --> صيغة الشهر والسنة
    t.trading_days as [TradingDays], --> عدد أيام العمل الفعلية في الشهر
    t.invoices as [TotalOrdersCount], --> إجمالي عدد فواتير التجزئة
    t.invoices_per_day as [DailyTraffic_InvoicesPerDay], --> متوسط عدد الفواتير يومياً (مؤشر إقبال الزبائن Traffic)
    t.avg_ticket as [AverageTicketValueEGP], --> متوسط قيمة الفاتورة AOV (مؤشر الإنفاق في الزيارة)
    t.units_per_invoice as [AverageBasketUnits], --> متوسط عدد القطع في كل فاتورة (مؤشر حجم السلة Basket Size)
    t.avg_unit_price as [AverageUnitPriceEGP], --> متوسط سعر بيع القطعة (مؤشر سياسة التسعير Pricing)
    t.distinct_products_sold as [DistinctSellingSKUs] --> عدد الأصناف المختلفة التي بيعت في الشهر
from dbo.vw_TrafficTicketMonthly t
order by t.year_month; --> ترتيب تسلسلي عبر الشهور
go

-- 2) جدول المقارنة الرقابي بين شهر الذروة الأساسي (ديسمبر 2025) وشهر القاع (أغسطس 2026)
--------------------------------------------------------------------------------
select 
    [DiagnosticMetricName], --> اسم المؤشر التشخيصي
    [Dec_2025_PeakValue], --> قيمة المؤشر في شهر الذروة (ديسمبر 2025)
    [Aug_2026_TroughValue], --> قيمة المؤشر في شهر القاع (أغسطس 2026)
    [AbsoluteChangeValue], --> قيمة التغير المطلق
    [PercentageChangeRate] --> نسبة التغير المئوية (%)
from (
    values
        ('Invoices per Trading Day (Footfall Traffic)', 29.3, 10.2, 10.2 - 29.3, round((10.2 - 29.3) / 29.3 * 100.0, 1)),
        ('Average Ticket Value EGP (Basket Spend)', 179.1, 132.6, 132.6 - 179.1, round((132.6 - 179.1) / 179.1 * 100.0, 1)),
        ('Units per Invoice (Basket Item Count)', 2.46, 1.80, 1.80 - 2.46, round((1.80 - 2.46) / 2.46 * 100.0, 1)),
        ('Average Unit Price EGP (Store Pricing)', 72.9, 73.7, 73.7 - 72.9, round((73.7 - 72.9) / 72.9 * 100.0, 1)),
        ('Distinct SKUs Sold Monthly (Assortment Active)', 628, 314, 314 - 628, round((314 - 628) * 100.0 / 628, 1))
) as DiagnosticTable([DiagnosticMetricName], [Dec_2025_PeakValue], [Aug_2026_TroughValue], [AbsoluteChangeValue], [PercentageChangeRate]);
go
