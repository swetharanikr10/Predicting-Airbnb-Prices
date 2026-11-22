/* Data Analysis Term Project
   Project Title: Predicting Airbnb Prices in Chicago Using SAS
   From: Swetha Rani Keshava Ravi
   Date: November 16, 2026
   Subject: Data Analysis Term Project */


%let path = /home/u64427676/Macro; 
libname abnb "&path";
ods graphics on;

/* 1. Import */

%macro fixfile;
    %if %sysfunc(fileexist(&path/listings_fixed.csv)) = 0 %then %do;
        filename rawf "&path/listings.csv" recfm=n;
        filename fixf "&path/listings_fixed.csv" recfm=n;
        data _null_;
            infile rawf recfm=n;
            file fixf recfm=n;
            retain inq 0;
            input ch $char1.;
            if ch = '22'x then inq = not inq;                   
            else if ch in ('0A'x, '0D'x) and inq then ch = ' ';  
            else if ch = '0D'x then delete;                      
            put ch $char1.;
        run;
        filename rawf clear;
        filename fixf clear;
    %end;
%mend fixfile;
%fixfile

proc import datafile="&path/listings_fixed.csv"
            out=abnb.raw dbms=csv replace;
    guessingrows=max;
    getnames=yes;
run;

proc contents data=abnb.raw varnum; run;

/* 1b. Prep: Text -> Numbers, Flags, Groups */

data abnb.prep;
    set abnb.raw(keep=id neighbourhood_cleansed latitude longitude property_type
        room_type accommodates bathrooms_text bedrooms beds price minimum_nights
        maximum_nights availability_30 availability_60 availability_90 availability_365
        number_of_reviews number_of_reviews_ltm number_of_reviews_l30d
        review_scores_rating review_scores_accuracy review_scores_cleanliness
        review_scores_checkin review_scores_communication review_scores_location
        review_scores_value reviews_per_month calculated_host_listings_count
        host_is_superhost);
    length bath_txt $40 prop_group $20 area $10 price_txt $32;

    /* price import as text  */
    price_txt = vvaluex('price');
    price_num = input(compress(price_txt, '$,'), best12.);

    /* bathrooms_text  */
    bath_txt = lowcase(bathrooms_text);
    if index(bath_txt, 'half') then baths = 0.5;
    else baths = input(scan(bath_txt, 1, ' '), best8.);
    shared_bath = (index(bath_txt, 'shared') > 0);

    superhost  = (host_is_superhost = 't');
    no_reviews = (missing(review_scores_rating));   
    if missing(reviews_per_month) then reviews_per_month = 0;

    /* collapse property_type */
    if      property_type = 'Entire rental unit' then prop_group = 'Entire rental unit';
    else if property_type = 'Entire home'        then prop_group = 'Entire home';
    else if property_type = 'Entire condo'       then prop_group = 'Entire condo';
    else if property_type =: 'Entire'            then prop_group = 'Other entire place';
    else if property_type =: 'Private room'      then prop_group = 'Private room';
    else                                              prop_group = 'Hotel/shared/other';

    /* collapse neighbourhood_cleansed */
    if neighbourhood_cleansed in ('Near North Side','Loop','Near South Side')
        then area = 'Central';
    else if neighbourhood_cleansed in ('Rogers Park','West Ridge','Uptown','Lincoln Square',
        'Edison Park','Norwood Park','Jefferson Park','Forest Glen','North Park','Albany Park',
        'Ohare','Edgewater','North Center','Lake View','Lincoln Park')
        then area = 'North';
    else if neighbourhood_cleansed in ('Portage Park','Irving Park','Dunning','Montclare',
        'Belmont Cragin','Hermosa','Avondale','Logan Square')
        then area = 'Northwest';
    else if neighbourhood_cleansed in ('Humboldt Park','West Town','Austin','West Garfield Park',
        'East Garfield Park','Near West Side','North Lawndale','South Lawndale','Lower West Side')
        then area = 'West';
    else if neighbourhood_cleansed in ('Garfield Ridge','Archer Heights','Brighton Park',
        'Mckinley Park','Bridgeport','New City','West Elsdon','Gage Park','Clearing','West Lawn',
        'Chicago Lawn','West Englewood','Englewood')
        then area = 'Southwest';
    else area = 'South';
run;

/* 2. Dependent Variable: Price */

/* 2a. missing or nonsensical values */
proc means data=abnb.prep n nmiss min max;
    var price_num;
run;

data work.p1;
    set abnb.prep;
    if not missing(price_num);
run;

/* 2b. distribution, normality, percentiles */
proc univariate data=work.p1;
    var price_num;
    histogram price_num / normal;
    qqplot price_num / normal(mu=est sigma=est);
    output out=work.pct pctlpts=1 5 95 99 pctlpre=p_;
run;
proc print data=work.pct; run;

/* 2c. remove outliers */
%let lo = 20;
%let hi = 1000;

data abnb.clean;
    set work.p1;
    if &lo <= price_num <= &hi;
    log_price = log(price_num);
run;

/* 2d. skewness before vs after the log transformation */
proc univariate data=abnb.clean;
    var price_num log_price;
    histogram price_num log_price / normal;
run;

/* 3. Predictors */

/* 3a. building the modelling data */
proc stdize data=abnb.clean out=work.imp reponly method=median;
    var bedrooms beds baths minimum_nights maximum_nights
        review_scores_rating review_scores_accuracy review_scores_cleanliness
        review_scores_checkin review_scores_communication review_scores_location
        review_scores_value;
run;

/* 3b. feature engineering */
proc sql noprint;
    select mean(accommodates) into :acc_mean trimmed from work.imp;
quit;

data work.model;
    set work.imp;
    acc_c      = accommodates - &acc_mean; 
    acc_sq     = acc_c**2;                    
    long_stay  = (minimum_nights >= 28);       
run;

/* 3c. multicollinearity */
%let cand = accommodates bedrooms beds baths minimum_nights maximum_nights
            availability_30 availability_60 availability_90 availability_365
            number_of_reviews number_of_reviews_ltm number_of_reviews_l30d
            review_scores_rating review_scores_accuracy review_scores_cleanliness
            review_scores_checkin review_scores_communication review_scores_location
            review_scores_value reviews_per_month calculated_host_listings_count;

proc corr data=work.model nosimple;
    var &cand;
run;

/* VIFs for every candidate */
proc reg data=work.model;
    model log_price = &cand / vif;
run; quit;

/* reduced predictor  */
%let nums = acc_c acc_sq bedrooms baths availability_30 availability_365
            number_of_reviews reviews_per_month review_scores_rating
            review_scores_location calculated_host_listings_count
            long_stay shared_bath superhost no_reviews latitude longitude;
%let cats = prop_group area;

proc reg data=work.model;
    model log_price = &nums / vif;
run; quit;

/* 3d. categorical variables */
proc freq data=abnb.prep order=freq;
    tables property_type neighbourhood_cleansed prop_group area / nocum;
run;

/* 3e. missing values */
proc means data=abnb.clean n nmiss;
    var accommodates bedrooms beds baths minimum_nights maximum_nights
        review_scores_rating review_scores_accuracy review_scores_cleanliness
        review_scores_checkin review_scores_communication review_scores_location
        review_scores_value;
run;

/* 3f. feature engineering */
proc sgscatter data=work.model;
    plot log_price*(accommodates bedrooms baths availability_365
                    review_scores_rating reviews_per_month) / loess;
run;

proc sgplot data=work.model;
    vbox log_price / category=area;
run;
proc sgplot data=work.model;
    vbox log_price / category=prop_group;
run;

/* 4. Train / Test Split (80/20) */

proc surveyselect data=work.model out=work.split
                  samprate=0.8 seed=2026 method=srs outall;
run;

data work.train work.test;
    set work.split;
    if selected then output work.train;
    else output work.test;
run;

/* shared scoring macro */
proc datasets lib=work nolist nowarn;
    delete results;
quit;

%macro score_stats(ds=, pred=, model=, sample=);
    data work._tmp;
        set &ds;
        e_log = log_price - &pred;
        e_usd = price_num - exp(&pred);
    run;
    proc sql;
        create table work._s as
        select "&model" as model length=12,
               "&sample" as sample length=6,
               count(*) as n,
               sqrt(mean(e_log**2))  as rmse_log format=8.4,
               sqrt(mean(e_usd**2))  as rmse_usd format=8.2,
               mean(abs(e_usd))      as mae_usd  format=8.2
        from work._tmp
        where not missing(e_log);
    quit;
    proc append base=work.results data=work._s force; run;
%mend score_stats;

/* 5. Linear Regression: GLMSELECT + LASSO */

proc glmselect data=work.train testdata=work.test seed=2026
               plots=(coefficients criterionpanel);
    class &cats / param=glm;
    model log_price = &cats &nums
          / selection=lasso(choose=cv stop=none) cvmethod=random(10);
    output out=work.train_lasso predicted=pred_lasso residual=res_lasso;
    score data=work.test out=work.test_lasso predicted=pred_lasso residual=res_lasso;
run;

/* regression assumptions on training residuals */
proc sgplot data=work.train_lasso;
    scatter x=pred_lasso y=res_lasso / markerattrs=(size=3);
    refline 0 / axis=y;
    title "Residuals vs Predicted (Training)";
run;
proc univariate data=work.train_lasso noprint;
    var res_lasso;
    histogram res_lasso / normal;
    qqplot res_lasso / normal(mu=est sigma=est);
run;
title;

%score_stats(ds=work.train_lasso, pred=pred_lasso, model=LASSO, sample=Train);
%score_stats(ds=work.test_lasso,  pred=pred_lasso, model=LASSO, sample=Test);

/* 6. Decision Tree: HPSPLIT */

proc hpsplit data=work.train maxdepth=8 seed=2026;
    class &cats;
    model log_price = &cats &nums;
    grow variance;
    prune costcomplexity;
    code file="&path/tree_score.sas";
run;

data work.train_tree; set work.train; %include "&path/tree_score.sas"; run;
data work.test_tree;  set work.test;  %include "&path/tree_score.sas"; run;

%score_stats(ds=work.train_tree, pred=P_log_price, model=Tree, sample=Train);
%score_stats(ds=work.test_tree,  pred=P_log_price, model=Tree, sample=Test);

/* 7. Random Forest: HPFOREST */

proc hpforest data=work.train maxtrees=300 vars_to_try=6 maxdepth=20
              leafsize=5 seed=2026;
    target log_price / level=interval;
    input &nums / level=interval;
    input &cats / level=nominal;
    save file="&path/forest.bin";
run;

proc hp4score data=work.train;
    id id log_price price_num;
    score file="&path/forest.bin" out=work.train_rf;
run;
proc hp4score data=work.test;
    id id log_price price_num;
    score file="&path/forest.bin" out=work.test_rf;
run;

%score_stats(ds=work.train_rf, pred=P_log_price, model=Forest, sample=Train);
%score_stats(ds=work.test_rf,  pred=P_log_price, model=Forest, sample=Test);

/* 8. Compare Models */

proc print data=work.results noobs; run;

proc sgplot data=work.results;
    vbar model / response=rmse_usd group=sample groupdisplay=cluster datalabel;
    yaxis label="RMSE (USD)";
    title "Train vs Test RMSE by Model";
run;
title;

ods graphics off;
