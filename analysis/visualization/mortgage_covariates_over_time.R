################################################################################
# mortgage_covariates_over_time.R  (2026-09-29)
#
# Line graph of the time-varying mortgage covariates -- state unemployment rate
# (BLS LAUS, SA, monthly) and house prices (FHFA purchase-only state HPI, SA,
# quarterly, indexed to 2016Q1 = 100) -- for the June-2022 design's 10 switchers
# vs its 20 controls (states untreated through 2025-03), NV out. Group means
# with an interquartile band. The design uses the 2019 baselines; this shows the
# full paths. No delinquency data enters: blind-safe.
#
# BLS series are fetched once through the public API v1 (no key) and cached in
# data/raw/covariates/bls_laus_state_ur_sa_2016_2025.json.
#
# Run from the project root: Rscript analysis/visualization/mortgage_covariates_over_time.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(jsonlite)
  library(httr)
  library(ggplot2)
  library(patchwork)
})
source("utils/eviction_treatment_schedule.R")
theme_set(theme_minimal(base_family = "serif"))

RAW      <- "data/raw/covariates"
BLS_FILE <- file.path(RAW, "bls_laus_state_ur_sa_2016_2025.json")
HPI_FILE <- file.path(RAW, "fhfa_hpi_po_state.txt")
COV_FILE <- "data/processed/state_covariates_2019.csv"
FIG      <- "figures/mortgage_covariates_over_time"
SWITCHERS <- c("DE", "FL", "KS", "KY", "MA", "MD", "ME", "NC", "OH", "VT")
DATA_END  <- as.Date("2025-03-01")
COVID     <- as.Date(c("2020-03-01", "2021-07-31"))
DESIGN_START <- as.Date("2022-06-01")

cov <- read_csv(COV_FILE, show_col_types = FALSE) %>%
  drop_pre_paspa_states("mortgage_covariates_over_time")
sched <- load_eviction_treatment_schedule("data/raw/sports_gambling_legalization_dates.csv",
                                          "online_start_date", states = cov$state_abb)
controls <- sched %>% filter(is.na(treat_start) | treat_start > DATA_END) %>% pull(state_abb)
grp <- tibble(state_abb = c(SWITCHERS, controls),
              group = c(rep("June-2022 switchers (10)", length(SWITCHERS)),
                        rep(sprintf("Controls (%d)", length(controls)), length(controls))))

# ---- BLS unemployment 2016-2025 (API v1 allows 10 years, 25 series/query) ----
if (!file.exists(BLS_FILE)) {
  ids <- paste0("LASST", sprintf("%02d", as.integer(cov$fips[cov$state_abb %in% grp$state_abb])),
                "0000000000003")
  res <- lapply(split(ids, ceiling(seq_along(ids) / 17)), function(b) {
    r <- POST("https://api.bls.gov/publicAPI/v1/timeseries/data/", user_agent("Mozilla/5.0"),
              body = list(seriesid = b, startyear = "2016", endyear = "2025"), encode = "json")
    content(r, as = "parsed", simplifyVector = FALSE)$Results$series
  })
  writeLines(toJSON(do.call(c, unname(res)), auto_unbox = TRUE), BLS_FILE)
}
bls <- fromJSON(paste(readLines(BLS_FILE, warn = FALSE), collapse = ""), simplifyVector = FALSE)
fips_abb <- cov %>% transmute(fips = sprintf("%02d", as.integer(fips)), state_abb)
unemp <- bind_rows(lapply(bls, function(s) bind_rows(lapply(s$data, function(d)
  if (grepl("^M(0[1-9]|1[0-2])$", d$period))
    tibble(fips = substr(s$seriesID, 6, 7),
           date = as.Date(sprintf("%s-%s-01", d$year, substr(d$period, 2, 3))),
           value = as.numeric(d$value)))))) %>%
  left_join(fips_abb, by = "fips") %>%
  filter(date <= DATA_END)
stopifnot(n_distinct(unemp$state_abb) == nrow(grp))

hpi <- read_tsv(HPI_FILE, show_col_types = FALSE) %>%
  transmute(state_abb = state, date = as.Date(sprintf("%d-%02d-01", yr, 3 * qtr - 2)),
            indx_sa) %>%
  filter(date >= as.Date("2016-01-01"), date <= DATA_END) %>%
  group_by(state_abb) %>% arrange(date) %>%
  mutate(value = 100 * indx_sa / first(indx_sa)) %>% ungroup()

summarise_groups <- function(d) d %>% inner_join(grp, by = "state_abb") %>%
  group_by(group, date) %>%
  summarise(mean = mean(value), q25 = quantile(value, .25), q75 = quantile(value, .75),
            .groups = "drop")

panel <- function(d, ylab, tag) {
  ggplot(summarise_groups(d), aes(date, mean)) +
    annotate("rect", xmin = COVID[1], xmax = COVID[2], ymin = -Inf, ymax = Inf, alpha = 0.10) +
    geom_vline(xintercept = DESIGN_START, linetype = "dotted", colour = "grey40") +
    geom_ribbon(aes(ymin = q25, ymax = q75, fill = group), alpha = 0.15) +
    geom_line(aes(linetype = group, colour = group), linewidth = 0.6) +
    scale_colour_manual(values = c("grey15", "#2c6fbb")) +
    scale_fill_manual(values = c("grey15", "#2c6fbb")) +
    scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
    labs(x = NULL, y = ylab, colour = NULL, fill = NULL, linetype = NULL, tag = tag)
}
p <- panel(unemp, "Unemployment rate (%, SA)", "(a)") /
  panel(hpi, "House prices (FHFA PO, 2016Q1 = 100)", "(b)") +
  plot_layout(guides = "collect") & theme(legend.position = "bottom")

ggsave(paste0(FIG, ".pdf"), p, width = 6.5, height = 7)
ggsave(paste0(FIG, ".png"), p, width = 6.5, height = 7, dpi = 300)
message("wrote ", FIG, ".{pdf,png}")
