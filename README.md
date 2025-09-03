# DS Take-Home — Package
# Procurement & Supply Analytics — Take-Home

## 📋 About this project
This repo is my solution for the Data Science take-home exercise.  
It covers four main parts:
1. **EDA** → checking data quality and patterns.  
2. **Modeling** → predicting late deliveries.  
3. **Price anomalies** → spotting unusual supplier prices.  
4. **SQL tasks** → answering business questions with queries.  

I made sure to only use features available **at order time** and kept a proper **temporal split**:  
- Train: orders up to 2025-03-31  
- Validate: orders from 2025-04-01 to 2025-06-30  

---

## 📂 Repo structure
dataset/
deliveries.csv
price_lists.csv
products.csv
purchase_orders.csv
suppliers.csv

notebooks/
EDA.ipynb # Data exploration and quality checks
Model_Anomaly.ipynb # Late delivery model, calibration, slice analysis, anomalies
predictions.csv # Model predictions (order_id, p_late)

sql_exercise task 6 .sql # All SQL queries for Task 6.D
Sql outputs.xlsx #with the output of the SQL task
autograde_metrics.py # Utility script from starter files
DS_Takehome_Brief_and_Rubric.md # Original assignment brief
REPORT.md # 2-page summary of approach and results
README.md # This file
requirements.txt # Python dependencies

---

## ▶️ How to run
1. **Clone the repo**
   ```bash
   git clone <your-repo-url>
   cd DS-TAKEHOME-ABOUKHATWA
pip install -r requirements.txt
Notebooks

Open notebooks/EDA.ipynb for data exploration.
Open notebooks/Model_Anomaly.ipynb for modeling, calibration, and anomaly detection.
SQL
Open sql_exercise task 6 .sql in SQLite or DBeaver.
It contains all queries (with comments) to reproduce Task 6.D.
CSVs are in dataset/ and can be imported directly if needed.

📊 Results (highlights)
Late delivery model: PR-AUC ~0.64, ROC-AUC ~0.62, best-F1 ~0.68.
Calibration: Brier score ~0.24 → slightly under-confident.
Ops threshold: At top-15% flagged orders → precision ~0.71, recall ~0.21.
Price anomalies: Top 10 flagged with z-score; extreme outliers easy to spot.
SQL tasks: All required queries + bonus risk segmentation are included.

💡 Notes
Code is kept clean and commented.
I focused on clarity, correct methodology, and actionable insights.
Next steps in a real project would be: calibrate the model, add more features for short-distance orders, and automate anomaly alerts.