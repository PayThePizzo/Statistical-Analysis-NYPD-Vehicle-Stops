# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Academic project for the course *Statistical Inference and Learning* (Prof. Cristiano Varin, Ca' Foscari University of Venice, 2025/2026). Goal: predict excessive enforcement patterns in NYPD vehicle stop data, examining relationships with demographics, time, and geography.

**Single target variable: `arrested`** (binary 0/1).

Note: `VEH_CHECKPOINT_FLG` was intentionally dropped in data preparation and is not available as a predictor or target. `any_escalation` was never built. Do not reference these as active features.

## Repository Structure

Five sequential R Markdown notebooks, each knitted to HTML:

| File | Purpose |
|------|---------|
| `Intro and Data Preparation.Rmd` | Type conversion, feature engineering, cleaning, coherency checks |
| `EDA and Feature Engineering 4 Wheels.Rmd` | Univariate → bivariate EDA on 4-wheel vehicles; writes the model-ready CSV |
| `EDA and Feature Engineering 2 Wheels.Rmd` | Same EDA on 2-wheel vehicles; writes the model-ready CSV |
| `Model Selection and Evaluation 4 Wheels.Rmd` | Feature selection, k-fold CV, final model evaluation for 4-wheel vehicles |
| `Model Selection and Evaluation 2 Wheels.Rmd` | Same, for 2-wheel vehicles |

Note: Model Selection was split into 2/4-wheel notebooks (mirroring the EDA split); a single combined `Model Selection and Evaluation.Rmd` no longer exists.

### Data

Pipeline: raw CSV → `Intro and Data Preparation.Rmd` (per-category CSV, EDA input) → `EDA and Feature Engineering *.Rmd` (per-category `*_final.csv`, model input).

- `data/NYPD_Vehicle_Stop_Reports_20260319.csv` — raw source (downloaded March 2026, 2,476,419 × 19)
- `data/vehiclestops_4_wheels.csv` — Intro output, 4-wheel vehicles (CAR/SUV only), EDA input (2,157,445 × 17: `veh_categ` already dropped since it's constant within the file)
- `data/vehiclestops_2_wheels.csv` — Intro output, 2-wheel vehicles (MCL, MOPED, DBIKE, BIKE), EDA input (189,610 × 17)
- `data/vehiclestops_4_wheels_final.csv` — EDA output, model-ready (2,145,587 × 12, after age/duplicate cleaning)
- `data/vehiclestops_2_wheels_final.csv` — EDA output, model-ready (189,542 × 13, after age/duplicate cleaning)

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

### Intro-stage schema

Columns in both Intro output CSVs (same order): `year`, `month`, `day`, `doy`, `dow`, `weekday`, `hour`, `time_bracket`, `latitude`, `longitude`, `area`, `boro`, `sex`, `ethnicity`, `age`, `age_bracket`, `veh_categ`, `arrested`.

## EDA-level feature engineering

Features added during EDA (not in Intro):

| Feature | File | Definition |
|---------|------|------------|
| `hot_season` | 2 Wheels EDA only | 1 if month ∈ {4,5,6,7,8,9,10} (Apr–Oct), else 0. Not created for 4-wheels — absent from its final schema. |

Features **discussed but not yet engineered** (mentioned in commentary as proposed actions):
- `working_hour`: stop within 09:00–17:00 (proposed but absent from code)
- `weekend`: Saturday or Sunday (proposed but absent from code)
- `event_day`: manually flagged NYC public events (proposed but absent from code)

### EDA-stage final schema

Each EDA notebook re-orders and trims columns before writing its `*_final.csv` (dropping `day`, `doy`, `dow` in favor of `weekday`; dropping `latitude`/`longitude`, visualization-only; `veh_categ` already gone):

- 2 wheels (13 cols): `year`, `month`, `hot_season`, `weekday`, `hour`, `time_bracket`, `area`, `boro`, `sex`, `ethnicity`, `age`, `age_bracket`, `arrested`.
- 4 wheels (12 cols, no `hot_season`): `year`, `month`, `weekday`, `hour`, `time_bracket`, `area`, `boro`, `sex`, `ethnicity`, `age`, `age_bracket`, `arrested`.

## Running / Rendering

```r
rmarkdown::render("Intro and Data Preparation.Rmd")
rmarkdown::render("EDA and Feature Engineering 4 Wheels.Rmd")
rmarkdown::render("EDA and Feature Engineering 2 Wheels.Rmd")
rmarkdown::render("Model Selection and Evaluation 4 Wheels.Rmd")
rmarkdown::render("Model Selection and Evaluation 2 Wheels.Rmd")
```

Or knit inside RStudio (Ctrl+Shift+K). Output is self-contained HTML.

Dependencies install automatically on first run via the `requirements` vector at the top of each `.Rmd` (each notebook declares its own, not a shared list — many entries are unused legacy carryovers kept only to avoid dependency errors). `tidyverse` itself is never actually required.

- Intro: `remotes`, `summarytools`, `stringr`, `plyr`, `dbplyr`, `dplyr`, `dtplyr`, `tidyr`, `tidyselect`, `timeDate`, `timechange`, `tzdb`, `hms`, `readr`, `lubridate`, `prettyunits`, `RColorBrewer`, `viridis`, `rcartocolor`, `ggbeeswarm`, `emmeans`, `sf`, `plotly`, `ggplot2`, `ggmap`, `ggdensity`, `UpSetR`, `patchwork`.
- EDA (both 2/4-wheels, identical): `remotes`, `summarytools`, `scales`, `dplyr`, `tidyr`, `tidyselect`, `tigris`, `corrplot`, `RColorBrewer`, `viridis`, `sf`, `ggplot2`, `patchwork`.

## Analytical Conventions

- Primary data frame is named `vehstops` throughout all notebooks (not `vehstop`).
- Binary flags are stored as integer 0/1.
- Age: minimum driving age is 16. Upper outlier cutoff at 75 applied identically in both EDA notebooks (`filter(age < 76 | is.na(age))`), justified in-text as restricting to the "plausible 16–75 enforcement range." Lower bound (16) is asserted in prose only — not yet enforced in code — known gap, in both notebooks.
- Class imbalance: `arrested` is rare — ~5.6% for 2-wheels (10,560 / 189,610), ~3.3% for 4-wheels (70,600 / 2,157,445), even more pronounced than 2-wheels. Strategy: stratified down-sampling for tree/distance-based models (LDA, QDA, KNN); observation weighting for GLMs (Logistic, Lasso, Ridge); optimize decision threshold on Precision-Recall curve instead of the default 0.5 cutoff.
- Cramer's V used for categorical × categorical association (via `chisq.test` effect-size formula, not p-values — "traditional p-values from chi-squared tests become meaningless" at this sample size). No fixed numeric cutoff is applied in the EDA notebooks; strength is judged qualitatively per pair. Observed values there topped out around 0.19 (ethnicity × area/boro), with area/boro, hour/time_bracket, and ethnicity called out as the only predictors with a "noticeable" signal against `arrested`, and sex/age called "negligible."
- Pearson correlation (`cor(..., use = "complete.obs")`, plotted with `corrplot`) used for numeric × numeric pairs (e.g. year, month, day, dow, doy, hour, age vs. arrested) in the EDA notebooks — not Spearman.
- Models use k-fold CV (k=10) for evaluation; AIC for comparison; stepwise or LASSO for selection (Model Selection notebooks — not verified against the EDA notebooks read for this doc).
- Statistical language must be precise: data is observational and self-reported — do not overstate causal claims.
- Independence assumption is violated: same individual can appear in multiple stops. Acknowledge this as a limitation.

## Documentation & Narrative Conventions

The EDA notebooks explicitly declare a four-point commentary structure for "any plot" in their intro section; the Intro notebook shares the same general prose register (parenthetical asides, formal/discursive tone) but does not use the four-point structure. Match the relevant style when adding or editing analysis text.

- **Per-plot commentary (EDA notebooks)**: nearly every plot is followed by a "What can we say?" transition, then up to four bolded bullets, in order: **Key finding** (objective takeaway), **Interpretation** (what it means for the analysis), **Comment** (informal/qualitative discussion), **Proposed Action** (what to do next, or explicitly "no action for now"). Not all four are always present; never reorder them.
- **Reusable functions**: grouped under banner comments (`# ====...====`) inside a "Plot Functions" chunk, split into "Univariate Plot Functions" / "Bivariate Plot Functions" sub-sections, each documented with a roxygen2-style block directly above it (`#' @title`, `#' @description`, `#' @param`, `#' @return`) even though these are plain functions, not a package.
- **Numbers and percentages in prose** are wrapped in inline LaTeX math, percent sign included inside the math: `\(5.6\%\)`, `\(10,560\)`, `\(189,610\)` — not plain "5.6%" or "10560".
- Parenthetical asides are preferred over em/en dashes; semicolons are avoided in prose (commas or new sentences instead).
- Column/variable names are wrapped in backticks (`` `arrested` ``, `` `hot_season` ``) when referenced in prose.
- Section flow uses short discursive linking sentences between chunks ("Let us see...", "Now let us check...", "What can we say?") rather than jumping straight from one code chunk to the next.
