# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Academic project for the course *Statistical Inference and Learning* (Prof. Cristiano Varin, Ca' Foscari University of Venice, 2025/2026). Goal: predict excessive enforcement patterns (arrests, vehicle checkpoints) in NYPD vehicle stop data, examining relationships with demographics, time, and geography.

Two target variables drive two separate analytical tracks:
1. **Vehicle checkpoint** (`veh_checkpoint`)
2. **Arrest** (`arrested`)

A combined flag `any_escalation` aggregates these for joint analysis.

## Repository Structure

Three sequential R Markdown notebooks, each knitted to HTML:

| File | Purpose |
|------|---------|
| `Intro and Data Preparation.Rmd` | Type conversion, initial feature engineering, cleaning/imputation, coherency checks |
| `EDA and Feature Engineering.Rmd` | Univariate → bivariate → multivariate EDA on 4-wheel vehicles |
| `EDA and Feature Engineering 2.Rmd` | Same EDA on 2-wheel vehicles |
| `Model Selection and Evaluation.Rmd` | Feature selection (stepwise/shrinkage), k-fold CV, final model evaluation |

### Data

- `data/NYPD_Vehicle_Stop_Reports_20260319.csv` — raw source (downloaded March 2026, ~2M rows)
- `data/vehiclestops_4_wheels.csv` — cleaned subset, 4-wheel vehicles
- `data/vehiclestops_2_wheels.csv` — cleaned subset, 2-wheel vehicles

Raw data columns: `EVNT_KEY`, `OCCUR_DT`, `OCCUR_TM`, `CMD_CD`, `VEH_SEIZED_FLG`, `VEH_SEARCHED_FLG`, `VEH_SEARCH_CONSENT_FLG`, `VEH_CHECKPOINT_FLG`, `FORCE_USED_FLG`, `ARREST_MADE_FLG`, `SUMMON_ISSUED_FLG`, `VEH_CATEGORY`, `RPTED_AGE`, `SEX_CD`, `RACE_DESC`, `LATITUDE`, `LONGITUDE`, `X_COORD_CD`, `Y_COORD_CD`.

Data files are gitignored — do not commit them.

## Running / Rendering

Render a single notebook from the R console or terminal:

```r
rmarkdown::render("Intro and Data Preparation.Rmd")
rmarkdown::render("EDA and Feature Engineering.Rmd")
rmarkdown::render("Model Selection and Evaluation.Rmd")
```

Or knit inside RStudio (Ctrl+Shift+K). Output is self-contained HTML.

Dependencies install automatically on first run via the `requirements` vector at the top of each `.Rmd`. Key packages: `tidyverse`, `lubridate`, `ggplot2`, `patchwork`, `sf`, `summarytools`, `emmeans`, `UpSetR`, `viridis`, `rcartocolor`.

## Analytical Conventions

- Primary data frame is named `vehstop` throughout all notebooks.
- Binary flags are stored as integer 0/1.
- `working_hour` = stop within 09:00–17:00; `weekend` = Saturday/Sunday; `event_day` = manually flagged NYC public events.
- `any_escalation` = 1 if `veh_checkpoint == 1` OR `arrested == 1`.
- Age outliers: clip to [16, 100] before analysis.
- Geographic bbox for NYC: lat [40.48, 40.92], lon [−74.27, −73.68].
- Correlation heatmaps use φ (phi) for binary × binary pairs (treat 0/1 as numeric).
- Models use k-fold CV (k=10) for evaluation; AIC for comparison; stepwise or LASSO for selection.
- Statistical language should be precise: do not overstate causal claims — the data is observational and self-reported.
