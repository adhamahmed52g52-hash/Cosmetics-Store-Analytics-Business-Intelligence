# Cosmetics Store Analytics & Business Intelligence

An end-to-end Data Analytics and Business Intelligence project focused on analyzing cosmetics store operations, including sales, purchases, returns, products, and inventory.

The project uses Python for data processing and analysis, SQL Server for data storage and management, and interactive dashboards for presenting business insights.

## Project Overview

The main goal of this project is to transform raw cosmetics store data into meaningful business insights that help understand business performance, track key metrics, and identify areas that need attention.

The project covers the complete data workflow, from data preparation and database design to analysis and interactive visualization.

## Technologies Used

- **Python:** Pandas, NumPy, Matplotlib, Seaborn
- **Database:** Microsoft SQL Server
- **Business Intelligence:** Power BI, Tableau
- **Development Tools:** Jupyter Notebook, VS Code, Git, GitHub

## Project Workflow

1. **Data Preparation:** Loading, cleaning, validating, and standardizing the source datasets using Python.
2. **Exploratory Data Analysis (EDA):** Exploring the data and understanding sales, purchases, returns, and inventory.
3. **Database Design:** Building a relational database using SQL Server with primary keys, foreign keys, and indexes.
4. **Data Analysis:** Calculating business KPIs and analyzing operational performance.
5. **Dashboard Development:** Building interactive visualizations to present the results and support business decisions.

## Database Structure

The SQL Server database contains 8 main tables organized around business transactions and dimensions.

The structure includes:

- Account dimension
- Product dimension
- Sales invoices and sales details
- Purchase invoices and purchase details
- Return invoices and return details

Primary and foreign key relationships are used to maintain data integrity.

## Key Business Metrics

The following metrics were calculated from the processed datasets:

| Metric | Value |
|---|---:|
| Gross Sales | 978,248.29 EGP |
| Net Sales | 964,468.51 EGP |
| Gross Profit | 198,590.41 EGP |
| Net Profit | 195,570.28 EGP |
| Profit Margin | 20.30% |
| Total Orders | 5,505 |
| Units Sold | 12,521.93 |
| Average Order Value | 177.70 EGP |
| Total Returns | 127 |
| Inventory Valuation | 322,251.11 EGP |

## Key Findings

- Gross profit margin reached approximately 20.30%.
- Returns accounted for approximately 1.41% of sales.
- Inventory analysis identified 84 products with negative stock quantities, requiring further investigation.
- The analysis provides an overview of sales performance, product activity, profitability, and inventory conditions.

## Interactive Dashboard

The project includes a multi-page interactive dashboard built with Streamlit and Plotly.

It supports data exploration and business performance monitoring through interactive charts, KPI cards, and filters.

The dashboard supports loading data from processed CSV files or SQL Server.

## Data Quality & Validation

Data processing and database validation included:

- Checking missing and invalid values.
- Standardizing data formats and classifications.
- Validating primary and foreign key relationships.
- Checking for orphan records.
- Verifying processed datasets and database records.

## Project Structure

The project is organized into separate folders for data, notebooks, database scripts, ETL processes, and dashboard development.

## Future Improvements

- Expand business analysis and reporting.
- Add more advanced SQL queries and analytical views.
- Improve inventory monitoring and anomaly detection.
- Enhance dashboard performance and user experience.

---

**Project Type:** Data Analytics & Business Intelligence  
**Focus:** Retail Analytics | Sales Analysis | Profitability | Inventory Management
