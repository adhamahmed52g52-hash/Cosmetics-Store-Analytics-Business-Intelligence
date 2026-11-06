# Cosmetics Store Analytics & Business Intelligence
**Digital Egypt Pioneers Initiative (DEPI) — Data Analytics Track**  
**Project:** Cosmetics Store Rebuild  
**Database:** Microsoft SQL Server (`cosmetics_store`)  

---

## 1. Data Overview

This project analyzes point-of-sale (POS), purchasing, returns, and inventory datasets from a retail cosmetics store in Egypt covering a 10-month period (**28 November 2025 to 14 September 2026**).

| Dataset | Records Count | Key Fields | Description |
| :--- | :---: | :--- | :--- |
| **Sales Invoices** | 5,505 rows | `invoice_no`, `invoice_date`, `sale_type`, `final_total`, `profit` | Transaction headers (5,481 retail sales + 24 non-retail transactions). |
| **Sales Items** | 10,891 rows | `invoice_no`, `item_code`, `qty`, `price`, `unit_cost`, `line_final` | Line items sold across invoices. |
| **Purchase Invoices** | 32 rows | `invoice_no`, `purchase_date`, `acct_no`, `final_total` | Supplier inventory replenishment orders totaling **1,118,614.71 EGP**. |
| **Purchase Items** | 1,658 rows | `invoice_no`, `item_code`, `qty`, `price`, `line_final` | Goods and quantities received into store inventory. |
| **Sales Returns** | 127 rows | `return_invoice_no`, `return_date`, `original_invoice_no`, `final_total` | Customer returns and refunds totaling **-13,779.78 EGP**. |
| **Return Items** | 157 rows | `return_invoice_no`, `item_code`, `qty`, `price`, `line_final` | Individual items returned by customers. |
| **Products Catalog** | 1,437 SKUs | `item_code`, `item_name`, `product_category`, `total_qty`, `stock_cost_valuation` | Store catalog classified across 7 departments with net valuation of **322,251.11 EGP**. |
| **Accounts Master** | 37 accounts | `acct_no`, `acct_name`, `nature`, `account_classification`, `is_internal` | Suppliers (15), customers (14), staff (3), partners (2), expenses (2), other (1). |

---

## 2. Verified Financial Numbers

The analysis distinguishes between total POS gross bookings and true core retail performance:

- **Gross Book Sales (All 5,505 Invoices):** **978,248.29 EGP** | Profit: **198,590.41 EGP** | Margin: **20.30%**
- **Excluded Non-Retail Transactions (24 Invoices):** **62,482.00 EGP**  
  *(Internal partner withdrawals, supplier barter settlements, staff payroll, and store expenses)*
- **Retail Gross Sales (5,481 Invoices):** **915,766.29 EGP** | Profit: **195,554.19 EGP**
- **Sales Returns (127 Invoices):** **-13,779.78 EGP** | Return Rate: **1.50%**
- **Retail Net Sales:** **901,986.51 EGP (~902K EGP)**
- **Retail Net Profit:** **192,534.06 EGP (~192.5K EGP)**
- **Retail Net Margin:** **21.35%**

---

## 3. Main Business Findings

### Why Did Daily Sales Fall by 74%?
Sales per trading day dropped from **≈5,150 EGP/day (Dec 2025) to ≈1,340 EGP/day (Aug 2026)**.
1. **Traffic / Footfall Collapse:** Daily invoices fell by **65.2%** (from 29.3 to 10.2 orders/day). Over **78%** of the revenue drop was fewer visiting customers.
2. **Stable Prices:** Average unit selling price stayed flat (**72.9 EGP → 73.7 EGP, +1.1%**), confirming customers did not leave due to price increases.
3. **Assortment Depletion:** Stock replenishment stopped (purchased units dropped from 11,536 in Nov to 3 in Aug). In-stock catalogue availability plunged from **97.9% to 63.8%**, leaving 76 of the top-100 sellers out of stock.
4. **Restock Sales Lift:** When products were restocked ($\ge 20$ SKUs), their sales jumped by **+108%, +78%, and +129%** in the following 45 days.

### Shopping Cycles
- **Late-Night Peak:** The hours from **20:00 to 04:00** account for **67.20%** of total revenue (**657,337.39 EGP**).
- **Friday Peak:** Friday is the highest revenue day, bringing in **22.41%** of weekly sales (**219,197.20 EGP**).

---

## 4. Project Structure

```text
cosmetics_store_rebuild/
├── data/
│   ├── raw/                             # 8 raw staging CSVs (extracted from POS Excel)
│   └── processed/                       # 8 cleaned and validated CSVs
├── scripts/
│   ├── 01_extract_excel_to_csv.py       # Extraction & assertion checks
│   ├── finalize_cleaned_data.py         # Data cleaning, taxonomy & account segmentation
│   └── parse_utils.py                   # Parsing helpers, block unpacking & date validation
├── sql_server/
│   ├── schema/                          # Table DDL, PKs, FKs, indexes, and views
│   ├── etl/                             # load_data_to_sql.py (ETL loader with pre-commit checks)
│   └── queries/                         # 12 analytical & diagnostic T-SQL queries
├── notebooks/
│   └── cosmetics_data_analysis.ipynb    # 55 cells with embedded tables and 7 charts
└── documentation/
    ├── 01_Project_Planning_and_Management.pdf                         # Project proposal, timeline & charter
    ├── 02_Literature_Review.pdf                                       # Retail analytics & inventory literature
    ├── 03_Requirements_Gathering.pdf                                  # Stakeholder analysis & user stories
    ├── Cosmetics Store Data Analysis - Full Project Documentation.pdf # Full project documentation report
    └── System_Analysis_and_Design.md                                  # System analysis & physical schema design
```

---

## 5. How to Run

```bash
# 1. Extract raw POS Excel workbooks to CSV
python scripts/01_extract_excel_to_csv.py

# 2. Clean data, apply taxonomy, and segment accounts
python scripts/finalize_cleaned_data.py

# 3. Load tables into SQL Server and run pre-commit tests
python sql_server/etl/load_data_to_sql.py

# 4. Open the analysis notebook
jupyter notebook notebooks/cosmetics_data_analysis.ipynb
```
