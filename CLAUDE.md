# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Academic project for the course *Statistical Inference and Learning* (Prof. Cristiano Varin, Ca' Foscari University of Venice, 2025/2026). Goal: predict excessive enforcement patterns in NYPD vehicle stop data, examining relationships with demographics, time, and geography.

**Single target variable: `arrested`** (binary 0/1).

Note: `VEH_CHECKPOINT_FLG` was intentionally dropped in data preparation and is not available as a predictor or target. `any_escalation` was never built. Do not reference these as active features.

## Repository Structure

Four sequential R Markdown notebooks, each knitted to HTML:

| File | Purpose |
|------|---------|
| `Intro and Data Preparation.Rmd` | Type conversion, feature engineering, cleaning, coherency checks |
| `EDA and Feature Engineering 4 Wheels.Rmd` | Univariate → bivariate → multivariate EDA on 4-wheel vehicles |
| `EDA and Feature Engineering 2 Wheels.Rmd` | Same EDA on 2-wheel vehicles |
| `Model Selection and Evaluation.Rmd` | Feature selection (stepwise/shrinkage), k-fold CV, final model evaluation |

### Data

- `data/NYPD_Vehicle_Stop_Reports_20260319.csv` — raw source (downloaded March 2026, 2,476,419 × 19)
- `data/vehiclestops_4_wheels.csv` — cleaned subset, 4-wheel vehicles (CAR/SUV only)
- `data/vehiclestops_2_wheels.csv` — cleaned subset, 2-wheel vehicles (MCL, MOPED, DBIKE, BIKE)

Raw data columns: `EVNT_KEY`, `OCCUR_DT`, `OCCUR_TM`, `CMD_CD`, `VEH_SEIZED_FLG`, `VEH_SEARCHED_FLG`, `VEH_SEARCH_CONSENT_FLG`, `VEH_CHECKPOINT_FLG`, `FORCE_USED_FLG`, `ARREST_MADE_FLG`, `SUMMON_ISSUED_FLG`, `VEH_CATEGORY`, `RPTED_AGE`, `SEX_CD`, `RACE_DESC`, `LATITUDE`, `LONGITUDE`, `X_COORD_CD`, `Y_COORD_CD`.

Data files are gitignored — do not commit them.

## Data Pipeline (Intro and Data Preparation.Rmd)

### Dropped columns

| Column | Reason |
|--------|--------|
| `EVNT_KEY` | Row ID — leakage risk |
| `SUMMON_ISSUED_FLG` | Separate target, out of scope |
| `VEH_SEARCH_CONSENT_FLG`, `VEH_SEARCHED_FLG`, `VEH_SEIZED_FLG`, `FORCE_USED_FLG` | Other enforcement flags, out of scope |
| `VEH_CHECKPOINT_FLG` | Dropped — not modeled |
| `date`, `time`, `minute` | Replaced by engineered features |
| `x_coord`, `y_coord` | Redundant with lat/lon; less R-compatible |
| `command` | Too granular (76+ precincts); overfitting risk |

### Engineered features

| Feature | Type | Description |
|---------|------|-------------|
| `year`, `month`, `day` | integer | Split from `OCCUR_DT` |
| `doy` | integer | Day of year (1–366) |
| `dow` | integer 1–7 | Day of week (1=Mon … 7=Sun, ISO) |
| `weekday` | ordered factor | Mon–Sun, ISO ordering |
| `hour` | integer 0–23 | Split from `OCCUR_TM` |
| `time_bracket` | ordered factor (6 levels) | Late night (0–3), Early morning (4–7), Morning commute (8–11), Midday (12–15), Afternoon/evening (16–19), Night (20–23) |
| `area` | character | Borough area from command code: Staten Island, Brooklyn, Manhattan, Queens, Bronx, Unknown |
| `boro` | character | Sub-borough from command code: Bronx, Brooklyn (North/South), Manhattan (North/South), Queens (North/South), Staten Island, Unknown |
| `age` | numeric | Parsed from `RPTED_AGE`; "UNKNOWN" → NA |
| `age_bracket` | ordered factor (8 levels) | Under 18, 18–24, 25–34, 35–44, 45–54, 55–64, 65+, Unknown |
| `ethnicity` | character | Recoded: Black, Hispanic, White, Asian / Pacific Islander, Unknown, Other (merges AMERICAN INDIAN/ALASKAN NATIVE + OTHER) |
| `veh_categ` | character | "4 wheels" (CAR/SUV) or "2 wheels" (MCL/MOPED/DBIKE/BIKE) |
| `arrested` | integer 0/1 | Target; "(null)" → NA |

### Geospatial notes

- `latitude` / `longitude`: 0 used as sentinel for missing/invalid (not NA). ~192,900 rows have 0 coordinates (~7.8% of raw data).
- Geographic bbox for NYC: lat [40.48, 40.92], lon [−74.26, −73.70].
- Coordinates used for visualization only; excluded from models (overfitting risk).

### Final dataset schema

Columns in both output CSVs (same order): `year`, `month`, `day`, `doy`, `dow`, `weekday`, `hour`, `time_bracket`, `latitude`, `longitude`, `area`, `boro`, `sex`, `ethnicity`, `age`, `age_bracket`, `veh_categ`, `arrested`.

## EDA-level feature engineering

Features added during EDA (not in Intro):

| Feature | File | Definition |
|---------|------|------------|
| `hot_season` | 2 Wheels EDA | 1 if month ∈ {4,5,6,7,8,9,10} (Apr–Oct), else 0 |

Features **discussed but not yet engineered** (mentioned in commentary as proposed actions):
- `working_hour`: stop within 09:00–17:00 (proposed but absent from code)
- `weekend`: Saturday or Sunday (proposed but absent from code)
- `event_day`: manually flagged NYC public events (proposed but absent from code)

## Running / Rendering

```r
rmarkdown::render("Intro and Data Preparation.Rmd")
rmarkdown::render("EDA and Feature Engineering 4 Wheels.Rmd")
rmarkdown::render("EDA and Feature Engineering 2 Wheels.Rmd")
rmarkdown::render("Model Selection and Evaluation.Rmd")
```

Or knit inside RStudio (Ctrl+Shift+K). Output is self-contained HTML.

Dependencies install automatically on first run via the `requirements` vector at the top of each `.Rmd`. Key packages: `tidyverse`, `lubridate`, `ggplot2`, `patchwork`, `sf`, `summarytools`, `emmeans`, `UpSetR`, `viridis`, `rcartocolor`.

## Analytical Conventions

- Primary data frame is named `vehstops` throughout all notebooks (not `vehstop`).
- Binary flags are stored as integer 0/1.
- Age: minimum driving age is 16. Upper outlier cutoff applied in 2-wheels EDA at 75 (`filter(age < 76 | is.na(age))`). Lower bound (16) not yet enforced in code — known gap.
- Class imbalance: `arrested` is rare (~5.6% for 2-wheels, ~3.4% overall). Strategy: stratified down-sampling for tree/distance-based models; observation weighting for GLMs; optimize decision threshold on Precision-Recall curve.
- Cramer's V used for categorical association (scales 0–1; >0.30 = strong effect). Chi-squared p-values not used at this sample size.
- Spearman correlation used for numeric features.
- Correlation heatmaps use φ (phi) for binary × binary pairs.
- Models use k-fold CV (k=10) for evaluation; AIC for comparison; stepwise or LASSO for selection.
- Statistical language must be precise: data is observational and self-reported — do not overstate causal claims.
- Independence assumption is violated: same individual can appear in multiple stops. Acknowledge this as a limitation.
