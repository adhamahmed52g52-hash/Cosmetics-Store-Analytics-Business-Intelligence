-- ******************************************************
--                         CTE
-- ******************************************************

use cosmetics_store;
go

--1) أعلى 15 منتج مبيعاً وإيراداً في المحل Hero Products
---------------------------------------------
select top 15
    s.item_code,
    s.item_name,
    p.product_category,
    sum(s.qty) as [UnitsSold],
    sum(s.line_final) as [TotalRevenue],
    sum(s.profit) as [TotalProfit],
    round(sum(s.profit) / nullif(sum(s.line_final), 0) * 100.0, 2) as [MarginPct],
    round(sum(s.line_final) / nullif(sum(s.qty), 0), 2) as [AvgSellingPrice] --> متوسط سعر بيع الوحدة للصنف
from dbo.FactSalesItem as s
inner join dbo.DimProduct as p
    on s.item_code = p.item_code
group by s.item_code, s.item_name, p.product_category
order by TotalRevenue desc;

---------------------------------------------
--2) فحص البضاعة الراكدة التي لم يباع منها أي قطعة ولها رصيد بالمخزن
---------------------------------------------
with UnsoldProducts as ( --> CTE بنصفي فيه المنتجات اللي ملهاش أي بيع وليها رصيد بالمخزن
    select 
        p.item_code,
        p.item_name,
        p.product_category,
        p.total_qty as [StockQty],
        p.sell_price,
        p.avg_purchase_price,
        p.stock_cost_valuation
    from dbo.DimProduct as p
    left join dbo.FactSalesItem as s
        on p.item_code = s.item_code
    where s.item_code is null --> مفيش أي مبيعات اتسجلت للصنف ده
      and p.total_qty > 0 --> رصيد المخزن موجب
)
select 
    product_category as [Category],
    count(item_code) as [UnsoldSKUCount],
    sum(StockQty) as [TiedUpUnits],
    sum(stock_cost_valuation) as [TiedUpCapitalEGP] --> رأس المال المعطل في الأصناف الراكدة
from UnsoldProducts
group by product_category
order by TiedUpCapitalEGP desc;
go
