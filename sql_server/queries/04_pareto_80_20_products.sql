-- *****************************************************************************
-- 04_pareto_80_20_products.sql
-- تحليل باريتو (قاعدة 80/20) وتصنيف الأصناف حسب مساهمتها في صافي مبيعات التجزئة
-- *****************************************************************************

use cosmetics_store;
go

-- 1) تصنيف الأصناف التراكمي وتحديد الفئات الثلاث A و B و C
--------------------------------------------------------------------------------
with ProductSalesSummary as ( --> CTE بنجمع فيه صافي مبيعات وأرباح كل صنف في المحل
    select 
        f.item_code as [ItemCode], --> كود الصنف
        f.item_name as [ItemName], --> اسم الصنف
        f.product_category as [Category], --> قسم الصنف
        f.product_scope as [Scope], --> نطاق الصنف
        sum(f.qty_signed) as [NetUnitsSold], --> صافي عدد القطع المباعة
        sum(f.revenue_signed) as [NetRevenue], --> صافي إيراد الصنف
        sum(f.profit_signed) as [NetProfit] --> صافي أرباح الصنف
    from dbo.vw_FactSalesLines f
    where f.is_retail_sale = 1 --> مبيعات التجزئة فقط
    group by f.item_code, f.item_name, f.product_category, f.product_scope
),
RankedProductsList as ( --> CTE حساب الترتيب التنازلي والمجموع التراكمي للإيرادات
    select 
        ps.*,
        sum(case when ps.[NetRevenue] > 0 then ps.[NetRevenue] else 0 end)
            over (order by ps.[NetRevenue] desc, ps.[ItemCode]
                  rows between unbounded preceding and current row) as [CumulativeRevenue], --> الإيراد التراكمي من أول صنف حتى الصنف الحالي
        sum(case when ps.[NetRevenue] > 0 then ps.[NetRevenue] else 0 end) over () as [TotalRetailRevenue], --> إجمالي مبيعات كل الأصناف
        count(*) over () as [TotalSellingSKUsCount], --> إجمالي عدد الأصناف التي بيعت
        row_number() over (order by ps.[NetRevenue] desc) as [RevenueRank] --> ترتيب الصنف من 1 إلى N حسب الإيراد
    from ProductSalesSummary ps
)
select 
    rp.[ItemCode] as [ItemCode], --> كود الصنف
    rp.[ItemName] as [ItemName], --> اسم الصنف
    rp.[Category] as [ProductCategory], --> قسم المنتج
    rp.[Scope] as [ProductScope], --> نطاق المنتج
    rp.[NetUnitsSold] as [NetUnitsSold], --> صافي القطع المباعة
    rp.[NetRevenue] as [NetRevenue], --> صافي الإيراد
    rp.[NetProfit] as [NetProfit], --> صافي الربح
    round(rp.[NetProfit] / nullif(rp.[NetRevenue], 0) * 100.0, 2) as [ProfitMarginPct], --> هامش ربح الصنف
    rp.[RevenueRank] as [RevenueRank], --> ترتيب الصنف في الإيرادات
    round(rp.[RevenueRank] * 100.0 / nullif(rp.[TotalSellingSKUsCount], 0), 2) as [SKUCumulativePct], --> النسبة المئوية لترتيب الصنف من إجمالي عدد الأصناف
    round(rp.[CumulativeRevenue] * 100.0 / nullif(rp.[TotalRetailRevenue], 0), 2) as [CumulativeRevenuePct], --> النسبة المئوية التراكمية للإيراد
    case 
        when rp.[CumulativeRevenue] <= 0.80 * rp.[TotalRetailRevenue] then 'Class A (Top 80% Revenue)' --> فئة A: أهم أصناف تولد أول 80% من المبيعات
        when rp.[CumulativeRevenue] <= 0.95 * rp.[TotalRetailRevenue] then 'Class B (Next 15% Revenue)' --> فئة B: أصناف متوسطة تولد الـ 15% التالية
        else 'Class C (Tail 5% Revenue)' --> فئة C: أصناف ضعيفة تولد آخر 5% فقط
    end as [ParetoClass] --> تصنيف باريتو
from RankedProductsList rp
order by rp.[NetRevenue] desc; --> عرض الأصناف من الأعلى إيراداً للأسفل
go
