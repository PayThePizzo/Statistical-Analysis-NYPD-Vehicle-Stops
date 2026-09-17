# Statistical Analysis of NYPD Vehicle Stops

Predicting excessive enforcement patterns in police behavior after vehicle stops in New York City.

## Overview

This project studies whether a NYPD vehicle stop is followed by an arrest and which characteristics best explain or predict that outcome. The analytical target is the conditional probability

P(arrested = 1 | X)

where X contains the stop-level information available to the model.

The analysis is split into two populations to avoid masking important differences in the underlying stop distributions:

- 2-wheeled vehicles
- 4-wheeled private vehicles

The raw data used in the project contains more than 2.4 million stop records from 2023-2025 and includes time, location, officer command, vehicle type, motorist demographics, and post-stop enforcement outcomes.

## Research question and motivation

The project evaluates whether stop-level features such as borough, hour, sex, ethnicity, age, and vehicle class are associated with post-stop arrest risk. The work focuses on a rare-event classification problem: arrests are uncommon in both populations, particularly among 4-wheeled stops.

## Data source

The dataset is based on the NYPD Vehicle Stop Reports published by the City of New York.

Key facts from the report:

- 2,488,293 raw stop records
- 19 raw attributes
- 2023-2025 coverage
- arrest is the binary target variable
- demographic missingness is handled through explicit "Unknown" groups where appropriate
- geographic command information is aggregated into borough/area-based groupings for modeling
- commercial and TLC-related observations are removed from the retained population

## Methodology

### 1. Data preparation

The project cleans and standardizes the raw stop data by:

- retaining arrest-related outcomes
- parsing temporal variables into year, month, weekday, and hour
- grouping sparse demographic levels into meaningful categories
- aggregating command information into interpretable geographic regions
- removing identifiers and overfitting-prone variables
- separating private 4-wheel stops from 2-wheel stops

### 2. Exploratory data analysis

The EDA focuses on identifying the structure that should be carried into the models. The report highlights several recurring patterns:

- Arrest rates are higher for late-night and early-morning stops.
- The Bronx shows the highest raw arrest rate in both populations.
- Male drivers have higher arrest rates than female drivers.
- Hispanic and Black motorists have substantially higher arrest rates than White motorists.
- Arrest risk differs by age and is especially concentrated among younger motorists in the 2-wheel population.

### 3. Modeling strategy

The project evaluates several interpretable and regularized modeling approaches:

- Logistic regression
- LASSO logistic regression
- Generalized additive models (GAM)
- Naive Bayes

The final modeling strategy balances interpretability, parsimony, and predictive performance while handling mostly categorical predictors and a rare binary outcome.

## Key findings from the report

The report documents the following patterns:

- 2-wheeled dataset: 189,610 stops, 10,560 arrests, approximately 5.6% arrest rate
- 4-wheeled dataset: 2,157,445 stops, 70,600 arrests, approximately 3.3% arrest rate
- Borough/area, hour, and ethnicity are among the strongest raw associations with arrest in the 2-wheel population
- Ethnicity, hour, and age bracket remain important in the 4-wheel population
- The analysis found that the relationship between hour and arrest is clearly nonlinear, justifying GAM-style modeling

## Project structure

### Main analysis notebooks and rendered outputs

1. [Intro and Data Preparation](Intro-and-Data-Preparation.html)
2. [EDA and Feature Engineering](EDA-and-Feature-Engineering-2-Wheels.html) and [EDA and Feature Engineering 4 Wheels](EDA-and-Feature-Engineering-4-Wheels.html)
3. Model evaluation and selection outputs:
   - [LOGISTIC_2_W.rmd](LOGISTIC_2_W.rmd) / [LOGISTIC_2_W.html](LOGISTIC_2_W.html)
   - [LOGISTIC_4_W.rmd](LOGISTIC_4_W.rmd) / [LOGISTIC_4_W.html](LOGISTIC_4_W.html)
   - [LASSO_2_W.rmd](LASSO_2_W.rmd) / [LASSO_2_W.html](LASSO_2_W.html)
   - [LASSO_4_W.Rmd](LASSO_4_W.Rmd) / [LASSO_4_W.html](LASSO_4_W.html)
   - [GAM_2_W.rmd](GAM_2_W.rmd) / [GAM_2_W.html](GAM_2_W.html)
   - [GAM_4_W.Rmd](GAM_4_W.Rmd) / [GAM_4_W.html](GAM_4_W.html)
   - [NAIVE_BAYES_2_W.Rmd](NAIVE_BAYES_2_W.Rmd) / [NAIVE_BAYES_2_W.html](NAIVE_BAYES_2_W.html)
   - [NAIVE_BAYES_4_W.Rmd](NAIVE_BAYES_4_W.Rmd) / [NAIVE_BAYES_4_W.html](NAIVE_BAYES_4_W.html)

### Report files

- [docs/Report.pdf](docs/Report.pdf)
- [docs/NYPD Stop Arrest Analysis.pdf](docs/NYPD%20Stop%20Arrest%20Analysis.pdf)
- [report/main.pdf](report/main.pdf)

### Data files

- [data/NYPD_Vehicle_Stop_Reports_20260319.csv](data/NYPD_Vehicle_Stop_Reports_20260319.csv)
- [data/vehiclestops_2_wheels.csv](data/vehiclestops_2_wheels.csv)
- [data/vehiclestops_2_wheels_final.csv](data/vehiclestops_2_wheels_final.csv)
- [data/vehiclestops_4_wheels.csv](data/vehiclestops_4_wheels.csv)
- [data/vehiclestops_4_wheels_final.csv](data/vehiclestops_4_wheels_final.csv)

## Tech stack

This project is implemented in R using R Markdown notebooks and rendered HTML reports. The workflow combines exploratory analysis, feature engineering, and statistical learning for binary classification.

## Getting started

### Prerequisites

- R (recommended version 4.x)
- RStudio or another R IDE
- The packages required by the analysis scripts, as listed in the project files

### Installation

Open the project in RStudio and install the required packages before running the analysis notebooks.

### Suggested workflow

1. Open and run [Intro and Data Preparation](Intro-and-Data-Preparation.html)
2. Review [EDA and Feature Engineering](EDA-and-Feature-Engineering-2-Wheels.html) and [EDA and Feature Engineering 4 Wheels](EDA-and-Feature-Engineering-4-Wheels.html)
3. Run the model-specific scripts for logistic regression, LASSO, GAM, and Naive Bayes
4. Compare model performance and interpret the findings in light of the report

## License

This project is distributed under the GNU GPL v3 License. See [LICENSE](LICENSE) for more information.

## Acknowledgments

This project is based on data from the NYPD Vehicle Stop Reports and was completed as part of the academic work described in the accompanying reports. The original data source is the City of New York Open Data portal.
