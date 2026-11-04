-- ******************************************************
--                         CTE
-- ******************************************************

use cosmetics_store;
go

--1) أداء أقسام المنتجات Category والإيرادات وهوامش الربح
---------------------------------------------
with CategoryMetrics as ( --> CTE بنجمع فيه أداء كل قسم من بنود المبيعات
    select 
        p.product_category as [Category],
        count(distinct s.invoice_no) as [DistinctInvoices], --> Distinct عشان نعد الفواتير الفريدة اللي اشترت من القسم ده بدون تكرار
        sum(s.qty) as [UnitsSold],
        sum(s.line_final) as [CategoryRevenue],
        sum(s.profit) as [CategoryProfit]
    from dbo.FactSalesItem as s
    inner join dbo.DimProduct as p
        on s.item_code = p.item_code --> ربط بند المبيعات بكتالوج الأصناف
    group by p.product_category
),
TotalSales as (
    select sum(line_final) as [OverallRevenue] from dbo.FactSalesItem
)
select 
    c.[Category],
    c.[DistinctInvoices],
    c.[UnitsSold],
    c.[CategoryRevenue],
    round(c.[CategoryRevenue] / t.[OverallRevenue] * 100.0, 2) as [RevenueSharePct],
    c.[CategoryProfit],
    round(c.[CategoryProfit] / nullif(c.[CategoryRevenue], 0) * 100.0, 2) as [ProfitMarginPct],
    round(c.[CategoryRevenue] / nullif(c.[UnitsSold], 0), 2) as [AvgPricePerUnit] --> متوسط سعر بيع القطعة في القسم
from CategoryMetrics as c
cross join TotalSales as t
order by c.[CategoryRevenue] desc;
go

---------------------------------------------
--2) تحليل نطاقات المنتجات Product Scope والمبيعات والكتالوج
---------------------------------------------
with CatalogScope as ( --> CTE بنحسب فيه عدد أصناف الكتالوج لكل نطاق
    select 
        product_scope as [ProductScope],
        count(item_code) as [CatalogSKUs]
    from dbo.DimProduct
    group by product_scope
),
SoldItems as ( --> CTE بنجمع فيه المبيعات الفعلية لكل نطاق
    select 
        p.product_scope as [ProductScope],
        count(distinct s.item_code) as [ActiveSoldSKUs],
        sum(s.qty) as [UnitsSold],
        sum(s.line_final) as [ScopeRevenue],
        sum(s.profit) as [ScopeProfit]
    from dbo.FactSalesItem as s
    inner join dbo.DimProduct as p
        on s.item_code = p.item_code
    group by p.product_scope
),
TotalStoreSales as (
    select sum(line_final) as [TotalRevenue] from dbo.FactSalesItem
)
select 
    c.[ProductScope],
    c.[CatalogSKUs],
    isnull(s.[ActiveSoldSKUs], 0) as [ActiveSoldSKUs],
    isnull(s.[UnitsSold], 0) as [UnitsSold],
    isnull(s.[ScopeRevenue], 0) as [ScopeRevenue],
    round(isnull(s.[ScopeRevenue], 0) / t.[TotalRevenue] * 100.0, 2) as [RevenueSharePct],
    isnull(s.[ScopeProfit], 0) as [ScopeProfit],
    round(isnull(s.[ScopeProfit], 0) / nullif(s.[ScopeRevenue], 0) * 100.0, 2) as [MarginPct]
from CatalogScope as c
left join SoldItems as s
    on c.[ProductScope] = s.[ProductScope] --> left join عشان نجيب كل نطاقات الكتالوج حتى لو متباعتش
cross join TotalStoreSales as t
order by ScopeRevenue desc;
go
