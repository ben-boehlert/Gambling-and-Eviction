#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# Post-COVID boundary: does a LATER window start actually buy trend stability?
#
# postcovid_boundary_sweep.R answers this with windows that run to the end of
# the panel, so a later start is also a SHORTER window. Slope dispersion and
# half-split shifts are both estimated less precisely on short windows, so that
# design confounds "later" with "shorter" -- and on the rebuilt panel it reports
# every metric worsening monotonically, which is exactly the signature of the
# confound rather than of real instability.
#
# Here window LENGTH is held fixed and the start is slid. Any remaining
# movement is attributable to WHEN the window sits.
#
# Never-treated states only; real outcomes; blindness-compatible.
# Output: output/covid_global_pt/postcovid_boundary_fixedlen.csv
# ─────────────────────────────────────────────────────────────────────────────
suppressMessages({library(tidyverse); library(fixest); library(glue)})
theme_set(theme_minimal())

OUT_DIR <- "output/covid_global_pt"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

NT_STATES <- c("AK","GA","ID","MN","MT","ND","OK","TX","UT")
MAX_DATE  <- as.Date("2025-11-01")
WIN_LENS  <- c(18L, 24L)

ym <- function(d) (as.integer(format(d,"%Y"))-2000L)*12L + as.integer(format(d,"%m"))

panel <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types=FALSE) %>%
  transmute(state_abb=as.character(state_abb), month_date=as.Date(month_date),
            filings_count=as.numeric(filings_count)) %>%
  filter(state_abb %in% NT_STATES, month_date >= as.Date("2016-01-01"),
         month_date <= MAX_DATE, !is.na(filings_count)) %>%
  mutate(y = log1p(pmax(filings_count,0)), t = ym(month_date))

n_st   <- n_distinct(panel$state_abb)
common <- panel %>% count(month_date) %>% filter(n==n_st) %>% pull(month_date)
panel  <- panel %>% filter(month_date %in% common)
cat(glue("{n_st} never-treated states; balanced {format(min(common))}..{format(max(common))} ",
         "({length(common)} months)"), "\n\n")

half_split_sd <- function(d) {
  if (n_distinct(d$t) < 8L) return(NA_real_)
  mid <- median(unique(d$t))
  d <- d %>% mutate(late = t > mid, state_abb = factor(state_abb))
  m <- feols(y ~ i(state_abb, late) | state_abb + t, data=d, cluster=~state_abb)
  sh <- c(broom::tidy(m) %>% filter(str_detect(term,"state_abb")) %>% pull(estimate), 0)
  sd(sh - mean(sh))
}

starts <- seq(as.Date("2021-08-01"), as.Date("2024-04-01"), by="2 months")
res <- map_dfr(WIN_LENS, function(L) {
  map_dfr(starts, function(s) {
    e <- s %m+% months(L-1L)
    if (e > max(common)) return(NULL)
    w <- panel %>% filter(month_date >= s, month_date <= e)
    if (n_distinct(w$month_date) < L) return(NULL)
    slopes <- w %>% group_by(state_abb) %>%
      summarise(slope = coef(lm(y ~ t))[["t"]], .groups="drop")
    tibble(win_len=L, start=s, end=e,
           within_halfsplit_sd = half_split_sd(w),
           slope_sd_annpp = 100*(exp(12*sd(slopes$slope))-1))
  })
})

cat("=== Fixed-length sliding windows (length held constant) ===\n")
print(res %>% mutate(start=format(start,"%Y-%m"), end=format(end,"%Y-%m"),
                     across(where(is.numeric), ~round(.x,3))) %>%
        as.data.frame(), row.names=FALSE)

cat("\n=== Pre vs post median, by window length ===\n")
summ <- res %>% mutate(era = ifelse(start < as.Date("2022-08-01"),
                                    "start < 2022-08", "start >= 2022-08")) %>%
  group_by(win_len, era) %>%
  summarise(n=n(), halfsplit_med=round(median(within_halfsplit_sd,na.rm=TRUE),3),
            slope_sd_med=round(median(slope_sd_annpp,na.rm=TRUE),2), .groups="drop")
print(as.data.frame(summ), row.names=FALSE)

write_csv(res, file.path(OUT_DIR,"postcovid_boundary_fixedlen.csv"))
cat(glue("\nWrote {OUT_DIR}/postcovid_boundary_fixedlen.csv\n"))
