# Predicting-Airbnb-Prices
Predicting Airbnb Prices in Chicago Using SAS 

This project models the nightly price of Chicago Airbnb listings in SAS OnDemand for Academics. The data is the Inside Airbnb snapshot from 19–20 Sep 2026 (8,695 listings, 90 variables).

Data: after removing listings with no price and keeping prices between $20 and $1,000, 7,253 listings remained. These were split 80/20 into a training sample (5,803) and a test sample (1,450). The target is log(price).

Preparation: fixed embedded line breaks before import, removed collinear predictors (VIF below 6 afterwards), grouped 43 property types and 76 neighbourhoods into 6 levels each, filled missing values with medians plus a no-reviews flag, and created features such as a squared size term, long_stay, shared_bath and superhost.

Models: LASSO (PROC GLMSELECT, 10-fold CV), decision tree (PROC HPSPLIT) and random forest (PROC HPFOREST, 300 trees).
