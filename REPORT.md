# Data Science Take-Home — Procurement & Supply Analytics

## 1. What I Did
The dataset covered suppliers, products, price lists, purchase orders, and deliveries.  
I had four main goals:
1. Check data quality and explore key patterns (EDA).  
2. Build and evaluate a model to predict late deliveries.  
3. Detect unusual or wrong-looking supplier prices.  
4. Answer a set of SQL business questions.  

Throughout the project I made sure to only use features available **at order time** and I used a proper **time split**: training up to March 2025 and validating from April to June 2025.

---

## 2. EDA Highlights
- Joins worked cleanly; only a few missing values (distance, price validity).  
- Roughly half of all orders were late (after promised date).  
- Sea shipments and some supplier countries stood out as less reliable.  
- Short-distance orders (<500 km) behaved oddly — not much signal in the features.  

I flagged these issues early so I wouldn’t leak future info into the model.

---

## 3. Late Delivery Model
I started with a baseline Random Forest, then improved with gradient boosting and rolling history features. Results:

| Model        | PR-AUC | ROC-AUC | Best F1 | Threshold |
|--------------|--------|---------|---------|-----------|
| Baseline RF  | 0.610  | 0.607   | 0.580   | 0.50      |
| Improved v1  | 0.624  | 0.597   | 0.684   | 0.20      |
| Improved v2  | 0.643  | 0.620   | 0.682   | 0.05      |

Key points:
- The final model clearly beats the baseline, especially in PR-AUC (the main metric).  
- At a **15% capacity threshold**, precision was ~0.71, recall ~0.21 → good for triaging.  
- The reliability diagram showed the model is a bit **under-confident**, so calibration would help.  

Slice analysis:  
- Strongest on sea freight and medium-distance orders.  
- Weak on short-distance, which suggests missing features.

---

## 4. Price Anomalies
I converted all prices to EUR (USD→EUR = 0.92) and checked each (supplier, sku) series.  
Method: simple z-scores → easy to explain.  
- Extreme outliers (>3σ) = clear red flags.  
- Moderate anomalies (2–3σ) = worth a second look.  
Plots showed these visually, so it’s easy for the pricing team to spot issues.

---

## 5. SQL Tasks
All tasks are covered in `sql/sql_exercise.sql`.  
Highlights:
- **Monthly late rates by ship mode** (Apr–Jun 2025).  
- **Top 5 suppliers by volume**, with late % and avg delay.  
- **Trailing 90-day late rate** per supplier, labeled into categories.  
- **Overlapping price windows** flagged as minor/moderate/major with conflict checks.  
- **Attach valid price + normalize to EUR**, compute order value.  
- **Top 10 price anomalies** by z-score.  
- **Incoterm × distance buckets** with avg delays and late %.  
- **Bonus:** used predictions to split top 10% risk vs the rest → high-risk bucket really did have higher actual late rates.

---

## 6. Takeaways
- The model adds clear value — it’s not perfect, but it helps ops focus on risky orders.  
- Calibration is the next easy win.  
- Sea freight and certain suppliers deserve extra monitoring.  
- Price anomaly checks already catch obvious mistakes.  
- SQL queries provide a reusable set of KPIs.  

**If I had more time:**  
- Add better features for short-distance orders (e.g., city congestion, supplier size).  
- Build a simple dashboard to track model risk scores and price anomalies in real time.

---
