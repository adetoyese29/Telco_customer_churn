SELECT * FROM telco_customer_churn
LIMIT 10;

--- 1. Churn Rate by Contract Type
SELECT
	contract,
	COUNT (*) AS total_customers,
	SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
	ROUND(100.0 * SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END) / COUNT (*), 2) AS churn_rate_percent
FROM telco_customer_churn
GROUP BY contract
ORDER BY churn_rate_percent DESC;

--- 2. Retention Rates by Tenure
SELECT
	tenure_groups,
	COUNT (*) AS total_customers,
	SUM(CASE WHEN churn = 'No' THEN 1 ELSE 0 END) AS retained_customers,
	ROUND(100.0 * SUM(CASE WHEN churn = 'No' THEN 1 ELSE 0 END) / COUNT (*), 2) AS retention_rate_percent
FROM telco_customer_churn
GROUP BY tenure_groups
ORDER BY retention_rate_percent DESC;

--- 3. Churn by Payment Method and Paperless Billing
SELECT 
    PaymentMethod,
    PaperlessBilling,
    COUNT(*) AS total,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate
FROM 
    telco_customer_churn
GROUP BY 
    PaymentMethod, PaperlessBilling
ORDER BY 
    churn_rate DESC;

--- 4. Revenue Lost to Churn
SELECT 
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 2) AS lost_monthly_revenue,
    ROUND(SUM(CASE WHEN Churn = 'No' THEN MonthlyCharges ELSE 0 END), 2) AS retained_monthly_revenue,
    ROUND(SUM(MonthlyCharges), 2) AS total_monthly_revenue
FROM 
    telco_customer_churn;

--- 5. High-Risk Customers (Short Tenure + High Monthly Charge)
SELECT 
    customerID,
    tenure,
    MonthlyCharges,
    TotalCharges,
    Contract,
    InternetService
FROM 
    telco_customer_churn
WHERE 
    tenure <= 3 AND tenure != 0 AND
    MonthlyCharges > 80 AND
    Churn = 'No'
ORDER BY 
    MonthlyCharges DESC;

--- 6. Customer Lifetime Value (Simple LTV)
SELECT 
    customerID,
    MonthlyCharges,
    tenure,
    ROUND(MonthlyCharges * tenure, 2) AS lifetime_value,
    Contract,
    Churn
FROM 
    telco_customer_churn
WHERE churn = 'No'
ORDER BY 
    lifetime_value DESC
LIMIT 20;

--- 7. Churn Breakdown by Internet Service
SELECT 
    InternetService,
    COUNT(*) AS total,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate
FROM 
    telco_customer_churn
GROUP BY 
    InternetService
ORDER BY 
    churn_rate DESC;

--- 8. Rolling Retention by Tenure (Window Function)
-- Step 1: Group and count retained customers by tenure_groups
WITH retention_base AS (
    SELECT 
        tenure_groups,
        COUNT(*) AS total_customers,
        SUM(CASE WHEN Churn = 'No' THEN 1 ELSE 0 END) AS retained_customers,
        CASE 
            WHEN tenure_groups = '0–3 months' THEN 1
            WHEN tenure_groups = '4–6 months' THEN 2
            WHEN tenure_groups = '7–12 months' THEN 3
            WHEN tenure_groups = '13–24 months' THEN 4
            WHEN tenure_groups = '25–48 months' THEN 5
            WHEN tenure_groups = '49+ months' THEN 6
        END AS sort_order
    FROM telco_customer_churn
    GROUP BY tenure_groups
),

-- Step 2: Get total number of retained customers
total_retention AS (
    SELECT SUM(retained_customers) AS total_retained
    FROM retention_base
)

-- Step 3: Calculate Rolling Retention %
SELECT 
    rb.tenure_groups,
    rb.total_customers,
    rb.retained_customers,
    SUM(rb.retained_customers) OVER (ORDER BY rb.sort_order) AS cumulative_retained,
    ROUND(
        100.0 * SUM(rb.retained_customers) OVER (ORDER BY rb.sort_order) / tr.total_retained,
        2
    ) AS cumulative_retention_percent
FROM 
    retention_base rb,
    total_retention tr
ORDER BY 
    rb.sort_order;


--- 9. Customer Segmentation by Revenue Contribution (RFM Scoring)
WITH rfm_base AS (
    SELECT 
        customerid,
        tenure,
        monthlycharges,
        totalcharges,
        NTILE(5) OVER (ORDER BY tenure) AS recency_score,
        NTILE(5) OVER (ORDER BY monthlycharges) AS frequency_score,
        NTILE(5) OVER (ORDER BY totalcharges) AS monetary_score
    FROM telco_customer_churn
    WHERE churn = 'No'
),
rfm_scored AS (
    SELECT *,
        (recency_score + frequency_score + monetary_score) AS rfm_score
    FROM rfm_base
)
SELECT 
    customerid,
    tenure,
    monthlycharges,
    totalcharges,
    recency_score,
    frequency_score,
    monetary_score,
    rfm_score,
    CASE
        WHEN rfm_score >= 13 THEN 'Champions'
        WHEN rfm_score >= 10 THEN 'Loyal Customers'
        WHEN rfm_score >= 7 THEN 'Potential Loyalists'
        WHEN rfm_score >= 4 THEN 'Needs Attention'
        ELSE 'At Risk'
    END AS customer_segment
FROM rfm_scored
ORDER BY rfm_score DESC;


--- 10. Cross-Tab of Churn by InternetService and Contract
SELECT 
    internetservice,
    contract,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
    ROUND(
        100.0 * SUM(CASE WHEN churn = 'Yes' THEN 1 ELSE 0 END)::numeric / COUNT(*),
        2
    ) AS churn_rate_percent
FROM telco_customer_churn
GROUP BY internetservice, contract
ORDER BY internetservice, contract;


--- 11. Churn Risk Scoring (Heuristic Model)

/* Logic used for this analysis:
Contract = Month-to-month;	Shortest commitment — higher churn
TechSupport = No;	Less support = more frustration
OnlineSecurity = No; 	Customers may feel exposed
Tenure < 6;	New users = not yet loyal
PaymentMethod = Electronic check;	Higher churn historically
MonthlyCharges > 80; 	Higher bills = higher cancel risk
*/

SELECT 
    customerid,
    contract,
    techsupport,
    onlinesecurity,
    tenure,
    paymentmethod,
    monthlycharges,
    
    -- Heuristic risk scoring
    CASE 
        WHEN contract = 'Month-to-month' THEN 2 ELSE 0 
    END +
    CASE 
        WHEN techsupport = 'No' THEN 1 ELSE 0 
    END +
    CASE 
        WHEN onlinesecurity = 'No' THEN 1 ELSE 0 
    END +
    CASE 
        WHEN tenure < 6 THEN 2 ELSE 0 
    END +
    CASE 
        WHEN paymentmethod = 'Electronic check' THEN 1 ELSE 0 
    END +
    CASE 
        WHEN monthlycharges > 80 THEN 1 ELSE 0 
    END AS churn_risk_score,
    
    CASE 
        WHEN 
            (
                CASE 
                    WHEN contract = 'Month-to-month' THEN 2 ELSE 0 
                END +
                CASE 
                    WHEN techsupport = 'No' THEN 1 ELSE 0 
                END +
                CASE 
                    WHEN onlinesecurity = 'No' THEN 1 ELSE 0 
                END +
                CASE 
                    WHEN tenure < 6 THEN 2 ELSE 0 
                END +
                CASE 
                    WHEN paymentmethod = 'Electronic check' THEN 1 ELSE 0 
                END +
                CASE 
                    WHEN monthlycharges > 80 THEN 1 ELSE 0 
                END
            ) >= 5 THEN 'High Risk'
        WHEN (
            CASE 
                    WHEN contract = 'Month-to-month' THEN 2 ELSE 0 
                END +
                CASE 
                    WHEN techsupport = 'No' THEN 1 ELSE 0 
                END +
                CASE 
                    WHEN onlinesecurity = 'No' THEN 1 ELSE 0 
                END +
                CASE 
                    WHEN tenure < 6 THEN 2 ELSE 0 
                END +
                CASE 
                    WHEN paymentmethod = 'Electronic check' THEN 1 ELSE 0 
                END +
                CASE 
                    WHEN monthlycharges > 80 THEN 1 ELSE 0 
                END
        ) BETWEEN 3 AND 4 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_category

FROM telco_customer_churn
WHERE churn = 'No';  -- Focus on active customers only

