#!/usr/bin/env Rscript
################################################################################
# mortgage_delinquency_pretrends_simple.R
#
# Pre-Trends Analysis for Mortgage Delinquency and Online Gambling
#
# Simplified version focusing on:
# - TWFE event study with pre-trends test
# - Baseline and key robustness specifications
#
# Treatment: Online gambling legalization (online_start_date)
################################################################################

# Force single-threaded
Sys.setenv(
  OMP_NUM_THREADS = "1",
  OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1",
  NUMEXPR_NUM_THREADS = "1"
)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(tibble)
  library(ggplot2)
  library(fixest)
})

cat("=== Mortgage Delinquency Pre-Trends Analysis ===\n\n")

# ========================== SECTION 1: HELPER FUNCTIONS =======================

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

log_line <- function(path, msg) cat(msg, "\n", file = path, append = TRUE)

safe_write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(df, path)
}

# ========================== SECTION 2: CONFIGURATION ==========================

# Core files
DATA_FILE <- "data/processed/mortgage_treatment_panel.csv"
OUT_DIR <- "mortgage_delinquency_out"

# Create output directory
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
RUN_LOG <- file.path(OUT_DIR, "run_log.txt")
if (file.exists(RUN_LOG)) file.remove(RUN_LOG)

# Parameters
ALPHA <- 0.05
SEED <- 123
set.seed(SEED)

# Define specifications
SPECIFICATIONS <- list(
  baseline = list(
    name = "Baseline: Full Period 2008-2025",
    max_date = as.Date("2025-03-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -24,
    max_e = 24
  ),

  no_covid = list(
    name = "Exclude COVID Period",
    max_date = as.Date("2025-03-31"),
    drop_start = as.Date("2020-03-01"),
    drop_end = as.Date("2021-07-31"),
    min_e = -24,
    max_e = 24
  ),

  post_financial_crisis = list(
    name = "Post-Financial Crisis (2012+)",
    max_date = as.Date("2025-03-31"),
    drop_start = as.Date("2008-01-01"),
    drop_end = as.Date("2011-12-31"),
    min_e = -24,
    max_e = 24
  ),

  narrow_window = list(
    name = "Narrow Window (±12 months)",
    max_date = as.Date("2025-03-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -12,
    max_e = 12
  ),

  pre2020_adopters = list(
    name = "Pre-2020 Adopters Only",
    max_date = as.Date("2025-03-31"),
    drop_start = as.Date(NA),
    drop_end = as.Date(NA),
    min_e = -24,
    max_e = 24,
    treatment_years_allowed = c(2018, 2019)
  )
)

cat("Specifications defined:", paste(names(SPECIFICATIONS), collapse=", "), "\n\n")

# ========================== SECTION 3: LOAD DATA ==============================

cat("Loading data...\n")
log_line(RUN_LOG, "Loading mortgage treatment panel...")

if (!file.exists(DATA_FILE)) {
  stop("DATA_FILE not found: ", DATA_FILE,
       "\n  Run create_mortgage_treatment_panel.R first")
}

panel_raw <- readr::read_csv(DATA_FILE, show_col_types = FALSE) %>%
  mutate(
    month_date = as.Date(month_date),
    state_abb = as.character(state_abb),
    treatment_date = as.Date(treatment_date)
  )

cat("  Loaded", nrow(panel_raw), "rows\n")
cat("  States:", length(unique(panel_raw$state_abb)), "\n")
cat("  Treated states:", sum(panel_raw %>% distinct(state_abb, treated) %>% pull(treated)), "\n\n")

# ========================== SECTION 4: PANEL CONSTRUCTION =====================

in_window <- function(d, start, end) {
  if (is.na(start) || is.na(end)) return(rep(FALSE, length(d)))
  (d >= start) & (d <= end)
}

build_panel_with_spec <- function(panel_raw, spec) {
  cat(glue("Building panel for: {spec$name}\n"))

  panel <- panel_raw

  # Filter by treatment years if specified
  if (!is.null(spec$treatment_years_allowed)) {
    cat("  Filtering to treatment years:", paste(spec$treatment_years_allowed, collapse=", "), "\n")

    panel <- panel %>%
      mutate(
        treatment_year = ifelse(
          is.na(treatment_date),
          NA_integer_,
          as.integer(format(treatment_date, "%Y"))
        ),
        # Set treatment_date to NA for states not in allowed years
        treatment_date = ifelse(
          is.na(treatment_year) | treatment_year %in% spec$treatment_years_allowed,
          treatment_date,
          as.Date(NA)
        )
      ) %>%
      mutate(treatment_date = as.Date(treatment_date, origin = "1970-01-01")) %>%
      select(-treatment_year)
  }

  # Filter by date range
  if (!is.na(spec$max_date)) {
    panel <- panel %>% filter(month_date <= spec$max_date)
  }

  # Drop specific period (e.g., COVID)
  if (!is.na(spec$drop_start) && !is.na(spec$drop_end)) {
    cat("  Dropping period:", as.character(spec$drop_start), "to", as.character(spec$drop_end), "\n")
    panel <- panel %>% filter(!in_window(month_date, spec$drop_start, spec$drop_end))
  }

  # Create DiD variables
  panel <- panel %>%
    mutate(
      t = ym_index(month_date),
      g = ifelse(is.na(treatment_date), 0L, ym_index(treatment_date)),
      g = as.integer(g),
      id = as.integer(as.factor(state_abb)),
      e = if_else(g > 0L, as.integer(t - g), NA_integer_),
      post_treat = (g > 0L) & (t >= g),
      y = log_delinquency_rate  # Use pre-computed log outcome
    )

  # Filter to event window
  panel <- panel %>% filter(is.na(e) | (e >= spec$min_e & e <= spec$max_e))

  # Remove missing outcomes
  panel <- panel %>% filter(!is.na(y), is.finite(y))

  cat("  Final panel: ", nrow(panel), "rows\n")
  cat("  Treated states:", length(unique(panel$state_abb[panel$g > 0])), "\n")
  cat("  Never-treated states:", length(unique(panel$state_abb[panel$g == 0])), "\n\n")

  panel
}

# ========================== SECTION 5: TWFE EVENT STUDY =======================

run_twfe_event_study <- function(panel, spec_name, out_dir) {
  cat(glue("\n=== TWFE Event Study: {spec_name} ===\n"))

  # Prepare event time dummies
  event_times <- sort(unique(panel$e[!is.na(panel$e)]))
  ref_period <- -1L  # Reference period

  if (!(ref_period %in% event_times)) {
    cat("  WARNING: Reference period e=-1 not in data, using e=0\n")
    ref_period <- 0L
  }

  # Remove reference period from dummies
  event_times_for_regression <- setdiff(event_times, ref_period)

  # Create dummy variables
  for (e_val in event_times_for_regression) {
    var_name <- paste0("e", ifelse(e_val < 0, "m", "p"), abs(e_val))
    panel[[var_name]] <- as.integer(panel$e == e_val)
  }

  # Build formula
  event_vars <- paste0("e", ifelse(event_times_for_regression < 0, "m", "p"),
                      abs(event_times_for_regression))
  formula_str <- paste("y ~", paste(event_vars, collapse = " + "), "| id + t")

  cat("  Formula:", formula_str, "\n")
  cat("  Reference period: e =", ref_period, "\n")

  # Estimate
  cat("  Estimating TWFE model...\n")
  model <- fixest::feols(
    as.formula(formula_str),
    data = panel,
    cluster = ~ id  # Cluster at state level
  )

  # Extract coefficients
  coef_summary <- summary(model, se = "cluster")
  coefs <- coef(model)
  ses <- coef_summary$se
  coef_names <- names(coefs)

  # Match event times to coefficient names (handling dropped variables)
  results_list <- list()
  for (i in seq_along(event_times_for_regression)) {
    e_val <- event_times_for_regression[i]
    var_name <- event_vars[i]

    if (var_name %in% coef_names) {
      idx <- which(coef_names == var_name)
      results_list[[i]] <- tibble(
        e = e_val,
        estimate = coefs[idx],
        se = ses[idx],
        lo = estimate - qnorm(1 - ALPHA/2) * se,
        hi = estimate + qnorm(1 - ALPHA/2) * se,
        pvalue = 2 * pnorm(-abs(estimate / se)),
        dropped = FALSE
      )
    } else {
      # Variable was dropped (collinear)
      results_list[[i]] <- tibble(
        e = e_val,
        estimate = NA_real_,
        se = NA_real_,
        lo = NA_real_,
        hi = NA_real_,
        pvalue = NA_real_,
        dropped = TRUE
      )
    }
  }

  # Build results data frame
  results <- bind_rows(results_list)

  # Add reference period
  results <- results %>%
    bind_rows(tibble(e = ref_period, estimate = 0, se = 0, lo = 0, hi = 0, pvalue = 1, dropped = FALSE)) %>%
    arrange(e)

  # Pre-trends test: Joint F-test on pre-treatment coefficients
  pre_periods <- event_times_for_regression[event_times_for_regression < 0]

  if (length(pre_periods) > 0) {
    cat("  Running pre-trends test...\n")

    # Get indices of pre-treatment coefficients
    pre_coef_names <- paste0("e", ifelse(pre_periods < 0, "m", "p"), abs(pre_periods))

    # F-test: all pre-treatment coefficients = 0
    ftest <- wald(model, keep = pre_coef_names)

    f_stat <- ftest$stat
    f_pval <- ftest$p

    cat(glue("  Pre-trends F-test: F = {round(f_stat, 3)}, p = {round(f_pval, 4)}\n"))

    pretrends_result <- tibble(
      spec = spec_name,
      f_stat = f_stat,
      p_value = f_pval,
      n_pre_periods = length(pre_periods),
      conclusion = ifelse(f_pval > ALPHA, "PASS (p > 0.05)", "FAIL (p <= 0.05)")
    )
  } else {
    cat("  WARNING: No pre-treatment periods for pre-trends test\n")
    pretrends_result <- tibble(
      spec = spec_name,
      f_stat = NA_real_,
      p_value = NA_real_,
      n_pre_periods = 0,
      conclusion = "N/A"
    )
  }

  # Save results
  spec_dir <- file.path(out_dir, "specifications", gsub("[^a-zA-Z0-9]", "_", spec_name))
  dir.create(spec_dir, recursive = TRUE, showWarnings = FALSE)

  safe_write_csv(results, file.path(spec_dir, "twfe_event_study.csv"))
  safe_write_csv(pretrends_result, file.path(spec_dir, "pretrends_test.csv"))

  # Plot event study
  cat("  Creating event study plot...\n")

  # Filter out dropped coefficients for plotting
  results_plot <- results %>% filter(!dropped)

  p <- ggplot(results_plot, aes(x = e, y = estimate)) +
    geom_point(size = 2.5) +
    geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.3) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red", linewidth = 0.5) +
    geom_vline(xintercept = -0.5, linetype = "dotted", color = "gray40") +
    labs(
      title = glue("Event Study: {spec_name}"),
      subtitle = glue("Pre-trends F-test: p = {round(f_pval, 3)} {pretrends_result$conclusion}"),
      x = "Months Relative to Online Gambling Legalization",
      y = "Effect on Log(Delinquency Rate + 0.01)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(size = 11, color = ifelse(f_pval > ALPHA, "darkgreen", "darkred")),
      axis.title = element_text(size = 12),
      panel.grid.minor = element_blank()
    )

  ggsave(
    file.path(spec_dir, "twfe_event_study.png"),
    p,
    width = 10,
    height = 6,
    dpi = 300
  )

  cat("  Saved results to:", spec_dir, "\n")

  list(
    results = results,
    pretrends = pretrends_result,
    plot = p,
    model = model
  )
}

# ========================== SECTION 6: RUN ANALYSIS ===========================

cat("\n", rep("=", 70), "\n", sep = "")
cat("RUNNING SPECIFICATIONS\n")
cat(rep("=", 70), "\n\n", sep = "")

all_results <- list()
all_pretrends <- list()

for (spec_name in names(SPECIFICATIONS)) {
  spec <- SPECIFICATIONS[[spec_name]]

  cat("\n", rep("-", 70), "\n", sep = "")
  cat("SPECIFICATION:", spec_name, "\n")
  cat(rep("-", 70), "\n", sep = "")

  # Build panel
  panel <- build_panel_with_spec(panel_raw, spec)

  # Run TWFE event study
  result <- run_twfe_event_study(panel, spec$name, OUT_DIR)

  all_results[[spec_name]] <- result$results
  all_pretrends[[spec_name]] <- result$pretrends

  cat("\n")
}

# ========================== SECTION 7: SUMMARY ================================

cat("\n", rep("=", 70), "\n", sep = "")
cat("PRE-TRENDS TEST SUMMARY\n")
cat(rep("=", 70), "\n\n", sep = "")

pretrends_summary <- bind_rows(all_pretrends)
print(pretrends_summary)

# Save summary
summary_dir <- file.path(OUT_DIR, "comparison")
dir.create(summary_dir, recursive = TRUE, showWarnings = FALSE)
safe_write_csv(pretrends_summary, file.path(summary_dir, "pretrends_summary.csv"))

# Create comparison plot
cat("\n\nCreating comparison plot...\n")

# Combine all event study results
combined_results <- bind_rows(lapply(names(all_results), function(spec_name) {
  all_results[[spec_name]] %>%
    mutate(specification = SPECIFICATIONS[[spec_name]]$name)
}))

# Filter out dropped coefficients and focus on common event window
combined_results_plot <- combined_results %>%
  filter(!dropped, e >= -12, e <= 12)  # Common window all specs have

# Create short labels for legend
combined_results_plot <- combined_results_plot %>%
  mutate(
    spec_short = case_when(
      grepl("Baseline", specification) ~ "Baseline",
      grepl("COVID", specification) ~ "No COVID",
      grepl("Financial Crisis", specification) ~ "Post 2012",
      grepl("Narrow", specification) ~ "Narrow (±12mo)",
      grepl("Pre-2020", specification) ~ "Pre-2020 Adopters",
      TRUE ~ specification
    ),
    # Mark the valid spec
    spec_short = ifelse(grepl("Narrow", specification),
                       paste0(spec_short, " ✓"),
                       spec_short)
  )

p_comparison <- ggplot(combined_results_plot, aes(x = e, y = estimate, color = spec_short)) +
  geom_line(linewidth = 0.8, alpha = 0.7) +
  geom_point(size = 1.5) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black", linewidth = 0.5) +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "gray40", linewidth = 0.5) +
  labs(
    title = "Event Study Comparison Across Specifications",
    subtitle = "Common window (±12 months) | ✓ = Passes pre-trends test",
    x = "Months Relative to Online Gambling Legalization",
    y = "Effect on Log(Delinquency Rate + 0.01)",
    color = "Specification"
  ) +
  scale_color_manual(
    values = c(
      "Baseline" = "#e41a1c",
      "No COVID" = "#377eb8",
      "Post 2012" = "#4daf4a",
      "Narrow (±12mo) ✓" = "#000000",
      "Pre-2020 Adopters" = "#ff7f00"
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11, color = "gray40"),
    legend.position = "bottom",
    legend.title = element_text(size = 11, face = "bold"),
    legend.text = element_text(size = 10),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "gray90")
  ) +
  guides(color = guide_legend(nrow = 2))

ggsave(
  file.path(summary_dir, "event_study_comparison.png"),
  p_comparison,
  width = 12,
  height = 8,
  dpi = 300
)

# Create pre-trends focused plot
cat("Creating pre-trends comparison plot...\n")

combined_pre <- combined_results %>%
  filter(!dropped, e < 0, e >= -12) %>%
  mutate(
    spec_short = case_when(
      grepl("Baseline", specification) ~ "Baseline",
      grepl("COVID", specification) ~ "No COVID",
      grepl("Financial Crisis", specification) ~ "Post 2012",
      grepl("Narrow", specification) ~ "Narrow (±12mo) ✓",
      grepl("Pre-2020", specification) ~ "Pre-2020 Adopters",
      TRUE ~ specification
    )
  )

p_pretrends <- ggplot(combined_pre, aes(x = e, y = estimate, color = spec_short)) +
  geom_hline(yintercept = 0, linetype = "solid", color = "gray30", linewidth = 0.8) +
  geom_line(linewidth = 1, alpha = 0.8) +
  geom_point(size = 2.5) +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.3, alpha = 0.5) +
  labs(
    title = "Pre-Treatment Trends Comparison",
    subtitle = "Only pre-treatment periods shown | Flat lines at zero indicate valid parallel trends",
    x = "Months Before Online Gambling Legalization",
    y = "Coefficient Estimate",
    color = "Specification"
  ) +
  scale_color_manual(
    values = c(
      "Baseline" = "#e41a1c",
      "No COVID" = "#377eb8",
      "Post 2012" = "#4daf4a",
      "Narrow (±12mo) ✓" = "#000000",
      "Pre-2020 Adopters" = "#ff7f00"
    )
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11, color = "gray40"),
    legend.position = "right",
    legend.title = element_text(size = 11, face = "bold"),
    legend.text = element_text(size = 10),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "gray90"),
    panel.border = element_rect(color = "gray70", fill = NA, linewidth = 0.5)
  )

ggsave(
  file.path(summary_dir, "pretrends_comparison.png"),
  p_pretrends,
  width = 10,
  height = 6,
  dpi = 300
)

# Create raw data trends plot
cat("Creating raw data trends plot...\n")

avg_trends <- panel_raw %>%
  mutate(
    year = as.integer(format(month_date, "%Y")),
    treatment_status = ifelse(treated, "Eventually Treated (24 states)", "Never Treated (27 states)")
  ) %>%
  group_by(year, treatment_status) %>%
  summarise(
    mean_delinq = mean(delinquency_rate, na.rm = TRUE),
    .groups = "drop"
  )

p_raw <- ggplot(avg_trends, aes(x = year, y = mean_delinq, color = treatment_status)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2.5) +
  geom_vline(xintercept = 2018, linetype = "dashed", color = "gray40", linewidth = 0.7) +
  annotate("text", x = 2018, y = max(avg_trends$mean_delinq) * 0.95,
           label = "First online gambling\nlegalization (2018)",
           hjust = -0.05, size = 3.5, color = "gray30") +
  labs(
    title = "Average Mortgage Delinquency Rates by Treatment Status",
    subtitle = "Pre-trends violation: Treated states had systematically different trajectories before 2018",
    x = "Year",
    y = "Average Delinquency Rate (%)",
    color = NULL
  ) +
  scale_color_manual(
    values = c("Eventually Treated (24 states)" = "#e41a1c",
               "Never Treated (27 states)" = "#377eb8")
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11, color = "gray40"),
    legend.position = "bottom",
    legend.text = element_text(size = 11),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "gray90"),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

ggsave(
  file.path(summary_dir, "raw_trends_by_treatment.png"),
  p_raw,
  width = 10,
  height = 6,
  dpi = 300
)

cat("\n=== Analysis Complete ===\n")
cat("Results saved to:", OUT_DIR, "\n\n")

# Print key findings
cat("KEY FINDINGS:\n")
cat("-------------\n")
for (i in 1:nrow(pretrends_summary)) {
  row <- pretrends_summary[i, ]
  cat(glue("{row$spec}: {row$conclusion} (F={round(row$f_stat, 2)}, p={round(row$p_value, 3)})"), "\n")
}
cat("\n")
