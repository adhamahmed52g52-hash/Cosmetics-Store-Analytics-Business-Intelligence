-- ******************************************************
--                         CTE
-- ******************************************************

use cosmetics_store;
go

--1) تحليل باريتو 80/20 لتحديد المنتجات المسؤولة عن 80% من إيرادات المحل
---------------------------------------------
with ProductSales as ( --> CTE بنجمع فيه إجمالي مبيعات كل منتج
    select 
        s.item_code,
        s.item_name,
        p.product_category,
        sum(s.qty) as [UnitsSold],
        sum(s.line_final) as [ProductRevenue],
        sum(s.profit) as [ProductProfit]
    from dbo.FactSalesItem as s
    inner join dbo.DimProduct as p
        on s.item_code = p.item_code
    group by s.item_code, s.item_name, p.product_category
),
CumulativeSales as ( --> CTE بنحسب فيه الترتيب والمجموع التراكمي للإيراد
    select 
        item_code,
        item_name,
        product_category,
        UnitsSold,
        ProductRevenue,
        ProductProfit,
        row_number() over (order by ProductRevenue desc) as [SalesRank], --> row_number بيدي ترتيب متسلسل للمنتجات من الأكثر مبيعاً للأقل
        sum(ProductRevenue) over (order by ProductRevenue desc rows between unbounded preceding and current row) as [RunningRevenue], --> Running Total الجمع التراكمي للإيراد خطوة بخطوة
        sum(ProductRevenue) over () as [TotalRevenue] --> إجمالي مبيعات كل المنتجات لحساب النسبة المئوية
    from ProductSales
)
select 
    SalesRank,
    item_code,
    item_name,
    product_category,
    UnitsSold,
    ProductRevenue,
    round(RunningRevenue / TotalRevenue * 100.0, 2) as [CumulativeRevenuePct],
    case 
        when RunningRevenue / TotalRevenue <= 0.80 then 'Top 80% Core (Pareto Group A)' --> المنتجات الأساسية اللي بتمثل أول 80% من المبيعات
        when RunningRevenue / TotalRevenue <= 0.95 then 'Next 15% (Group B)' --> المنتجات المتوسطة
        else 'Tail 5% (Group C)' --> المنتجات الأقل مساهمة في الإيراد
    end as [ParetoClassification]
from CumulativeSales
where SalesRank <= 25 or (RunningRevenue / TotalRevenue <= 0.801) --> بنعرض أعلى 25 منتج أو كل المنتجات اللي حققت الـ 80%
order by SalesRank;
go
