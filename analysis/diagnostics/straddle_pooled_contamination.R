suppressPackageStartupMessages({library(tidyverse); library(lubridate)})
EXCL <- c("NV","ID","HI","MS"); CS <- as.Date("2020-03-01"); CE <- as.Date("2021-07-31")
pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types=FALSE) %>%
  mutate(month_date=as.Date(month_date), y=log1p(filings_count)) %>% filter(!state_abb %in% EXCL)
norm <- pan %>% filter(year(month_date) %in% 2017:2019) %>%
  group_by(state_abb, m=month(month_date)) %>% summarise(y_norm=mean(y), n=n(), .groups="drop") %>% filter(n>=2)
dev <- pan %>% mutate(m=month(month_date)) %>% inner_join(norm, by=c("state_abb","m")) %>%
  transmute(state_abb, month_date, dev=y-y_norm)
D <- dev %>% { split(setNames(.$dev, format(.$month_date,"%Y-%m")), .$state_abb) }
ab <- c(Delaware="DE",`West Virginia`="WV",Pennsylvania="PA",`Rhode Island`="RI",Arkansas="AR",
 `New York`="NY",Indiana="IN",`New Hampshire`="NH",Colorado="CO",Tennessee="TN",Virginia="VA",
 `North Carolina`="NC",Arizona="AZ",Connecticut="CT",Louisiana="LA",Maryland="MD",Kansas="KS",
 Massachusetts="MA",Ohio="OH",Kentucky="KY",Maine="ME",Florida="FL",Vermont="VT",Missouri="MO")
L <- read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types=FALSE) %>%
  transmute(st=ab[state], L=as.Date(online_start_date)) %>% filter(!is.na(st), !is.na(L))
obs <- split(pan$month_date, pan$state_abb); obs <- map(obs, ~ .x[.x < CS | .x > CE])
k <- function(d) format(d,"%Y-%m")
md <- function(s,mo){v <- D[[s]][k(mo)]; v<-v[!is.na(v)]; if(!length(v)) NA_real_ else mean(v)}
never <- setdiff(names(obs), L$st)

# states DISQUALIFIED by the strict rule (baseline in the COVID hole) = the straddle candidates
cand <- L %>% rowwise() %>% mutate(
    strict_ok = all(seq(L %m-% months(6), by="month", length.out=6) %in% obs[[st]]),
    pre = list(sort(obs[[st]][obs[[st]] < L])),
    owin= list({o <- seq(L %m+% months(12), L %m+% months(24), by="month"); o[o %in% obs[[st]]]})) %>%
  ungroup() %>% filter(!strict_ok, map_int(owin, length) > 0, map_int(pre, length) >= 6)
cat("States treated during COVID that a pre-COVID baseline would rescue:\n")
res <- cand %>% rowwise() %>% mutate(
    bwin = list(tail(pre, 6)), bstart = min(bwin), bend = max(bwin),
    gap_mo = interval(bend, min(owin)) %/% months(1),
    drift = md(st, owin) - md(st, bwin)) %>% ungroup()
print(as.data.frame(res %>% transmute(st, launch=L, baseline=paste(format(bstart,"%Y-%m"),"..",format(bend,"%Y-%m")),
                                      gap_months=gap_mo, n_out=map_int(owin,length), drift=round(drift,3))), row.names=FALSE)

# control drift over the SAME outcome windows (what the cell differences against)
cell <- res %>% rowwise() %>% mutate(
    ctl_drift = { cs <- map_dbl(never, function(c){
        b <- tail(sort(obs[[c]][obs[[c]] < L]), 6); if(length(b)<6) return(NA_real_)
        md(c, owin) - md(c, b) }); mean(cs, na.rm=TRUE) },
    n_ctl = sum(map_lgl(never, ~ length(obs[[.x]]) > 0)),
    contam = drift - ctl_drift) %>% ungroup()
sd_raw <- sd(res$drift, na.rm=TRUE); sd_cell <- sd(cell$contam, na.rm=TRUE)
n_sw <- sum(is.finite(cell$contam))
cat(sprintf("\nraw cross-state SD of straddle drift            : %.3f  (%.1fx MDE 0.127)\n", sd_raw, sd_raw/0.127))
cat(sprintf("after differencing vs the never-treated pool     : %.3f  (%.1fx MDE)  <- common recovery cancels\n", sd_cell, sd_cell/0.127))
cat(sprintf("mean contamination (bias if non-zero)            : %+.3f\n", mean(cell$contam, na.rm=TRUE)))
cat(sprintf("POOLED over %d straddle switchers (SD/sqrt(n))    : %.3f  (%.1f%% of MDE)\n",
            n_sw, sd_cell/sqrt(n_sw), 100*sd_cell/sqrt(n_sw)/0.127))
cat("\n(the pooled figure assumes mean-zero contamination, which the A/B/C bias tests support)\n")
