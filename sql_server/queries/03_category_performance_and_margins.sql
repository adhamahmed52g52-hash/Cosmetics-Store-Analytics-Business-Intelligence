-- *****************************************************************************
-- 03_category_performance_and_margins.sql
-- تقرير أداء أقسام المنتجات وهوامش الربحية والتصنيف المزدوج (Category & Scope)
-- *****************************************************************************

use cosmetics_store;
go

-- 1) أداء الأقسام التجميلية الرئيسية لصافي مبيعات التجزئة (بعد خصم المرتجعات)
--------------------------------------------------------------------------------
with CategoryMetrics as ( --> CTE بنجمع فيه أداء كل قسم تجميلي من أسطر المبيعات والمرتجع الموحدة
    select 
        f.product_category as [Category], --> اسم القسم التجميلي
        count(distinct f.doc_no) as [DistinctInvoicesCount], --> عدد الفواتير الفريدة التي اشترت من هذا القسم
        sum(f.qty_signed) as [NetUnitsSold], --> صافي عدد القطع المباعة بعد خصم المرتجع
        sum(f.revenue_signed) as [NetRevenue], --> صافي إيراد القسم بعد خصم المرتجع
        sum(f.profit_signed) as [NetProfit] --> صافي أرباح القسم بعد خصم المرتجع
    from dbo.vw_FactSalesLines f
    where f.is_retail_sale = 1 --> مبيعات التجزئة فقط
    group by f.product_category
),
TotalRetail as ( --> CTE إجمالي مبيعات المتجر الصافية لحساب الحصص النسبية
    select sum(revenue_signed) as [TotalRetailRevenue]
    from dbo.vw_FactSalesLines
    where is_retail_sale = 1
)
select 
    c.[Category] as [ProductCategory], --> القسم التجميلي
    c.[DistinctInvoicesCount] as [DistinctOrders], --> عدد الفواتير التي اشترت من القسم
    c.[NetUnitsSold] as [NetUnitsSold], --> صافي القطع المباعة
    c.[NetRevenue] as [NetRevenue], --> صافي إيراد القسم بالجنيه
    round(c.[NetRevenue] / nullif(t.[TotalRetailRevenue], 0) * 100.0, 2) as [RevenueContributionPct], --> مساهمة القسم في إجمالي مبيعات المحل
    c.[NetProfit] as [NetProfit], --> صافي أرباح القسم بالجنيه
    round(c.[NetProfit] / nullif(c.[NetRevenue], 0) * 100.0, 2) as [ProfitMarginPct], --> نسبة مجمل الربح للقسم
    round(c.[NetRevenue] / nullif(c.[NetUnitsSold], 0), 2) as [AveragePricePerUnit] --> متوسط سعر بيع القطعة في هذا القسم
from CategoryMetrics c
cross join TotalRetail t
order by c.[NetRevenue] desc; --> ترتيب الأقسام من الأكثر إيراداً للأقل
go

-- 2) تحليل نطاقات المنتجات (Product Scope) والمخزون والنشاط البيعي
--------------------------------------------------------------------------------
with CatalogScopeMetrics as ( --> CTE بنحسب فيه عدد الأصناف وقيمة المخزون لكل نطاق بالكتالوج
    select 
        product_scope as [ProductScope], --> نطاق المنتج (Beauty, Fashion, Personal Care, Packaging)
        count(item_code) as [TotalCatalogSKUs], --> إجمالي عدد أصناف الكتالوج
        sum(stock_cost_valuation) as [InventoryCostValuation] --> إجمالي قيمة المخزون الحالي بالتكلفة
    from dbo.DimProduct
    group by product_scope
),
SalesScopeMetrics as ( --> CTE بنجمع فيه المبيعات الفعلية لكل نطاق منتجات
    select 
        f.product_scope as [ProductScope],
        count(distinct f.item_code) as [ActiveSellingSKUs], --> عدد الأصناف التي بيع منها بالفعل
        sum(f.qty_signed) as [NetUnitsSold], --> صافي عدد القطع المباعة
        sum(f.revenue_signed) as [NetRevenue], --> صافي الإيراد
        sum(f.profit_signed) as [NetProfit] --> صافي الربح
    from dbo.vw_FactSalesLines f
    where f.is_retail_sale = 1
    group by f.product_scope
)
select 
    cs.[ProductScope] as [ProductScope], --> نطاق المنتجات
    cs.[TotalCatalogSKUs] as [CatalogSKUCount], --> عدد الأصناف المسجلة في الكتالوج
    isnull(ss.[ActiveSellingSKUs], 0) as [ActiveSellingSKUs], --> عدد الأصناف النشطة بيعياً
    round(isnull(ss.[ActiveSellingSKUs], 0) * 100.0 / nullif(cs.[TotalCatalogSKUs], 0), 2) as [AssortmentUtilizationPct], --> نسبة استغلال الكتالوج
    isnull(ss.[NetUnitsSold], 0) as [NetUnitsSold], --> صافي القطع المباعة
    isnull(ss.[NetRevenue], 0) as [NetRevenue], --> صافي الإيراد
    isnull(ss.[NetProfit], 0) as [NetProfit], --> صافي الربح
    round(isnull(ss.[NetProfit], 0) / nullif(ss.[NetRevenue], 0) * 100.0, 2) as [ProfitMarginPct], --> هامش الربح للنطاق
    cs.[InventoryCostValuation] as [InventoryValuationAtCost] --> قيمة رأس المال المجمد في المخزون
from CatalogScopeMetrics cs
left join SalesScopeMetrics ss on cs.[ProductScope] = ss.[ProductScope]
order by NetRevenue desc;
go
