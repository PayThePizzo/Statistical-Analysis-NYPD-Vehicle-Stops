knitr::opts_chunk$set(echo = TRUE, warning = FALSE, message = FALSE)

requirements <- c(
  "remotes", "summarytools", "forcats", "scales", "purrr", "broom",
  "stringr", "plyr", "dbplyr", "dplyr", "dtplyr", "tidyr", "tidyselect",
  "timeDate", "timechange", "tzdb", "hms", "readr",
  "lubridate", "prettyunits", "RColorBrewer", "viridis", "rcartocolor",
  "sf", "ggplot2", "patchwork", "pROC", "kableExtra"
)

for (req in requirements) {
  if (!requireNamespace(req, quietly = TRUE)) install.packages(req)
}

for (req in requirements) library(req, character.only = TRUE)
rm(requirements, req)

vehstop <- read.csv("data/vehiclestops_2_wheels_final.csv")

# Ordered weekday levels (ISO order)
wday_levels <- c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

# Ordered time bracket levels
tbkt_levels <- c(
  "Late night (0–3)",
  "Early morning (4–7)",
  "Morning commute (8–11)",
  "Midday (12–15)",
  "Afternoon/evening (16–19)",
  "Night (20–23)"
)

# Ordered age-bracket levels
abkt_levels <- c("Under 18", "18–24", "25–34", "35–44", "45–54", "55–64", "65+")

vehstop <- vehstop %>%
  mutate(
    year         = factor(year),
    month        = factor(month, levels = 1:12),
    weekday      = factor(weekday, levels = wday_levels),
    hour         = factor(hour, levels = 0:23),
    time_bracket = factor(time_bracket, levels = tbkt_levels),
    area         = factor(area),
    boro         = factor(boro),
    sex          = factor(sex),
    ethnicity    = factor(ethnicity),
    age_bracket  = factor(age_bracket, levels = abkt_levels)
  )

# Reference levels chosen for interpretable contrasts
vehstop$sex          <- relevel(vehstop$sex,          ref = "M")
vehstop$ethnicity    <- relevel(vehstop$ethnicity,    ref = "White")
vehstop$weekday      <- relevel(vehstop$weekday,      ref = "Monday")
vehstop$time_bracket <- relevel(vehstop$time_bracket, ref = "Morning commute (8–11)")
vehstop$age_bracket  <- relevel(vehstop$age_bracket,  ref = "25–34")

rm(wday_levels, tbkt_levels, abkt_levels)

set.seed(2026)

# Joint stratum key; drop = TRUE removes empty combinations
vehstop$.strat <- interaction(
  vehstop$arrested, vehstop$area, vehstop$sex, vehstop$ethnicity, vehstop$hour,
  drop = TRUE
)

train_rows <- vehstop %>%
  mutate(.row = row_number()) %>%
  group_by(.strat) %>%
  slice_sample(prop = 0.8) %>%
  pull(.row)

train <- vehstop[ train_rows, ] %>% select(-.strat)
test  <- vehstop[-train_rows, ] %>% select(-.strat)
vehstop <- vehstop %>% select(-.strat)

check_prop <- function(var, label) {
  tr <- prop.table(table(train[[var]]))
  te <- prop.table(table(test[[var]]))
  tibble(
    level    = names(tr),
    train    = as.numeric(tr),
    test     = as.numeric(te),
    diff_ppt = round((as.numeric(te) - as.numeric(tr)) * 100, 2)
  ) %>%
    mutate(variable = label) %>%
    relocate(variable)
}

bind_rows(
  check_prop("arrested",  "arrested"),
  check_prop("area",      "area"),
  check_prop("sex",       "sex"),
  check_prop("ethnicity", "ethnicity")
) %>%
  kbl(
    digits    = 4,
    caption   = "Proportion of each level in train vs test (diff in percentage points)",
    col.names = c("Variable", "Level", "Train", "Test", "Δ (ppt)")
  ) %>%
  kable_styling(bootstrap_options = c("striped", "hover", "condensed"), full_width = FALSE) %>%
  collapse_rows(columns = 1, valign = "top")

cat(sprintf(
  "Training set : %d rows  |  Arrested: %.2f%%\nTest set     : %d rows  |  Arrested: %.2f%%\n",
  nrow(train), 100 * mean(train$arrested),
  nrow(test),  100 * mean(test$arrested)
))

f_base <- arrested ~ year + month + weekday + time_bracket + boro + sex + ethnicity + age_bracket

mod_base <- glm(f_base, family = binomial, data = train)

summary(mod_base)

predictors <- c("year", "month", "weekday", "time_bracket", "boro", "sex", "ethnicity", "age_bracket")

or_tbl <- tidy(mod_base, conf.int = TRUE, exponentiate = TRUE) %>%
  filter(term != "(Intercept)") %>%
  mutate(
    group = purrr::map_chr(term, function(t) {
      g <- predictors[purrr::map_lgl(predictors, ~ startsWith(t, .x))]
      if (length(g) == 0) "Other" else g[which.max(nchar(g))]
    }),
    level = purrr::map2_chr(term, group, ~ sub(paste0("^", .y), "", .x)),
    sig = case_when(
      p.value < 0.001 ~ "***",
      p.value < 0.01  ~ "**",
      p.value < 0.05  ~ "*",
      p.value < 0.1   ~ ".",
      TRUE            ~ ""
    )
  ) %>%
  select(group, level, estimate, conf.low, conf.high, p.value, sig)

or_tbl %>%
  kbl(
    digits    = 3,
    caption   = "Odds ratios with 95% CI and significance (reference levels: year=2023, month=Jan, weekday=Mon, time_bracket=Morning commute, boro=Bronx, sex=M, ethnicity=White, age_bracket=25-34)",
    col.names = c("Group", "Level vs Reference", "OR", "CI 2.5%", "CI 97.5%", "p-value", "")
  ) %>%
  kable_styling(bootstrap_options = c("striped", "hover", "condensed"), full_width = FALSE) %>%
  collapse_rows(columns = 1, valign = "top")

or_plot_data <- or_tbl %>%
  mutate(
    is_sig = p.value < 0.05,
    level  = stringr::str_wrap(level, width = 28),
    group  = factor(group, levels = c(
      "year", "month", "weekday", "time_bracket",
      "boro", "sex", "ethnicity", "age_bracket"
    ))
  )

ggplot(or_plot_data, aes(x = estimate, y = reorder(level, estimate), colour = is_sig)) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "grey55", linewidth = 0.5) +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high), height = 0.25, linewidth = 0.45) +
  geom_point(size = 2) +
  scale_x_log10(labels = scales::number_format(accuracy = 0.01)) +
  scale_colour_manual(
    values = c("TRUE" = "#2c7bb6", "FALSE" = "#d73027"),
    labels = c("TRUE" = "p < 0.05", "FALSE" = "p ≥ 0.05")
  ) +
  facet_wrap(~ group, scales = "free_y", ncol = 2) +
  labs(
    x       = "Odds Ratio (log scale)",
    y       = NULL,
    colour  = "Significance",
    title   = "Full Logistic Model — Odds Ratios with 95% CI",
    caption = paste0(
      "Reference levels: year = 2023, month = 1, weekday = Monday,\n",
      "time_bracket = Morning commute, boro = Bronx,\n",
      "sex = M, ethnicity = White, age_bracket = 25–34"
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    strip.text       = element_text(face = "bold"),
    legend.position  = "bottom",
    panel.grid.minor = element_blank()
  )

cv_auc <- function(formula, data, folds_vec) {
  k        <- max(folds_vec)
  auc_vals <- numeric(k)
  for (i in seq_len(k)) {
    tr  <- data[folds_vec != i, ]
    te  <- data[folds_vec == i, ]
    fit <- tryCatch(
      glm(formula, family = binomial, data = tr),
      error = function(e) NULL
    )
    if (is.null(fit)) { auc_vals[i] <- NA_real_; next }
    prob <- tryCatch(
      predict(fit, newdata = te, type = "response"),
      error = function(e) rep(NA_real_, nrow(te))
    )
    auc_vals[i] <- tryCatch(
      as.numeric(pROC::auc(te$arrested, prob, quiet = TRUE)),
      error = function(e) NA_real_
    )
  }
  mean(auc_vals, na.rm = TRUE)
}

# Shared fold assignment — same folds used for every model
set.seed(2026)
cv_folds <- sample(rep(1:10, length.out = nrow(train)))

f_hour   <- arrested ~ year + month + weekday + hour + boro + sex + ethnicity + age_bracket
mod_hour <- glm(f_hour, family = binomial, data = train)

aic_a <- AIC(mod_base, mod_hour)
bic_a <- BIC(mod_base, mod_hour)

tibble(
  Model     = c("Base (time_bracket, 5 df)", "Alternative (hour, 23 df)"),
  df        = aic_a$df,
  AIC       = round(aic_a$AIC, 1),
  BIC       = round(bic_a$BIC, 1),
  delta_AIC = round(aic_a$AIC - min(aic_a$AIC), 1),
  delta_BIC = round(bic_a$BIC - min(bic_a$BIC), 1)
) %>%
  kbl(
    caption   = "Comparison (a): time_bracket vs hour",
    col.names = c("Model", "# Param", "AIC", "BIC", "Δ AIC", "Δ BIC")
  ) %>%
  kable_styling(bootstrap_options = c("striped", "condensed"), full_width = FALSE)

lrt_a <- anova(mod_base, mod_hour, test = "Chisq")
lrt_a

chi_a <- lrt_a[["Deviance"]][2]
df_a  <- lrt_a[["Df"]][2]
p_a   <- lrt_a[["Pr(>Chi)"]][2]
cat(sprintf("LRT (a): χ²(%d) = %.2f,  p = %.4g\n", df_a, chi_a, p_a))

auc_base_a <- cv_auc(f_base, train, cv_folds)
auc_hour_a <- cv_auc(f_hour, train, cv_folds)

tibble(
  Model   = c("Base (time_bracket)", "Alternative (hour)"),
  CV_AUC  = round(c(auc_base_a, auc_hour_a), 4)
) %>%
  kbl(caption = "10-fold CV AUC on training set — comparison (a)") %>%
  kable_styling(bootstrap_options = c("striped", "condensed"), full_width = FALSE)

f_area   <- arrested ~ year + month + weekday + time_bracket + area + sex + ethnicity + age_bracket
mod_area <- glm(f_area, family = binomial, data = train)

aic_b <- AIC(mod_area, mod_base)
bic_b <- BIC(mod_area, mod_base)

tibble(
  Model     = c("Alternative (area, 4 df)", "Base (boro, 7 df)"),
  df        = aic_b$df,
  AIC       = round(aic_b$AIC, 1),
  BIC       = round(bic_b$BIC, 1),
  delta_AIC = round(aic_b$AIC - min(aic_b$AIC), 1),
  delta_BIC = round(bic_b$BIC - min(bic_b$BIC), 1)
) %>%
  kbl(
    caption   = "Comparison (b): area vs boro",
    col.names = c("Model", "# Param", "AIC", "BIC", "Δ AIC", "Δ BIC")
  ) %>%
  kable_styling(bootstrap_options = c("striped", "condensed"), full_width = FALSE)

lrt_b <- anova(mod_area, mod_base, test = "Chisq")
lrt_b

chi_b <- lrt_b[["Deviance"]][2]
df_b  <- lrt_b[["Df"]][2]
p_b   <- lrt_b[["Pr(>Chi)"]][2]
cat(sprintf("LRT (b): χ²(%d) = %.2f,  p = %.4g\n", df_b, chi_b, p_b))

auc_area_b <- cv_auc(f_area, train, cv_folds)
auc_base_b <- cv_auc(f_base, train, cv_folds)

tibble(
  Model   = c("Alternative (area)", "Base (boro)"),
  CV_AUC  = round(c(auc_area_b, auc_base_b), 4)
) %>%
  kbl(caption = "10-fold CV AUC on training set — comparison (b)") %>%
  kable_styling(bootstrap_options = c("striped", "condensed"), full_width = FALSE)

f_age   <- arrested ~ year + month + weekday + time_bracket + boro + sex + ethnicity + age
mod_age <- glm(f_age, family = binomial, data = train)

aic_c <- AIC(mod_base, mod_age)
bic_c <- BIC(mod_base, mod_age)

tibble(
  Model     = c("Base (age_bracket, 6 df)", "Alternative (age numeric, 1 df)"),
  df        = aic_c$df,
  AIC       = round(aic_c$AIC, 1),
  BIC       = round(bic_c$BIC, 1),
  delta_AIC = round(aic_c$AIC - min(aic_c$AIC), 1),
  delta_BIC = round(bic_c$BIC - min(bic_c$BIC), 1)
) %>%
  kbl(
    caption   = "Comparison (c): age_bracket vs numeric age",
    col.names = c("Model", "# Param", "AIC", "BIC", "Δ AIC", "Δ BIC")
  ) %>%
  kable_styling(bootstrap_options = c("striped", "condensed"), full_width = FALSE)

auc_base_c <- cv_auc(f_base, train, cv_folds)
auc_age_c  <- cv_auc(f_age,  train, cv_folds)

tibble(
  Model   = c("Base (age_bracket)", "Alternative (age numeric)"),
  CV_AUC  = round(c(auc_base_c, auc_age_c), 4)
) %>%
  kbl(caption = "10-fold CV AUC on training set — comparison (c)") %>%
  kable_styling(bootstrap_options = c("striped", "condensed"), full_width = FALSE)

# Collect all AUC values (shared folds)
auc_summary <- c(
  cv_auc(f_base, train, cv_folds),
  cv_auc(f_hour, train, cv_folds),
  cv_auc(f_area, train, cv_folds),
  cv_auc(f_age,  train, cv_folds)
)

models_list <- list(mod_base, mod_hour, mod_area, mod_age)

summary_tbl <- tibble(
  Model      = c(
    "Base  (time_bracket + boro + age_bracket)",
    "(a)   hour + boro + age_bracket",
    "(b)   time_bracket + area + age_bracket",
    "(c)   time_bracket + boro + age (numeric)"
  ),
  Parameters = sapply(models_list, function(m) length(coef(m))),
  Deviance   = sapply(models_list, function(m) round(deviance(m), 1)),
  AIC        = sapply(models_list, function(m) round(AIC(m), 1)),
  BIC        = sapply(models_list, function(m) round(BIC(m), 1)),
  CV_AUC     = round(auc_summary, 4)
) %>%
  mutate(
    delta_AIC = round(AIC - min(AIC), 1),
    delta_BIC = round(BIC - min(BIC), 1)
  )

summary_tbl %>%
  kbl(
    caption   = "All model alternatives compared — lower AIC/BIC and higher CV AUC preferred",
    col.names = c("Model", "# Param", "Deviance", "AIC", "BIC", "CV AUC", "Δ AIC", "Δ BIC")
  ) %>%
  kable_styling(bootstrap_options = c("striped", "hover", "condensed"), full_width = TRUE) %>%
  row_spec(which.min(summary_tbl$AIC), bold = TRUE, color = "white", background = "#2c7bb6")

tibble(
  Comparison = c("(a) time_bracket → hour (18 df freed)", "(b) boro → area (3 df constrained)"),
  `χ²` = round(c(chi_a, chi_b), 2),
  df      = c(df_a, df_b),
  p_value = signif(c(p_a, p_b), 3)
) %>%
  kbl(caption = "Likelihood ratio tests for nested comparisons") %>%
  kable_styling(bootstrap_options = c("striped", "condensed"), full_width = FALSE)

summary_tbl %>%
  select(Model, AIC, BIC) %>%
  pivot_longer(c(AIC, BIC), names_to = "Criterion", values_to = "Value") %>%
  mutate(Model = stringr::str_wrap(Model, 35)) %>%
  ggplot(aes(x = reorder(Model, Value), y = Value, fill = Criterion)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6) +
  coord_flip() +
  scale_fill_viridis_d(option = "mako", begin = 0.35, end = 0.75) +
  labs(
    x     = NULL,
    y     = "Information criterion (lower is better)",
    title = "AIC and BIC across predictor-form alternatives",
    fill  = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", panel.grid.minor = element_blank())

summary_tbl %>%
  mutate(Model = stringr::str_wrap(Model, 35)) %>%
  ggplot(aes(x = reorder(Model, CV_AUC), y = CV_AUC)) +
  geom_col(fill = "#2c7bb6", width = 0.6) +
  geom_text(aes(label = sprintf("%.4f", CV_AUC)), hjust = -0.1, size = 3.5) +
  coord_flip(ylim = c(
    min(summary_tbl$CV_AUC) - 0.005,
    max(summary_tbl$CV_AUC) + 0.012
  )) +
  labs(
    x     = NULL,
    y     = "10-fold CV AUC (higher is better)",
    title = "Cross-validated AUC across predictor-form alternatives"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

use_time <- if (AIC(mod_hour) <= AIC(mod_base)) "hour"         else "time_bracket"
use_geo  <- if (AIC(mod_base) <= AIC(mod_area)) "boro"         else "area"
use_age  <- if (AIC(mod_base) <= AIC(mod_age))  "age_bracket"  else "age"

cat("Time predictor :", use_time, "\n")
cat("Geo predictor  :", use_geo,  "\n")
cat("Age predictor  :", use_age,  "\n")

f_final <- reformulate(
  c("year", "month", "weekday", use_time, use_geo, "sex", "ethnicity", use_age),
  response = "arrested"
)

# ── Threshold and confusion-matrix helpers ───────────────────────────────────

best_thresh <- function(roc_obj) {
  pROC::coords(roc_obj, "best", ret = "threshold", best.method = "youden",
               quiet = TRUE)$threshold
}

conf_tib <- function(actual, predicted) {
  tibble(
    Actual    = factor(actual,    levels = c(0, 1)),
    Predicted = factor(predicted, levels = c(0, 1))
  ) %>% count(Actual, Predicted)
}

plot_cm <- function(actual, predicted, title = "Confusion Matrix") {
  conf_tib(actual, predicted) %>%
    ggplot(aes(Predicted, Actual, fill = n)) +
    geom_tile(colour = "white") +
    geom_text(aes(label = scales::comma(n)), size = 5.5, fontface = "bold") +
    scale_fill_gradient(low = "#e8f4f8", high = "#2c7bb6", guide = "none") +
    scale_x_discrete(labels = c("0" = "No arrest", "1" = "Arrest")) +
    scale_y_discrete(labels = c("0" = "No arrest", "1" = "Arrest")) +
    labs(title = title, x = "Predicted", y = "Actual") +
    theme_minimal(base_size = 12) +
    theme(panel.grid = element_blank())
}

class_metrics <- function(actual, predicted, pos = 1) {
  tp <- sum(actual == pos & predicted == pos)
  tn <- sum(actual != pos & predicted != pos)
  fp <- sum(actual != pos & predicted == pos)
  fn <- sum(actual == pos & predicted != pos)
  sens <- tp / (tp + fn)
  spec <- tn / (tn + fp)
  list(
    sensitivity  = sens,
    specificity  = spec,
    balanced_acc = (sens + spec) / 2,
    ppv          = tp / (tp + fp),
    npv          = tn / (tn + fn)
  )
}

# ── Probability-based metrics and evaluation plots ───────────────────────────

# Full metrics tibble (one row per model)
compute_metrics <- function(actual, prob, model_name = "Model") {
  roc_obj <- pROC::roc(actual, prob, quiet = TRUE)
  auc_val <- as.numeric(pROC::auc(roc_obj))
  thr     <- best_thresh(roc_obj)
  pred_cl <- as.integer(prob >= thr)

  tp <- sum(actual == 1 & pred_cl == 1); tn <- sum(actual == 0 & pred_cl == 0)
  fp <- sum(actual == 0 & pred_cl == 1); fn <- sum(actual == 1 & pred_cl == 0)
  sens <- if ((tp+fn) == 0) NA_real_ else tp / (tp+fn)
  spec <- if ((tn+fp) == 0) NA_real_ else tn / (tn+fp)
  prec <- if ((tp+fp) == 0) NA_real_ else tp / (tp+fp)
  f1   <- if (is.na(prec) || is.na(sens) || (prec+sens) == 0) NA_real_ else
            2 * prec * sens / (prec + sens)
  mcc_den <- sqrt(as.numeric(tp+fp) * as.numeric(tp+fn) *
                  as.numeric(tn+fp) * as.numeric(tn+fn))
  mcc_val <- if (mcc_den == 0) NA_real_ else (tp*tn - fp*fn) / mcc_den

  eps     <- 1e-15
  logloss <- -mean(actual * log(pmax(prob, eps)) + (1-actual) * log(pmax(1-prob, eps)))
  brier   <- mean((prob - actual)^2)

  # PR-AUC via trapezoid rule over pROC coords
  pr_raw <- pROC::coords(roc_obj, "all",
                          ret = c("sensitivity", "precision"),
                          transpose = FALSE, drop = FALSE)
  names(pr_raw)[names(pr_raw) == "sensitivity"] <- "recall"
  pr_raw <- pr_raw %>%
    filter(!is.nan(precision), !is.na(precision), !is.nan(recall)) %>%
    arrange(recall)
  pr_auc_val <- if (nrow(pr_raw) >= 2)
    sum(diff(pr_raw$recall) *
          (head(pr_raw$precision, -1) + tail(pr_raw$precision, -1)) / 2)
  else NA_real_

  tibble(
    Model       = model_name,
    AUC         = round(auc_val, 4),
    PR_AUC      = round(pr_auc_val, 4),
    Log_Loss    = round(logloss, 4),
    Brier       = round(brier, 4),
    Threshold   = round(thr, 4),
    Sensitivity = round(sens, 3),
    Specificity = round(spec, 3),
    Precision   = round(prec, 3),
    F1          = round(f1, 3),
    MCC         = round(mcc_val, 3),
    Bal_Acc     = round(if (!is.na(sens) && !is.na(spec)) (sens+spec)/2
                        else NA_real_, 3)
  )
}

# ROC curve (single model)
plot_roc_single <- function(actual, prob, title = "ROC Curve") {
  roc_obj <- pROC::roc(actual, prob, quiet = TRUE)
  auc_lbl <- paste0("AUC = ", round(as.numeric(pROC::auc(roc_obj)), 4))
  pROC::ggroc(roc_obj, colour = "#2c7bb6", linewidth = 0.9) +
    geom_abline(slope = 1, intercept = 1, linetype = "dashed", colour = "grey60") +
    annotate("text", x = 0.25, y = 0.06, label = auc_lbl,
             colour = "#2c7bb6", size = 4) +
    labs(x = "Specificity", y = "Sensitivity", title = title) +
    theme_minimal(base_size = 11) + theme(panel.grid.minor = element_blank())
}

# Precision-Recall curve (single model)
plot_pr_single <- function(actual, prob, title = "Precision-Recall Curve") {
  roc_obj <- pROC::roc(actual, prob, quiet = TRUE)
  pr_raw  <- pROC::coords(roc_obj, "all",
                           ret = c("sensitivity", "precision"),
                           transpose = FALSE, drop = FALSE)
  names(pr_raw)[names(pr_raw) == "sensitivity"] <- "recall"
  pr_df <- pr_raw %>%
    filter(!is.nan(precision), !is.na(precision)) %>% arrange(recall)
  pr_auc_lbl <- if (nrow(pr_df) >= 2) {
    v <- sum(diff(pr_df$recall) *
               (head(pr_df$precision,-1) + tail(pr_df$precision,-1)) / 2)
    paste0("PR-AUC = ", round(v, 4))
  } else "PR-AUC = NA"
  baseline <- mean(actual)
  ggplot(pr_df, aes(x = recall, y = precision)) +
    geom_line(colour = "#d73027", linewidth = 0.9) +
    geom_hline(yintercept = baseline, linetype = "dashed", colour = "grey55") +
    annotate("text", x = 0.02, y = baseline + 0.015,
             label = paste0("No-skill = ", round(baseline, 3)),
             colour = "grey40", size = 3.2, hjust = 0) +
    annotate("text", x = 0.55, y = 0.90, label = pr_auc_lbl,
             colour = "#d73027", size = 4) +
    scale_x_continuous(limits = c(0, 1)) + scale_y_continuous(limits = c(0, 1)) +
    labs(x = "Recall", y = "Precision", title = title) +
    theme_minimal(base_size = 11) + theme(panel.grid.minor = element_blank())
}

# Calibration (reliability) plot
plot_calibration_single <- function(actual, prob, title = "Calibration Plot",
                                    n_bins = 10) {
  brks  <- unique(quantile(prob, seq(0, 1, length.out = n_bins + 1), na.rm = TRUE))
  cal_df <- tibble(actual = actual, prob = prob) %>%
    mutate(bin = cut(prob, breaks = brks, include.lowest = TRUE)) %>%
    filter(!is.na(bin)) %>%
    group_by(bin) %>%
    summarise(mean_pred = mean(prob), mean_obs = mean(actual),
              n = n(), .groups = "drop")
  ggplot(cal_df, aes(x = mean_pred, y = mean_obs)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey55") +
    geom_line(colour = "#2c7bb6", linewidth = 0.8) +
    geom_point(aes(size = n), colour = "#2c7bb6", alpha = 0.85) +
    scale_size_continuous(name = "Count", range = c(2, 9)) +
    scale_x_continuous(labels = scales::percent_format(accuracy = 0.1)) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
    labs(x = "Mean predicted probability", y = "Observed positive rate",
         title = title,
         caption = "Size ∝ bin count.  Dashed = perfect calibration.") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", panel.grid.minor = element_blank())
}

# Threshold analysis: sensitivity, specificity, precision, F1 vs threshold
plot_threshold_single <- function(actual, prob, title = "Threshold Analysis") {
  roc_obj  <- pROC::roc(actual, prob, quiet = TRUE)
  thr_data <- pROC::coords(roc_obj, "all",
                            ret = c("threshold","sensitivity","specificity","precision"),
                            transpose = FALSE, drop = FALSE) %>%
    filter(is.finite(threshold), threshold >= 0, threshold <= 1) %>%
    mutate(f1 = ifelse(!is.nan(precision) & (precision + sensitivity) > 0,
                       2 * precision * sensitivity / (precision + sensitivity), 0)) %>%
    pivot_longer(c(sensitivity, specificity, precision, f1),
                 names_to = "Metric", values_to = "Value") %>%
    mutate(Metric = recode(Metric,
      sensitivity = "Sensitivity", specificity = "Specificity",
      precision   = "Precision",   f1          = "F1 Score"))
  thr_opt <- best_thresh(roc_obj)
  ggplot(thr_data, aes(x = threshold, y = Value, colour = Metric)) +
    geom_line(linewidth = 0.75, na.rm = TRUE) +
    geom_vline(xintercept = thr_opt, linetype = "dashed",
               colour = "grey35", linewidth = 0.55) +
    annotate("text", x = thr_opt, y = 0.04,
             label = paste0("Youden\n", round(thr_opt, 3)),
             hjust = -0.08, size = 3, colour = "grey30") +
    scale_colour_viridis_d(option = "turbo", begin = 0.05, end = 0.92) +
    scale_y_continuous(limits = c(0, 1)) +
    labs(x = "Threshold", y = "Metric value", colour = NULL, title = title,
         caption = "Dashed: Youden's J optimal threshold") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", panel.grid.minor = element_blank())
}

# 2×2 evaluation panel (ROC | PR) / (Calibration | Threshold)
eval_quad_plot <- function(actual, prob, model_name) {
  p1 <- plot_roc_single(actual, prob,   paste(model_name, "— ROC"))
  p2 <- plot_pr_single(actual, prob,    paste(model_name, "— Precision-Recall"))
  p3 <- plot_calibration_single(actual, prob, paste(model_name, "— Calibration"))
  p4 <- plot_threshold_single(actual, prob, paste(model_name, "— Threshold Analysis"))
  (p1 | p2) / (p3 | p4)
}

mod_logit_best <- glm(f_final, family = binomial, data = train)
prob_logit     <- predict(mod_logit_best, newdata = test, type = "response")
roc_logit      <- pROC::roc(test$arrested, prob_logit, quiet = TRUE)
auc_logit      <- as.numeric(pROC::auc(roc_logit))
thr_logit      <- best_thresh(roc_logit)
class_logit    <- as.integer(prob_logit >= thr_logit)
met_logit      <- class_metrics(test$arrested, class_logit)

compute_metrics(test$arrested, prob_logit, "Logistic Regression") %>%
  kbl(
    caption   = "Logistic Regression — full evaluation metrics (test set, Youden threshold)",
    col.names = c("Model","AUC","PR-AUC","Log-Loss","Brier",
                  "Threshold","Sensitivity","Specificity","Precision","F1","MCC","Bal. Acc.")
  ) %>%
  kable_styling(bootstrap_options = c("striped","condensed"), full_width = TRUE)

plot_cm(test$arrested, class_logit,
        "Logistic Regression — Confusion Matrix (Youden threshold)")

eval_quad_plot(test$arrested, prob_logit, "Logistic Regression")

if (!requireNamespace("MASS", quietly = TRUE)) install.packages("MASS")
# Do NOT library(MASS) — it masks dplyr::select; use MASS:: prefix throughout

mod_qda <- MASS::qda(f_final, data = train)

cat("Prior probabilities:\n")
print(mod_qda$prior)

means_df <- as.data.frame(t(mod_qda$means)) %>%
  tibble::rownames_to_column("feature") %>%
  rename(arrested_0 = `0`, arrested_1 = `1`) %>%
  mutate(
    diff      = arrested_1 - arrested_0,
    direction = ifelse(diff > 0, "Higher in arrested", "Lower in arrested"),
    feature   = stringr::str_wrap(feature, 22)
  ) %>%
  arrange(desc(abs(diff)))

ggplot(head(means_df, 30), aes(x = diff, y = reorder(feature, diff), fill = direction)) +
  geom_col(width = 0.7) +
  geom_vline(xintercept = 0, linewidth = 0.4) +
  scale_fill_manual(values = c("Higher in arrested" = "#d73027", "Lower in arrested" = "#2c7bb6")) +
  labs(
    x     = "Mean difference  (arrested=1) − (arrested=0)",
    y     = NULL,
    fill  = NULL,
    title = "QDA — Top 30 features by within-class mean difference"
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom", panel.grid.minor = element_blank())

pred_qda  <- predict(mod_qda, newdata = test)
prob_qda  <- pred_qda$posterior[, "1"]
roc_qda   <- pROC::roc(test$arrested, prob_qda, quiet = TRUE)
auc_qda   <- as.numeric(pROC::auc(roc_qda))
thr_qda   <- best_thresh(roc_qda)
class_qda <- as.integer(prob_qda >= thr_qda)
met_qda   <- class_metrics(test$arrested, class_qda)

cat(sprintf(
  "AUC: %.4f  |  Threshold (Youden): %.4f\nSensitivity: %.3f  |  Specificity: %.3f  |  Balanced accuracy: %.3f\n",
  auc_qda, thr_qda, met_qda$sensitivity, met_qda$specificity, met_qda$balanced_acc
))

plot_cm(test$arrested, class_qda, title = "QDA — Confusion Matrix (Youden threshold)")

tibble(prob = prob_qda, actual = factor(test$arrested, levels = c(0,1),
                                        labels = c("Not arrested","Arrested"))) %>%
  ggplot(aes(x = prob, fill = actual)) +
  geom_histogram(bins = 60, position = "identity", alpha = 0.65) +
  geom_vline(xintercept = thr_qda, linetype = "dashed", colour = "grey30") +
  scale_fill_viridis_d(option = "mako", begin = 0.3, end = 0.8) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.001)) +
  labs(
    x     = "Predicted probability (log scale)",
    y     = "Count",
    fill  = NULL,
    title = "QDA — Posterior probability distribution by class",
    caption = "Dashed line: Youden optimal threshold"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

compute_metrics(test$arrested, prob_qda, "QDA") %>%
  kbl(
    caption   = "QDA — full evaluation metrics (test set, Youden threshold)",
    col.names = c("Model","AUC","PR-AUC","Log-Loss","Brier",
                  "Threshold","Sensitivity","Specificity","Precision","F1","MCC","Bal. Acc.")
  ) %>%
  kable_styling(bootstrap_options = c("striped","condensed"), full_width = TRUE)

eval_quad_plot(test$arrested, prob_qda, "QDA")

if (!requireNamespace("e1071", quietly = TRUE)) install.packages("e1071")
library(e1071)

laplace_grid <- c(0, 0.5, 1, 2, 5, 10)

nb_cv_auc <- function(k, data, folds_vec, formula) {
  n_folds  <- max(folds_vec)
  auc_vals <- numeric(n_folds)
  for (i in seq_len(n_folds)) {
    tr  <- data[folds_vec != i, ]
    te  <- data[folds_vec == i, ]
    fit <- e1071::naiveBayes(formula, data = tr, laplace = k)
    # posterior: columns named after class levels; column 2 = P(arrested=1)
    prob <- predict(fit, newdata = te, type = "raw")[, 2]
    auc_vals[i] <- tryCatch(
      as.numeric(pROC::auc(te$arrested, prob, quiet = TRUE)),
      error = function(e) NA_real_
    )
  }
  mean(auc_vals, na.rm = TRUE)
}

nb_aucs <- sapply(laplace_grid, nb_cv_auc,
                  data = train, folds_vec = cv_folds, formula = f_final)
best_laplace <- laplace_grid[which.max(nb_aucs)]
cat("Best Laplace k:", best_laplace, " | CV AUC:", round(max(nb_aucs), 4), "\n")

tibble(k = laplace_grid, CV_AUC = nb_aucs) %>%
  ggplot(aes(x = factor(k), y = CV_AUC)) +
  geom_col(fill = "#2c7bb6", width = 0.6) +
  geom_text(aes(label = round(CV_AUC, 4)), vjust = -0.4, size = 3.5) +
  labs(
    x     = "Laplace smoothing parameter k",
    y     = "10-fold CV AUC",
    title = "Naive Bayes — Laplace tuning"
  ) +
  coord_cartesian(ylim = c(min(nb_aucs) - 0.002, max(nb_aucs) + 0.005)) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

mod_nb <- e1071::naiveBayes(f_final, data = train, laplace = best_laplace)

# Extract tables for a selected set of substantively interesting predictors
plot_nb_feature <- function(feature_name, mod) {
  tbl <- mod$tables[[feature_name]]
  as.data.frame(tbl) %>%
    rename(level = 1, class = 2, prob = Freq) %>%
    mutate(class = factor(class, labels = c("Not arrested", "Arrested"))) %>%
    ggplot(aes(x = level, y = prob, fill = class)) +
    geom_col(position = position_dodge(width = 0.75), width = 0.65) +
    scale_fill_viridis_d(option = "mako", begin = 0.3, end = 0.8) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    labs(x = NULL, y = "P(level | class)", title = feature_name, fill = NULL) +
    theme_minimal(base_size = 9) +
    theme(
      axis.text.x    = element_text(angle = 30, hjust = 1),
      legend.position = "bottom",
      panel.grid.minor = element_blank()
    )
}

key_preds <- intersect(
  c("ethnicity", "sex", "age_bracket", use_geo, use_time),
  names(mod_nb$tables)
)

plots_nb <- lapply(key_preds, plot_nb_feature, mod = mod_nb)
patchwork::wrap_plots(plots_nb, ncol = 3) +
  patchwork::plot_annotation(
    title   = "Naive Bayes — Conditional probability by class for key predictors",
    caption = "P(level | class) from the training-set frequency tables"
  ) +
  patchwork::plot_layout(guides = "collect") &
  theme(legend.position = "bottom")

prob_nb  <- predict(mod_nb, newdata = test, type = "raw")[, 2]
roc_nb   <- pROC::roc(test$arrested, prob_nb, quiet = TRUE)
auc_nb   <- as.numeric(pROC::auc(roc_nb))
thr_nb   <- best_thresh(roc_nb)
class_nb <- as.integer(prob_nb >= thr_nb)
met_nb   <- class_metrics(test$arrested, class_nb)

cat(sprintf(
  "AUC: %.4f  |  Threshold (Youden): %.4f\nSensitivity: %.3f  |  Specificity: %.3f  |  Balanced accuracy: %.3f\n",
  auc_nb, thr_nb, met_nb$sensitivity, met_nb$specificity, met_nb$balanced_acc
))

plot_cm(test$arrested, class_nb, title = "Naive Bayes — Confusion Matrix (Youden threshold)")

compute_metrics(test$arrested, prob_nb, "Naive Bayes") %>%
  kbl(
    caption   = "Naive Bayes — full evaluation metrics (test set, Youden threshold)",
    col.names = c("Model","AUC","PR-AUC","Log-Loss","Brier",
                  "Threshold","Sensitivity","Specificity","Precision","F1","MCC","Bal. Acc.")
  ) %>%
  kable_styling(bootstrap_options = c("striped","condensed"), full_width = TRUE)

eval_quad_plot(test$arrested, prob_nb, "Naive Bayes")

if (!requireNamespace("glmnet", quietly = TRUE)) install.packages("glmnet")
library(glmnet)

X_train <- model.matrix(f_final, data = train)[, -1]   # drop intercept column
X_test  <- model.matrix(f_final, data = test)[, -1]
y_train <- train$arrested
y_test  <- test$arrested

cat("Training matrix:", nrow(X_train), "×", ncol(X_train), "\n")
cat("Test matrix    :", nrow(X_test),  "×", ncol(X_test),  "\n")

set.seed(2026)
cv_lasso <- cv.glmnet(
  X_train, y_train,
  family       = "binomial",
  alpha        = 1,
  nfolds       = 10,
  type.measure = "auc"
)

cat(sprintf(
  "λ.min  = %.6f  (CV AUC = %.4f)\nλ.1se  = %.6f  (CV AUC = %.4f)\n",
  cv_lasso$lambda.min, max(cv_lasso$cvm),
  cv_lasso$lambda.1se,
  cv_lasso$cvm[cv_lasso$lambda == cv_lasso$lambda.1se]
))

# Replicate the cv.glmnet plot in ggplot2
cv_df <- tibble(
  log_lambda = log(cv_lasso$lambda),
  cvm        = cv_lasso$cvm,
  cvup       = cv_lasso$cvup,
  cvlo       = cv_lasso$cvlo,
  nzero      = cv_lasso$nzero
)

ggplot(cv_df, aes(x = log_lambda, y = cvm)) +
  geom_ribbon(aes(ymin = cvlo, ymax = cvup), alpha = 0.15, fill = "#2c7bb6") +
  geom_line(colour = "#2c7bb6") +
  geom_point(size = 0.8, colour = "#2c7bb6") +
  geom_vline(xintercept = log(cv_lasso$lambda.min), linetype = "dashed",
             colour = "#d73027", linewidth = 0.7) +
  geom_vline(xintercept = log(cv_lasso$lambda.1se), linetype = "dashed",
             colour = "#fdae61", linewidth = 0.7) +
  annotate("text", x = log(cv_lasso$lambda.min), y = min(cv_df$cvlo),
           label = "λ.min", colour = "#d73027", hjust = -0.1, size = 3.5) +
  annotate("text", x = log(cv_lasso$lambda.1se), y = min(cv_df$cvlo),
           label = "λ.1se", colour = "#b36200", hjust = -0.1, size = 3.5) +
  labs(
    x     = "log(λ)",
    y     = "10-fold CV AUC",
    title = "LASSO — Cross-validated AUC vs regularisation strength"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

# Tidy the full coefficient path
coef_path <- as.matrix(coef(cv_lasso$glmnet.fit))   # (p+1) × n_lambda
lambdas   <- cv_lasso$glmnet.fit$lambda

path_df <- as.data.frame(t(coef_path[-1, ])) %>%   # drop intercept row
  mutate(log_lambda = log(lambdas)) %>%
  pivot_longer(-log_lambda, names_to = "feature", values_to = "coef") %>%
  filter(coef != 0)

# Only label non-zero at lambda.min for clarity
active_min <- names(which(coef(cv_lasso, s = "lambda.min")[-1, 1] != 0))

ggplot(path_df, aes(x = log_lambda, y = coef, group = feature,
                    colour = feature %in% active_min)) +
  geom_line(linewidth = 0.45, alpha = 0.8) +
  geom_vline(xintercept = log(cv_lasso$lambda.min), linetype = "dashed",
             colour = "#d73027", linewidth = 0.7) +
  geom_vline(xintercept = log(cv_lasso$lambda.1se), linetype = "dashed",
             colour = "#fdae61", linewidth = 0.7) +
  scale_colour_manual(values = c("TRUE" = "#2c7bb6", "FALSE" = "grey70"),
                      guide  = "none") +
  labs(
    x       = "log(λ)",
    y       = "Coefficient",
    title   = "LASSO — Coefficient paths",
    caption = "Blue paths: active at λ.min  |  Dashed lines: λ.min (red) and λ.1se (orange)"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

extract_coefs <- function(cv_fit, s_name) {
  cf <- coef(cv_fit, s = s_name)
  tibble(
    feature  = rownames(cf)[-1],
    estimate = as.numeric(cf[-1])
  ) %>%
    filter(estimate != 0) %>%
    arrange(desc(abs(estimate))) %>%
    mutate(OR = round(exp(estimate), 3), estimate = round(estimate, 4))
}

coef_min <- extract_coefs(cv_lasso, "lambda.min")
coef_1se <- extract_coefs(cv_lasso, "lambda.1se")

cat("Non-zero coefficients at λ.min:", nrow(coef_min), "\n")
cat("Non-zero coefficients at λ.1se:", nrow(coef_1se), "\n")

coef_min %>%
  kbl(
    caption   = "LASSO coefficients at λ.min (sorted by |estimate|)",
    col.names = c("Feature", "Log-odds", "Odds Ratio")
  ) %>%
  kable_styling(bootstrap_options = c("striped", "condensed"), full_width = FALSE)

coef_min %>%
  mutate(
    direction = ifelse(estimate > 0, "Increases odds", "Decreases odds"),
    feature   = stringr::str_wrap(feature, 30)
  ) %>%
  ggplot(aes(x = estimate, y = reorder(feature, estimate), fill = direction)) +
  geom_col(width = 0.7) +
  geom_vline(xintercept = 0, linewidth = 0.4) +
  scale_fill_manual(values = c("Increases odds" = "#d73027", "Decreases odds" = "#2c7bb6")) +
  labs(
    x     = "LASSO coefficient (log-odds scale)",
    y     = NULL,
    fill  = NULL,
    title = "LASSO — Non-zero coefficients at λ.min"
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom", panel.grid.minor = element_blank())

prob_lasso_min <- as.numeric(predict(cv_lasso, newx = X_test, s = "lambda.min", type = "response"))
prob_lasso_1se <- as.numeric(predict(cv_lasso, newx = X_test, s = "lambda.1se", type = "response"))

roc_lasso_min <- pROC::roc(y_test, prob_lasso_min, quiet = TRUE)
roc_lasso_1se <- pROC::roc(y_test, prob_lasso_1se, quiet = TRUE)
auc_lasso_min <- as.numeric(pROC::auc(roc_lasso_min))
auc_lasso_1se <- as.numeric(pROC::auc(roc_lasso_1se))

thr_lasso_min  <- best_thresh(roc_lasso_min)
class_lasso_min <- as.integer(prob_lasso_min >= thr_lasso_min)
met_lasso_min   <- class_metrics(y_test, class_lasso_min)

cat(sprintf(
  "λ.min — AUC: %.4f  |  Threshold: %.4f  |  Sens: %.3f  |  Spec: %.3f  |  Bal.Acc: %.3f\n",
  auc_lasso_min, thr_lasso_min,
  met_lasso_min$sensitivity, met_lasso_min$specificity, met_lasso_min$balanced_acc
))

thr_lasso_1se   <- best_thresh(roc_lasso_1se)
class_lasso_1se <- as.integer(prob_lasso_1se >= thr_lasso_1se)
met_lasso_1se   <- class_metrics(y_test, class_lasso_1se)

cat(sprintf(
  "λ.1se — AUC: %.4f  |  Threshold: %.4f  |  Sens: %.3f  |  Spec: %.3f  |  Bal.Acc: %.3f\n",
  auc_lasso_1se, thr_lasso_1se,
  met_lasso_1se$sensitivity, met_lasso_1se$specificity, met_lasso_1se$balanced_acc
))

p_cm_min <- plot_cm(y_test, class_lasso_min, "LASSO (λ.min) — Confusion Matrix")
p_cm_1se <- plot_cm(y_test, class_lasso_1se, "LASSO (λ.1se) — Confusion Matrix")
p_cm_min | p_cm_1se

bind_rows(
  compute_metrics(y_test, prob_lasso_min, "LASSO λ.min"),
  compute_metrics(y_test, prob_lasso_1se, "LASSO λ.1se")
) %>%
  kbl(
    caption   = "LASSO — full evaluation metrics (test set, Youden threshold)",
    col.names = c("Model","AUC","PR-AUC","Log-Loss","Brier",
                  "Threshold","Sensitivity","Specificity","Precision","F1","MCC","Bal. Acc.")
  ) %>%
  kable_styling(bootstrap_options = c("striped","condensed"), full_width = TRUE)

eval_quad_plot(y_test, prob_lasso_min, "LASSO (λ.min)")

eval_quad_plot(y_test, prob_lasso_1se, "LASSO (λ.1se)")

# prob_logit / roc_logit / auc_logit already defined in section ii-b
roc_list <- list(
  "Logistic"     = roc_logit,
  "QDA"          = roc_qda,
  "Naive Bayes"  = roc_nb,
  "LASSO λ.min"  = roc_lasso_min,
  "LASSO λ.1se"  = roc_lasso_1se
)

pROC::ggroc(roc_list, linewidth = 0.8) +
  geom_abline(slope = 1, intercept = 1, linetype = "dashed", colour = "grey60") +
  scale_colour_viridis_d(option = "turbo", begin = 0.05, end = 0.92) +
  labs(
    x      = "Specificity",
    y      = "Sensitivity",
    colour = NULL,
    title  = "ROC curves — all methods (test set)"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

# All threshold/class/metric objects already defined in per-model sections
bind_rows(
  compute_metrics(test$arrested, prob_logit,     "Logistic"),
  compute_metrics(test$arrested, prob_qda,       "QDA"),
  compute_metrics(test$arrested, prob_nb,        "Naive Bayes"),
  compute_metrics(y_test,        prob_lasso_min, "LASSO λ.min"),
  compute_metrics(y_test,        prob_lasso_1se, "LASSO λ.1se")
) %>%
  kbl(
    caption   = "All methods — full evaluation metrics (test set, Youden threshold)",
    col.names = c("Method","AUC","PR-AUC","Log-Loss","Brier",
                  "Threshold","Sensitivity","Specificity","Precision","F1","MCC","Bal. Acc.")
  ) %>%
  kable_styling(bootstrap_options = c("striped","hover","condensed"), full_width = TRUE) %>%
  row_spec(which.max(c(
    as.numeric(pROC::auc(roc_logit)),
    auc_qda, auc_nb, auc_lasso_min, auc_lasso_1se
  )), bold = TRUE, colour = "white", background = "#2c7bb6")
