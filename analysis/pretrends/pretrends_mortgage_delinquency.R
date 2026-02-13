#!/usr/bin/env Rscript
################################################################################
# pretrends_mortgage_delinquency.R
#
# Pre-trends diagnostics for state-month mortgage delinquency panel:
#   A) CS-DiD (Callaway-Sant'Anna) dynamic event study — analytic + bootstrap
#   B) TWFE / Sun-Abraham event study
#
# Treatment: online sports gambling legalization (staggered across states)
# Outcome:   % of mortgages 90+ days delinquent (state-level, monthly)
#
# All configuration via environment variables (see SECTION 2).
# Run via: bash scripts/run_pretrends_mortgage.sh
################################################################################

# Force single-threaded BLAS to avoid contention under mclapply
Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1",
  NUMEXPR_NUM_THREADS = "1"
)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(tibble)
  library(ggplot2)
  library(fixest)
  library(patchwork)
  library(did)
  library(glue)
})

################################################################################
# SECTION 1: HELPER FUNCTIONS
################################################################################

getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}

parse_num <- function(x, default = NA_real_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.numeric(x))
}

parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.integer(x))
}

parse_bool <- function(x, default = FALSE) {
  if (!nzchar(x)) return(default)
  x <- toupper(trimws(x))
  x %in% c("1", "TRUE", "T", "YES", "Y")
}

parse_chr_list <- function(x, default = character()) {
  if (!nzchar(x)) return(default)
  trimws(strsplit(x, ",", fixed = TRUE)[[1]])
}

parse_date <- function(x, default = as.Date(NA)) {
  if (!nzchar(x)) return(default)
  out <- suppressWarnings(as.Date(x))
  if (is.na(out)) default else out
}

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

state_name_to_abb <- function(state_name) {
  state_name <- trimws(state_name)
  m <- setNames(state.abb, state.name)
  m2 <- c(m, "District of Columbia" = "DC")
  unname(m2[state_name])
}

safe_write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(df, path)
}

################################################################################
# SECTION 2: CONFIGURATION
################################################################################

MORTGAGE_FILE <- getenv1("MORTGAGE_FILE", "data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv")
TREAT_FILE    <- getenv1("TREAT_FILE", "data/raw/sports_gambling_legalization_dates.csv")
TREAT_DATE_COL <- getenv1("TREAT_DATE_COL", "online_start_date")

EXCLUDE_STATES <- parse_chr_list(getenv1("EXCLUDE_STATES", ""))
MIN_DATE      <- as.Date(getenv1("MIN_DATE", "2016-01-01"))
MAX_DATE      <- as.Date(getenv1("MAX_DATE", "2024-12-31"))
DROP_START    <- parse_date(getenv1("DROP_START", ""))
DROP_END      <- parse_date(getenv1("DROP_END", ""))
COVERAGE_THRESHOLD_RAW <- getenv1("COVERAGE_THRESHOLD", "")
COVERAGE_THRESHOLD <- if (nzchar(COVERAGE_THRESHOLD_RAW)) {
  parse_int(COVERAGE_THRESHOLD_RAW, 0L)
} else {
  NA_integer_
}
BALANCE_COMMON_MONTHS <- parse_bool(getenv1("BALANCE_COMMON_MONTHS", "TRUE"), TRUE)

OUTCOME       <- getenv1("OUTCOME", "delinq_pct")

CONTROL_GROUP <- getenv1("CONTROL_GROUP", "notyettreated")
EST_METHOD    <- getenv1("EST_METHOD", "reg")
ALLOW_UNBALANCED <- parse_bool(getenv1("ALLOW_UNBALANCED_PANEL", "TRUE"), TRUE)
PRE_WINDOW    <- eval(parse(text = getenv1("PRE_WINDOW", "-12:-1")))

CS_ANALYTIC   <- parse_bool(getenv1("CS_ANALYTIC", "TRUE"), TRUE)
CS_BOOTSTRAP  <- parse_bool(getenv1("CS_BOOTSTRAP", "TRUE"), TRUE)
CS_BITERS     <- parse_int(getenv1("CS_BITERS", "199"), 199L)
CS_FASTER_MODE <- parse_bool(getenv1("CS_FASTER_MODE", "TRUE"), TRUE)

ALPHA         <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
SEED          <- parse_int(getenv1("SEED", "123"), 123L)

OUT_DIR       <- getenv1("OUT_DIR", "output/pretrends_mortgage_delinquency")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

LOG_FILE <- file.path(OUT_DIR, "run_log.txt")

log_msg <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- paste0("[", ts, "] ", msg)
  cat(line, "\n")
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}

# Initialize log
cat("", file = LOG_FILE)

log_msg("=== Pre-trends diagnostics: Mortgage Delinquency ===")
log_msg(glue("MORTGAGE_FILE: {MORTGAGE_FILE}"))
log_msg(glue("TREAT_FILE: {TREAT_FILE}"))
log_msg(glue("TREAT_DATE_COL: {TREAT_DATE_COL}"))
log_msg(glue("EXCLUDE_STATES: {paste(EXCLUDE_STATES, collapse=',')}"))
log_msg(glue("MIN_DATE: {MIN_DATE}  MAX_DATE: {MAX_DATE}"))
log_msg(glue("DROP_START: {ifelse(is.na(DROP_START), '<none>', as.character(DROP_START))}  DROP_END: {ifelse(is.na(DROP_END), '<none>', as.character(DROP_END))}"))
log_msg(glue("COVERAGE_THRESHOLD (requested): {ifelse(is.finite(COVERAGE_THRESHOLD), COVERAGE_THRESHOLD, 'auto')}"))
log_msg(glue("BALANCE_COMMON_MONTHS: {BALANCE_COMMON_MONTHS}"))
log_msg(glue("OUTCOME: {OUTCOME}"))
log_msg(glue("CONTROL_GROUP: {CONTROL_GROUP}  EST_METHOD: {EST_METHOD}"))
log_msg(glue("ALLOW_UNBALANCED_PANEL: {ALLOW_UNBALANCED}"))
log_msg(glue("PRE_WINDOW: {paste(range(PRE_WINDOW), collapse=' to ')}"))
log_msg(glue("CS_ANALYTIC: {CS_ANALYTIC}  CS_BOOTSTRAP: {CS_BOOTSTRAP}  CS_BITERS: {CS_BITERS}"))
log_msg(glue("CS_FASTER_MODE: {CS_FASTER_MODE}"))
log_msg(glue("ALPHA: {ALPHA}  SEED: {SEED}"))
log_msg(glue("OUT_DIR: {OUT_DIR}"))

if (!file.exists(MORTGAGE_FILE)) stop("MORTGAGE_FILE not found: ", MORTGAGE_FILE, call. = FALSE)
if (!file.exists(TREAT_FILE))    stop("TREAT_FILE not found: ", TREAT_FILE, call. = FALSE)

################################################################################
# SECTION 3: LOAD AND PREPARE PANEL
################################################################################

log_msg("Loading mortgage delinquency data...")

mort_wide <- readr::read_csv(MORTGAGE_FILE, show_col_types = FALSE)

# Keep only state-level rows
mort_wide <- mort_wide %>% filter(RegionType == "State")
log_msg(glue("  State rows: {nrow(mort_wide)}"))

# Identify month columns (pattern: YYYY-MM)
all_cols <- colnames(mort_wide)
month_cols <- grep("^\\d{4}-\\d{2}$", all_cols, value = TRUE)
log_msg(glue("  Month columns: {length(month_cols)} ({min(month_cols)} to {max(month_cols)})"))

# Pivot wide to long
mort_long <- mort_wide %>%
  select(Name, all_of(month_cols)) %>%
  pivot_longer(
    cols = all_of(month_cols),
    names_to = "month_str",
    values_to = "delinq_pct"
  ) %>%
  mutate(
    state_abb  = state_name_to_abb(Name),
    month_date = as.Date(paste0(month_str, "-01")),
    delinq_pct = as.numeric(delinq_pct)
  ) %>%
  filter(!is.na(state_abb)) %>%
  select(state_abb, month_date, delinq_pct)

log_msg(glue("  Long panel: {nrow(mort_long)} rows, {n_distinct(mort_long$state_abb)} states"))

# Load treatment schedule
log_msg("Loading treatment schedule...")
treat_raw <- readr::read_csv(TREAT_FILE, show_col_types = FALSE)

if (!TREAT_DATE_COL %in% colnames(treat_raw)) {
  stop("TREAT_DATE_COL '", TREAT_DATE_COL, "' not found in treatment file. Available: ",
       paste(colnames(treat_raw), collapse = ", "), call. = FALSE)
}

treat_sched <- treat_raw %>%
  transmute(
    state_abb = state_name_to_abb(state),
    treat_start = as.Date(.data[[TREAT_DATE_COL]])
  ) %>%
  filter(!is.na(state_abb))

log_msg(glue("  Treatment states: {sum(!is.na(treat_sched$treat_start))} with {TREAT_DATE_COL}"))

# Merge treatment onto panel
panel0 <- mort_long %>%
  left_join(treat_sched, by = "state_abb")

# Apply filters
if (length(EXCLUDE_STATES) > 0 && any(nzchar(EXCLUDE_STATES))) {
  panel0 <- panel0 %>% filter(!(state_abb %in% EXCLUDE_STATES))
}
if (!is.na(MIN_DATE)) panel0 <- panel0 %>% filter(month_date >= MIN_DATE)
if (!is.na(MAX_DATE)) panel0 <- panel0 %>% filter(month_date <= MAX_DATE)

if (xor(is.na(DROP_START), is.na(DROP_END))) {
  stop("If setting DROP_START or DROP_END, set both (e.g., DROP_START=2020-03-01 DROP_END=2021-07-31).", call. = FALSE)
}
if (!is.na(DROP_START) && !is.na(DROP_END)) {
  n0 <- nrow(panel0)
  panel0 <- panel0 %>% filter(!(month_date >= DROP_START & month_date <= DROP_END))
  log_msg(glue("Dropped months in [{DROP_START}, {DROP_END}]: removed {n0 - nrow(panel0)} rows"))
}

# Coverage threshold
coverage <- panel0 %>%
  count(state_abb, name = "n_months") %>%
  arrange(desc(n_months), state_abb)

max_coverage <- if (nrow(coverage) > 0) max(coverage$n_months, na.rm = TRUE) else NA_integer_
if (!is.finite(COVERAGE_THRESHOLD)) {
  COVERAGE_THRESHOLD <- max_coverage
}
log_msg(glue("COVERAGE_THRESHOLD (used): {COVERAGE_THRESHOLD}  (max_coverage={max_coverage})"))

keep_states <- coverage %>% filter(n_months >= COVERAGE_THRESHOLD) %>% pull(state_abb)
panel <- panel0 %>% filter(state_abb %in% keep_states)

if (nrow(panel) < 200) stop("Too few rows after filtering; panel size=", nrow(panel), call. = FALSE)

# Balance common months
if (isTRUE(BALANCE_COMMON_MONTHS)) {
  n_states_tmp <- n_distinct(panel$state_abb)
  common_months <- panel %>%
    count(month_date, name = "n_states") %>%
    filter(n_states == n_states_tmp) %>%
    pull(month_date)
  panel <- panel %>% filter(month_date %in% common_months)
}

# Create DiD identifiers
panel <- panel %>%
  mutate(
    id = as.integer(as.factor(state_abb)),
    t  = ym_index(month_date),
    g  = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
    g  = as.integer(g),
    event_time = ifelse(g > 0L, t - g, NA_integer_),
    y  = dplyr::case_when(
      OUTCOME == "delinq_pct"     ~ delinq_pct,
      OUTCOME == "log_delinq_pct" ~ log(pmax(delinq_pct, 0.001)),
      TRUE ~ NA_real_
    )
  )

if (!OUTCOME %in% c("delinq_pct", "log_delinq_pct")) {
  stop("Unknown OUTCOME: ", OUTCOME, ". Use 'delinq_pct' or 'log_delinq_pct'.", call. = FALSE)
}

n_states  <- n_distinct(panel$id)
n_treated <- n_distinct(panel$state_abb[panel$g > 0L])
n_never   <- n_distinct(panel$state_abb[panel$g == 0L])
n_cohorts <- n_distinct(panel$g[panel$g > 0L])
t_vals    <- sort(unique(panel$t))
n_t       <- length(t_vals)

if (n_states < 8L) stop("Too few states after filtering; n_states=", n_states, call. = FALSE)

log_msg(glue("Panel: {n_states} states ({n_treated} treated, {n_never} never-treated), {n_cohorts} cohorts, {n_t} months, {nrow(panel)} obs"))

panel_summary <- tibble(
  n_states = n_states, n_treated = n_treated, n_never_treated = n_never,
  n_cohorts = n_cohorts, n_months = n_t, n_obs = nrow(panel),
  min_date = min(panel$month_date), max_date = max(panel$month_date),
  coverage_threshold = COVERAGE_THRESHOLD, outcome = OUTCOME,
  treatment = TREAT_DATE_COL
)
safe_write_csv(panel_summary, file.path(OUT_DIR, "panel_summary.csv"))

################################################################################
# SECTION 4: CS-DiD PRETRENDS (Analysis A)
################################################################################

HEADLINE_METHOD <- "analytic"

run_cs_pretrends <- function(panel_df, bstrap, biters, label) {
  log_msg(glue("Running CS-DiD pretrends ({label})..."))

  dat <- data.frame(
    id = panel_df$id,
    t  = panel_df$t,
    g  = panel_df$g,
    y  = panel_df$y
  )

  mp <- tryCatch({
    suppressMessages(suppressWarnings({
      did::att_gt(
        yname = "y", tname = "t", idname = "id", gname = "g",
        xformla = ~1, data = dat, panel = TRUE,
        control_group = CONTROL_GROUP,
        allow_unbalanced_panel = ALLOW_UNBALANCED,
        est_method = EST_METHOD,
        faster_mode = CS_FASTER_MODE,
        bstrap = bstrap,
        biters = biters,
        cband = TRUE,
        clustervars = "id"
      )
    }))
  }, error = function(e) {
    log_msg(glue("  ERROR in att_gt() ({label}): {conditionMessage(e)}"))
    return(NULL)
  })

  if (is.null(mp)) return(NULL)

  dyn <- tryCatch({
    did::aggte(mp, type = "dynamic", na.rm = TRUE)
  }, error = function(e) {
    log_msg(glue("  ERROR in aggte(dynamic) ({label}): {conditionMessage(e)}"))
    return(NULL)
  })

  if (is.null(dyn)) return(NULL)

  n_cl <- n_distinct(panel_df$id)

  es <- tibble(
    egt       = as.integer(dyn$egt),
    att       = as.numeric(dyn$att.egt),
    se        = as.numeric(dyn$se.egt),
    crit_val  = as.numeric(dyn$crit.val.egt),
    method    = label
  ) %>%
    mutate(
      t_stat = ifelse(is.finite(att) & is.finite(se) & se > 0, att / se, NA_real_),
      p_value_ptwise = ifelse(
        is.finite(t_stat),
        2 * pt(-abs(t_stat), df = n_cl - 1),
        NA_real_
      ),
      ci_lo = att - qnorm(1 - ALPHA / 2) * se,
      ci_hi = att + qnorm(1 - ALPHA / 2) * se
    )

  # Pre-trend joint test: Holm-adjusted max-|t|
  pre <- es %>% filter(egt %in% PRE_WINDOW, is.finite(t_stat))
  if (nrow(pre) > 0) {
    raw_p <- pre$p_value_ptwise
    holm_p <- p.adjust(raw_p, method = "holm")
    joint_reject <- any(holm_p < ALPHA)
    joint_min_holm_p <- min(holm_p)
    max_abs_t <- max(abs(pre$t_stat))
  } else {
    joint_reject <- NA
    joint_min_holm_p <- NA_real_
    max_abs_t <- NA_real_
  }

  # Overall ATT
  ovr <- tryCatch({
    did::aggte(mp, type = "simple", na.rm = TRUE)
  }, error = function(e) NULL)

  overall_att <- if (!is.null(ovr)) as.numeric(ovr$overall.att) else NA_real_
  overall_se  <- if (!is.null(ovr)) as.numeric(ovr$overall.se)  else NA_real_

  log_msg(glue("  {label}: {nrow(pre)} pre-periods, joint_reject={joint_reject}, min_holm_p={round(joint_min_holm_p,4)}, overall_att={round(overall_att,4)}"))

  list(
    event_study = es,
    n_pre = nrow(pre),
    joint_reject = joint_reject,
    joint_min_holm_p = joint_min_holm_p,
    max_abs_t = max_abs_t,
    overall_att = overall_att,
    overall_se = overall_se,
    n_clusters = n_cl,
    n_obs = nrow(panel_df),
    mp = mp,
    dyn = dyn
  )
}

cs_analytic_res  <- NULL
cs_bootstrap_res <- NULL

if (CS_ANALYTIC) {
  cs_analytic_res <- run_cs_pretrends(panel, bstrap = FALSE, biters = 0, label = "analytic")
  if (!is.null(cs_analytic_res)) {
    safe_write_csv(cs_analytic_res$event_study, file.path(OUT_DIR, "event_study_cs_analytic.csv"))
  }
}

if (CS_BOOTSTRAP) {
  cs_bootstrap_res <- run_cs_pretrends(panel, bstrap = TRUE, biters = CS_BITERS, label = "bootstrap")
  if (!is.null(cs_bootstrap_res)) {
    safe_write_csv(cs_bootstrap_res$event_study, file.path(OUT_DIR, "event_study_cs_bootstrap.csv"))
  }
}

################################################################################
# SECTION 5: TWFE / SUN-ABRAHAM PRETRENDS (Analysis B)
################################################################################

log_msg("Running TWFE/Sun-Abraham pretrends...")

sa_result <- NULL
sa_mod <- tryCatch({
  fixest::feols(y ~ sunab(g, t) | id + t, data = panel, cluster = ~id)
}, error = function(e) {
  log_msg(glue("ERROR in Sun-Abraham model: {conditionMessage(e)}"))
  NULL
})

if (!is.null(sa_mod)) {
  sa_coefs <- coef(sa_mod)
  sa_ses <- se(sa_mod)
  coef_names <- names(sa_coefs)

  # Parse event times from coefficient names (sunab names: "t::VALUE")
  sunab_mask <- grepl("::", coef_names)
  sunab_names <- coef_names[sunab_mask]

  extract_event_time <- function(name) {
    parts <- strsplit(name, "::", fixed = TRUE)[[1]]
    if (length(parts) >= 2) {
      return(suppressWarnings(as.integer(parts[length(parts)])))
    }
    NA_integer_
  }

  event_times <- vapply(sunab_names, extract_event_time, integer(1))

  sa_es <- tibble(
    egt = event_times,
    att = as.numeric(sa_coefs[sunab_names]),
    se  = as.numeric(sa_ses[sunab_names]),
    coef_name = sunab_names,
    method = "TWFE_SunAb"
  ) %>%
    filter(!is.na(egt)) %>%
    mutate(
      t_stat = att / se,
      p_value = 2 * pt(-abs(t_stat), df = sa_mod$nobs - length(sa_coefs)),
      ci_lo = att - qnorm(1 - ALPHA / 2) * se,
      ci_hi = att + qnorm(1 - ALPHA / 2) * se
    ) %>%
    arrange(egt)

  # Add reference period (event_time = -1)
  if (!(-1L %in% sa_es$egt)) {
    sa_es <- bind_rows(
      sa_es,
      tibble(egt = -1L, att = 0, se = 0, coef_name = "Reference",
             method = "TWFE_SunAb", t_stat = NA_real_, p_value = NA_real_,
             ci_lo = 0, ci_hi = 0)
    ) %>%
      arrange(egt)
  }

  # Joint Wald F-test on pre-period
  pre_terms <- sunab_names[!is.na(event_times) & event_times %in% PRE_WINDOW]
  wald_f <- wald_p <- NA_real_
  wald_df1 <- wald_df2 <- NA_integer_
  joint_reject_sa <- NA

  if (length(pre_terms) > 0) {
    wald_res <- tryCatch(
      fixest::wald(sa_mod, keep = pre_terms),
      error = function(e) NULL
    )
    if (!is.null(wald_res)) {
      wald_f  <- as.numeric(wald_res$stat)
      wald_p  <- as.numeric(wald_res$p)
      wald_df1 <- as.integer(wald_res$df1)
      wald_df2 <- as.integer(wald_res$df2)
      joint_reject_sa <- wald_p < ALPHA
    }
  }

  log_msg(glue("  SunAb: {sum(sa_es$egt %in% PRE_WINDOW & !is.na(sa_es$t_stat))} pre-periods, Wald F={round(wald_f,3)}, p={round(wald_p,4)}, reject={joint_reject_sa}"))

  sa_result <- list(
    model = sa_mod,
    event_study = sa_es,
    wald_f = wald_f, wald_p = wald_p, wald_df1 = wald_df1, wald_df2 = wald_df2,
    joint_reject = joint_reject_sa,
    n_clusters = n_states,
    n_obs = nrow(panel)
  )

  safe_write_csv(sa_es %>% select(-coef_name), file.path(OUT_DIR, "event_study_twfe_sunab.csv"))
}

################################################################################
# SECTION 6: PLOTS
################################################################################

log_msg("Generating plots...")

y_label <- if (OUTCOME == "delinq_pct") {
  "ATT (percentage points)"
} else {
  "ATT (log delinquency rate)"
}

# Build a sample-description label for plot subtitles
sample_label <- glue("{format(min(panel$month_date), '%b %Y')}\u2013{format(max(panel$month_date), '%b %Y')}")
if (!is.na(DROP_START) && !is.na(DROP_END)) {
  sample_label <- glue("{sample_label}, excl. {format(DROP_START, '%b %Y')}\u2013{format(DROP_END, '%b %Y')}")
}

base_theme <- theme_minimal(base_size = 12)
zero_line <- geom_hline(yintercept = 0, linetype = "dashed", color = "red", linewidth = 0.5)
treat_line <- geom_vline(xintercept = -0.5, linetype = "dotted", color = "gray40", linewidth = 0.5)

make_es_plot <- function(es_df, title, subtitle = "", color = "steelblue") {
  if (is.null(es_df) || nrow(es_df) == 0) return(NULL)

  es_plot <- es_df %>%
    filter(is.finite(att), is.finite(se), se > 0) %>%
    ggplot(aes(x = egt, y = att)) +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.2, fill = color) +
    geom_point(size = 2, color = color) +
    geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.2, color = color) +
    zero_line + treat_line +
    base_theme +
    labs(
      title = title,
      subtitle = subtitle,
      x = "Event Time (months relative to online gambling legalization)",
      y = y_label
    )

  # Shade pre-window
  pre_range <- range(PRE_WINDOW)
  es_plot <- es_plot +
    annotate("rect",
             xmin = pre_range[1] - 0.5, xmax = pre_range[2] + 0.5,
             ymin = -Inf, ymax = Inf,
             alpha = 0.05, fill = "orange")

  es_plot
}

# Plot 1: CS analytic event study
if (!is.null(cs_analytic_res)) {
  p1 <- make_es_plot(
    cs_analytic_res$event_study,
    "CS-DiD Event Study: Online Gambling \u2192 Mortgage Delinquency (Analytic SEs)",
    glue("Pre-trend Holm p = {round(cs_analytic_res$joint_min_holm_p, 4)} | {cs_analytic_res$n_clusters} clusters, {cs_analytic_res$n_obs} obs | {sample_label}")
  )
  if (!is.null(p1)) ggsave(file.path(OUT_DIR, "cs_event_study_analytic.png"), p1, width = 10, height = 6, dpi = 300)
}

# Plot 2: CS bootstrap event study
if (!is.null(cs_bootstrap_res)) {
  p2 <- make_es_plot(
    cs_bootstrap_res$event_study,
    "CS-DiD Event Study: Online Gambling \u2192 Mortgage Delinquency (Bootstrap SEs)",
    glue("Pre-trend Holm p = {round(cs_bootstrap_res$joint_min_holm_p, 4)} | biters={CS_BITERS} | {cs_bootstrap_res$n_clusters} clusters | {sample_label}"),
    color = "darkgreen"
  )
  if (!is.null(p2)) ggsave(file.path(OUT_DIR, "cs_event_study_bootstrap.png"), p2, width = 10, height = 6, dpi = 300)
}

# Plot 3: CS analytic vs bootstrap comparison
if (!is.null(cs_analytic_res) && !is.null(cs_bootstrap_res)) {
  combined_cs <- bind_rows(
    cs_analytic_res$event_study %>% mutate(method = "Analytic"),
    cs_bootstrap_res$event_study %>% mutate(method = "Bootstrap")
  ) %>%
    filter(is.finite(att), is.finite(se), se > 0)

  if (nrow(combined_cs) > 0) {
    p3 <- ggplot(combined_cs, aes(x = egt, y = att, color = method, fill = method)) +
      geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.15) +
      geom_point(size = 2, position = position_dodge(width = 0.3)) +
      geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.2, position = position_dodge(width = 0.3)) +
      zero_line + treat_line + base_theme +
      scale_color_manual(values = c("Analytic" = "steelblue", "Bootstrap" = "darkgreen")) +
      scale_fill_manual(values = c("Analytic" = "steelblue", "Bootstrap" = "darkgreen")) +
      labs(
        title = "CS-DiD: Analytic vs Bootstrap SEs (Mortgage Delinquency)",
        subtitle = glue("Headline method: {toupper(HEADLINE_METHOD)} | {sample_label}"),
        x = "Event Time (months)", y = y_label, color = "Inference", fill = "Inference"
      )
    ggsave(file.path(OUT_DIR, "cs_analytic_vs_bootstrap.png"), p3, width = 10, height = 6, dpi = 300)
  }
}

# Plot 4: TWFE/SunAb event study
if (!is.null(sa_result)) {
  sa_subtitle <- glue("Wald F = {round(sa_result$wald_f, 3)}, p = {round(sa_result$wald_p, 4)} | {sa_result$n_clusters} clusters | {sample_label}")
  p4 <- make_es_plot(sa_result$event_study, "Sun-Abraham Event Study: Online Gambling \u2192 Mortgage Delinquency", sa_subtitle, color = "darkorange")
  if (!is.null(p4)) ggsave(file.path(OUT_DIR, "twfe_sunab_event_study.png"), p4, width = 10, height = 6, dpi = 300)
}

# Plot 5: CS vs TWFE comparison
headline_cs <- if (HEADLINE_METHOD == "bootstrap" && !is.null(cs_bootstrap_res)) {
  cs_bootstrap_res$event_study %>% mutate(method = "CS-DiD (Bootstrap)")
} else if (!is.null(cs_analytic_res)) {
  cs_analytic_res$event_study %>% mutate(method = "CS-DiD (Analytic)")
} else {
  NULL
}

if (!is.null(headline_cs) && !is.null(sa_result)) {
  combined_all <- bind_rows(
    headline_cs %>% select(egt, att, se, ci_lo, ci_hi, method),
    sa_result$event_study %>% mutate(method = "Sun-Abraham (TWFE)") %>% select(egt, att, se, ci_lo, ci_hi, method)
  ) %>%
    filter(is.finite(att), is.finite(se), se > 0)

  if (nrow(combined_all) > 0) {
    p5 <- ggplot(combined_all, aes(x = egt, y = att, color = method)) +
      geom_point(size = 2, position = position_dodge(width = 0.3)) +
      geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.2, position = position_dodge(width = 0.3)) +
      zero_line + treat_line + base_theme +
      scale_color_manual(values = c(
        "CS-DiD (Analytic)" = "steelblue", "CS-DiD (Bootstrap)" = "darkgreen",
        "Sun-Abraham (TWFE)" = "darkorange"
      )) +
      labs(
        title = "CS-DiD vs Sun-Abraham: Mortgage Delinquency",
        subtitle = glue("CS headline: {HEADLINE_METHOD} | {sample_label}"),
        x = "Event Time (months)", y = y_label, color = "Method"
      )
    ggsave(file.path(OUT_DIR, "cs_vs_twfe_comparison.png"), p5, width = 10, height = 6, dpi = 300)
  }
}

################################################################################
# SECTION 7: OUTPUT ASSEMBLY
################################################################################

log_msg("Assembling outputs...")

# --- pretrends_summary.csv ---
summary_rows <- list()

if (!is.null(cs_analytic_res)) {
  pre_a <- cs_analytic_res$event_study %>% filter(egt %in% PRE_WINDOW, is.finite(att))
  summary_rows[["CS_analytic"]] <- tibble(
    method = "CS_analytic",
    n_states = cs_analytic_res$n_clusters,
    n_obs = cs_analytic_res$n_obs,
    n_pre_periods = cs_analytic_res$n_pre,
    joint_test_type = "holm",
    joint_test_stat = cs_analytic_res$max_abs_t,
    joint_test_p = cs_analytic_res$joint_min_holm_p,
    joint_reject = cs_analytic_res$joint_reject,
    max_abs_pre_att = if (nrow(pre_a) > 0) max(abs(pre_a$att)) else NA_real_,
    mean_abs_pre_att = if (nrow(pre_a) > 0) mean(abs(pre_a$att)) else NA_real_,
    overall_att = cs_analytic_res$overall_att,
    overall_se = cs_analytic_res$overall_se,
    headline = (HEADLINE_METHOD == "analytic")
  )
}

if (!is.null(cs_bootstrap_res)) {
  pre_b <- cs_bootstrap_res$event_study %>% filter(egt %in% PRE_WINDOW, is.finite(att))
  summary_rows[["CS_bootstrap"]] <- tibble(
    method = "CS_bootstrap",
    n_states = cs_bootstrap_res$n_clusters,
    n_obs = cs_bootstrap_res$n_obs,
    n_pre_periods = cs_bootstrap_res$n_pre,
    joint_test_type = "holm",
    joint_test_stat = cs_bootstrap_res$max_abs_t,
    joint_test_p = cs_bootstrap_res$joint_min_holm_p,
    joint_reject = cs_bootstrap_res$joint_reject,
    max_abs_pre_att = if (nrow(pre_b) > 0) max(abs(pre_b$att)) else NA_real_,
    mean_abs_pre_att = if (nrow(pre_b) > 0) mean(abs(pre_b$att)) else NA_real_,
    overall_att = cs_bootstrap_res$overall_att,
    overall_se = cs_bootstrap_res$overall_se,
    headline = (HEADLINE_METHOD == "bootstrap")
  )
}

if (!is.null(sa_result)) {
  pre_sa <- sa_result$event_study %>% filter(egt %in% PRE_WINDOW, is.finite(att), se > 0)
  summary_rows[["TWFE_SunAb"]] <- tibble(
    method = "TWFE_SunAb",
    n_states = sa_result$n_clusters,
    n_obs = sa_result$n_obs,
    n_pre_periods = nrow(pre_sa),
    joint_test_type = "wald_F",
    joint_test_stat = sa_result$wald_f,
    joint_test_p = sa_result$wald_p,
    joint_reject = sa_result$joint_reject,
    max_abs_pre_att = if (nrow(pre_sa) > 0) max(abs(pre_sa$att)) else NA_real_,
    mean_abs_pre_att = if (nrow(pre_sa) > 0) mean(abs(pre_sa$att)) else NA_real_,
    overall_att = NA_real_,
    overall_se = NA_real_,
    headline = TRUE
  )
}

if (length(summary_rows) > 0) {
  pretrends_summary <- bind_rows(summary_rows)
  safe_write_csv(pretrends_summary, file.path(OUT_DIR, "pretrends_summary.csv"))
}

# --- README.md ---
readme_lines <- c(
  "# Pre-trends Diagnostics: Mortgage Delinquency",
  "",
  glue("Generated: {Sys.time()}"),
  "",
  "## Research Question",
  "Does online sports gambling legalization affect mortgage delinquency rates?",
  glue("Outcome: % of mortgages 90+ days delinquent ({OUTCOME})"),
  glue("Treatment: {TREAT_DATE_COL} (online sports gambling legalization)"),
  "",
  "## Configuration",
  glue("- Mortgage data: `{MORTGAGE_FILE}`"),
  glue("- Treatment file: `{TREAT_FILE}`"),
  glue("- Treatment column: {TREAT_DATE_COL}"),
  glue("- Excluded states: {if (length(EXCLUDE_STATES) > 0 && any(nzchar(EXCLUDE_STATES))) paste(EXCLUDE_STATES, collapse=', ') else '<none>'}"),
  glue("- Date range: {MIN_DATE} to {MAX_DATE}"),
  glue("- Dropped window: {ifelse(is.na(DROP_START), '<none>', as.character(DROP_START))} to {ifelse(is.na(DROP_END), '<none>', as.character(DROP_END))}"),
  glue("- Coverage threshold: {COVERAGE_THRESHOLD}"),
  glue("- Balance common months: {BALANCE_COMMON_MONTHS}"),
  glue("- Outcome: {OUTCOME}"),
  glue("- Control group: {CONTROL_GROUP}, est_method: {EST_METHOD}"),
  glue("- Allow unbalanced panel: {ALLOW_UNBALANCED}"),
  glue("- Pre-window: {paste(range(PRE_WINDOW), collapse=' to ')}"),
  glue("- Alpha: {ALPHA}"),
  "",
  "## Panel Summary",
  glue("- {n_states} states ({n_treated} treated, {n_never} never-treated)"),
  glue("- {n_cohorts} treatment cohorts"),
  glue("- {n_t} months, {nrow(panel)} observations"),
  ""
)

if (!is.null(cs_analytic_res)) {
  readme_lines <- c(readme_lines,
    "## CS-DiD Pretrends (Analytic)",
    glue("- Pre-periods tested: {cs_analytic_res$n_pre}"),
    glue("- Joint test (Holm): min_p = {round(cs_analytic_res$joint_min_holm_p, 4)}, reject = {cs_analytic_res$joint_reject}"),
    glue("- Overall ATT: {round(cs_analytic_res$overall_att, 4)} (SE = {round(cs_analytic_res$overall_se, 4)})"),
    ""
  )
}

if (!is.null(cs_bootstrap_res)) {
  readme_lines <- c(readme_lines,
    "## CS-DiD Pretrends (Bootstrap)",
    glue("- Pre-periods tested: {cs_bootstrap_res$n_pre}"),
    glue("- Joint test (Holm): min_p = {round(cs_bootstrap_res$joint_min_holm_p, 4)}, reject = {cs_bootstrap_res$joint_reject}"),
    glue("- Overall ATT: {round(cs_bootstrap_res$overall_att, 4)} (SE = {round(cs_bootstrap_res$overall_se, 4)})"),
    glue("- Bootstrap iterations: {CS_BITERS}"),
    ""
  )
}

if (!is.null(sa_result)) {
  readme_lines <- c(readme_lines,
    "## TWFE / Sun-Abraham Pretrends",
    glue("- Joint Wald F = {round(sa_result$wald_f, 3)}, p = {round(sa_result$wald_p, 4)}, reject = {sa_result$joint_reject}"),
    ""
  )
}

readme_lines <- c(readme_lines,
  "## Inference Notes",
  "- CS p-values: pointwise t-test with df = n_states - 1, Holm step-down for joint test",
  "- SunAb p-values: cluster-robust SEs (state level), Wald F-test for joint pre-trend",
  "",
  "## How to Run",
  "```bash",
  "# Default (excludes COVID period)",
  "bash scripts/run_pretrends_mortgage.sh",
  "",
  "# Include COVID period",
  "NO_COVID=FALSE bash scripts/run_pretrends_mortgage.sh",
  "",
  "# Use retail legalization dates instead of online",
  "TREAT_DATE_COL=retail_start_date bash scripts/run_pretrends_mortgage.sh",
  "```",
  ""
)

writeLines(readme_lines, file.path(OUT_DIR, "README.md"))

log_msg("=== Done ===")
log_msg(glue("Output directory: {OUT_DIR}"))

# List outputs
output_files <- list.files(OUT_DIR, full.names = FALSE)
for (f in output_files) {
  log_msg(glue("  - {f}"))
}
