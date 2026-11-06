-- *****************************************************************************
-- 09_hero_and_dead_stock_products.sql
-- تقرير أفضل الأصناف مبيعاً (Hero Products) مقابل البضاعة الراكدة التي لم تباع (Dead Stock)
-- *****************************************************************************

use cosmetics_store;
go

-- 1) أعلى 15 منتج مبيعاً وإيراداً في المحل (Hero Products)
--------------------------------------------------------------------------------
select top 15
    s.item_code as [ItemCode], --> كود الصنف
    s.item_name as [ItemName], --> اسم الصنف
    p.product_category as [ProductCategory], --> قسم الصنف
    sum(s.qty) as [UnitsSold], --> إجمالي عدد القطع المباعة
    sum(s.line_final) as [TotalRevenue], --> إجمالي الإيراد المحقق
    sum(s.profit) as [TotalProfit], --> إجمالي الأرباح المحققة
    round(sum(s.profit) / nullif(sum(s.line_final), 0) * 100.0, 2) as [ProfitMarginPct], --> نسبة مجمل الربح للصنف
    round(sum(s.line_final) / nullif(sum(s.qty), 0), 2) as [AverageSellingPrice] --> متوسط سعر بيع القطعة
from dbo.FactSalesItem as s
inner join dbo.DimProduct as p on s.item_code = p.item_code --> ربط بند المبيعات بالكتالوج
inner join dbo.FactSalesInvoice as inv on inv.invoice_no = s.invoice_no --> ربط البند برأس الفاتورة
where inv.is_retail_sale = 1 --> فلترة مبيعات التجزئة فقط
group by s.item_code, s.item_name, p.product_category
order by TotalRevenue desc; --> الترتيب من الأكثر إيراداً
go

-- 2) فحص البضاعة الراكدة التي لم يباع منها أي قطعة ولها رصيد بالمخزن (Dead Stock)
--------------------------------------------------------------------------------
with UnsoldStockItems as ( --> CTE بنصفي فيه الأصناف التي لم يدخل لها أي سطر بيع ولها رصيد موجب بالمخزن
    select 
        p.item_code,
        p.item_name,
        p.product_category,
        p.total_qty as [StockUnits],
        p.sell_price,
        p.avg_purchase_price,
        p.stock_cost_valuation
    from dbo.DimProduct as p
    left join dbo.FactSalesItem as s on p.item_code = s.item_code
    where s.item_code is null --> مفيش أي سطر بيع مسجل للصنف ده نهائياً
      and p.total_qty > 0 --> رصيد المخزن موجب (بضاعة موجودة على الرفوف ولم تتحرك)
)
select 
    product_category as [ProductCategory], --> اسم القسم
    count(item_code) as [UnsoldSKUCount], --> عدد الأصناف الراكدة في القسم
    sum(StockUnits) as [TiedUpStockUnits], --> إجمالي عدد القطع المعطلة
    sum(stock_cost_valuation) as [TiedUpCapitalEGP] --> رأس المال المعطل والمجمد في بضاعة راكدة
from UnsoldStockItems
group by product_category
order by TiedUpCapitalEGP desc; --> الترتيب من القسم الأكثر تجميداً للأموال
go
