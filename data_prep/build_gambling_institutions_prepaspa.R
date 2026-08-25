################################################################################
# build_gambling_institutions_prepaspa.R
#
# Builds the pre-PASPA gambling-institutions predictor block.
# Provenance for every value: data/raw/gambling_institutions/SOURCES.md
# PASPA was enacted October 1992, so all measures are cut at 31 Dec 1991.
################################################################################

suppressPackageStartupMessages(library(tidyverse))
source("utils/eviction_treatment_schedule.R")

OUT <- "data/raw/gambling_institutions/state_gambling_institutions_prepaspa.csv"

# ---- lottery first-offering year (LotteryUSA; DC corrected to 1982) ----------
lottery_year <- c(
  NH = 1964, NY = 1967, NJ = 1970, CT = 1972, PA = 1972, MA = 1972, MI = 1972,
  MD = 1973, DE = 1974, RI = 1974, ME = 1974, IL = 1974, OH = 1974, VT = 1978,
  AZ = 1981, DC = 1982, WA = 1982, CO = 1983, OR = 1985, IA = 1985, CA = 1985,
  WV = 1986, MO = 1986, MT = 1987, SD = 1987, KS = 1987, FL = 1988, WI = 1988,
  VA = 1988, KY = 1989, ID = 1989, IN = 1989, MN = 1990, LA = 1991, TX = 1992,
  GA = 1993, NE = 1993, NM = 1996, SC = 2002, TN = 2004, ND = 2004, OK = 2005,
  NC = 2006, AR = 2009, WY = 2014, MS = 2019
)
NO_LOTTERY <- c("AL", "AK", "HI", "NV", "UT")

# ---- commercial casino: year first casinos OPERATED, and year AUTHORIZED -----
casino_op_year   <- c(NV = 1931, NJ = 1978, SD = 1989, IA = 1991, IL = 1991,
                      CO = 1991, MS = 1992, LA = 1993)
casino_auth_year <- c(NV = 1931, NJ = 1976, SD = 1988, IA = 1989, IL = 1990,
                      CO = 1990, MS = 1990, LA = 1991)

PASPA_CUT <- 1991   # last full year before PASPA's October 1992 enactment

inst <- tibble(state_abb = EVICTION_STATE_UNIVERSE) %>%
  mutate(
    lottery_year   = unname(lottery_year[state_abb]),
    has_lottery    = !state_abb %in% NO_LOTTERY,
    lottery_by_91  = as.integer(!is.na(lottery_year) & lottery_year <= PASPA_CUT),
    # years of lottery operation as of 1991: a maturity measure, 0 if none yet.
    # Strictly better than the binary -- NH (27 yrs) and MN (1 yr) are not the
    # same kind of "has a lottery".
    lottery_years_91 = ifelse(lottery_by_91 == 1L, PASPA_CUT - lottery_year, 0L),

    casino_op_year   = unname(casino_op_year[state_abb]),
    casino_auth_year = unname(casino_auth_year[state_abb]),
    casino_op_by_91   = as.integer(!is.na(casino_op_year)   & casino_op_year   <= PASPA_CUT),
    casino_auth_by_91 = as.integer(!is.na(casino_auth_year) & casino_auth_year <= PASPA_CUT)
  )

# consistency checks -- these encode the source's own internal claims
stopifnot(
  nrow(inst) == 51,
  sum(!inst$has_lottery) == 5,                       # AL AK HI NV UT
  all(is.na(inst$lottery_year[!inst$has_lottery])),
  sum(inst$casino_op_by_91)   == 6,                  # NV NJ SD IA IL CO
  sum(inst$casino_auth_by_91) == 8,                   # + MS LA
  # authorization must never post-date operation
  all(inst$casino_auth_year <= inst$casino_op_year, na.rm = TRUE)
)

write_csv(inst, OUT)
cat("wrote", OUT, "\n")
cat("lottery by 1991:", sum(inst$lottery_by_91), "states | casino authorized by 1991:",
    sum(inst$casino_auth_by_91), "| operating:", sum(inst$casino_op_by_91), "\n")
print(as.data.frame(inst %>% filter(casino_auth_by_91 == 1) %>%
  select(state_abb, casino_auth_year, casino_op_year, lottery_year)), row.names = FALSE)
