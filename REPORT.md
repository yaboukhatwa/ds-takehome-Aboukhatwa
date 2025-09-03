# Data Science Take-Home — Procurement & Supply Analytics

## 1. Overview
This project analyzes a procurement dataset covering suppliers, products, price lists, purchase orders, and deliveries.  
The goals were to:
- Check data quality and explore patterns (EDA).  
- Build a model to predict late deliveries.  
- Detect unusual supplier price entries.  
- Answer key SQL questions for April–June 2025.  

All modeling was done with a **temporal split**: training on orders up to 2025-03-31 and validating on orders from 2025-04-01 to 2025-06-30.  
Features were restricted to **information available at order time** to avoid leakage.

---

## 2. Exploratory Data Analysis (Task 6.A)
- **Joins:** Tables connected cleanly on `order_id`, `supplier_id`, and `sku`.  
- **Missingness:** Some missing values in distance and price validity dates, but not critical.  
- **Delivery outcomes:** Around half of orders were late; cancellations were excluded.  
- **Patterns:**  
  - Sea freight and some supplier countries showed higher late rates.  
  - Short-distance (<500 km) orders were harder to explain, suggesting missing features (e.g., local congestion).  
- **Seasonality:** Order volumes were stable; late rates slightly higher in Q2.  

Visuals included: late rate by month, ship mode comparison, supplier heatmap, and distance bucket distribution.  

**Conclusion:** The dataset is suitable for predictive modeling, though additional features would help explain short-distance behavior.

---

## 3. Late Delivery Prediction (Task 6.B)

### Model Results
| Model        | PR-AUC | ROC-AUC | Best F1 | Threshold |
|--------------|--------|---------|---------|-----------|
| Baseline RF  | 0.610  | 0.607   | 0.580   | 0.50      |
| Improved v1  | 0.624  | 0.597   | 0.684   | 0.20      |
| Improved v2  | 0.643  | 0.620   | 0.682   | 0.05\*    |

\*Sweep found max F1 at threshold=0 (predict all orders late). I report 0.05 as a **practical threshold**.  

### Key Takeaways
- **Performance:** PR-AUC improved from 0.610 → 0.643 with gradient boosting and rolling history features.  
- **Thresholding:**  
  - At **0.5**: balanced but weaker recall.  
  - At **best-F1**: ~0.68.  
  - At **capacity (15%)**: Precision 0.71, Recall 0.21 → good for triaging.  
- **Calibration:**  
  - Brier score = 0.241.  
  - Reliability plot showed the model is **under-confident** → recommend Platt scaling or isotonic regression.  
- **Slice analysis:**  
  - Sea freight had the best separability (PR-AUC ~0.77).  
  - Medium-distance (500–1499 km) performed better than short-distance (<500 km).  
  - Supplier country patterns were consistent with overall results.  

---

## 4. Price Anomaly Detection (Task 6.C)
- **Normalization:** All prices converted to EUR (USD→EUR = 0.92).  
- **Method:** z-score on per-(supplier, sku) series; top 10 anomalies flagged.  
- **Findings:**  
  - Extreme outliers (>3σ) = strong candidates for data entry errors.  
  - Moderate anomalies (2–3σ) highlight suppliers with unstable pricing.  
- **Visuals:** Plots showed flagged anomalies clearly.  

**Operationally:** This method is simple, explainable, and can be automated for alerts.

---

## 5. SQL Exercise (Task 6.D)
Queries are in `sql/sql_exercise.sql` and outputs are included.  

- **Monthly late rates:** Overall and by ship mode for Apr–Jun 2025.  
- **Top 5 suppliers by volume:** With late % and avg delay.  
- **Trailing 90-day rate:** For each order, strictly before order_date.  
- **Overlapping price windows:** None detected with strict rules.  
- **Valid pricing at order date:** Attached prices, normalized to EUR, with `order_value_eur`.  
- **Price anomalies:** Top 10 |z| values flagged.  
- **Incoterm × distance buckets:** Avg delays and late rates by category.  
- **Bonus:** With predictions, top-10% high-risk orders showed higher actual late rates than the rest.  

---

## 6. Conclusions & Recommendations
- **Modeling:** Adds value by flagging risky orders, especially for sea freight and medium-distance shipments. Needs calibration for better probability estimates.  
- **Operations:** Use a capacity-based threshold (e.g., top 15%) to balance workload and recall.  
- **Suppliers:** Monitor high-volume suppliers with worsening 90-day late rates.  
- **Pricing:** Outlier detection already highlights entries for immediate review.  
- **Next steps:**  
  - Engineer features for short-distance orders.  
  - Deploy calibrated probabilities in dashboards.  
  - Automate anomaly alerts for pricing and delivery performance.

**Overall:** The project delivers a full pipeline from data quality checks to predictive modeling, anomaly detection, and SQL insights — with clear, actionable recommendations for procurement and operations teams.
