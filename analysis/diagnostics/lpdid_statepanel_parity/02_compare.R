suppressPackageStartupMessages(library(tidyverse))
SCR <- Sys.getenv("SCR")
fw <- read_csv(file.path(SCR, "framework_results.csv"), show_col_types = FALSE)
tags <- list.files(SCR, pattern = "^s[0-9]+_d[0-9]+$")
rs <- map_dfr(tags, function(t) map_dfr(c("asis", "nobal"), function(v) {
  f  <- file.path(SCR, t, paste0("out_", v), "lpdid_pooled_shift12_event_clean.csv")
  lg <- readLines(file.path(SCR, t, paste0("out_", v), "log.txt"), warn = FALSE)
  pan <- grep("^Panel:", lg, value = TRUE)[1]
  us  <- grep("Usable as switchers", lg, value = TRUE)[1]
  base <- tibble(seed = as.integer(sub("s(\\d+)_d.*", "\\1", t)),
                 delta = as.integer(sub(".*_d(\\d+)", "\\1", t)) / 100, variant = v,
                 panel_line = pan, usable = us,
                 failed = any(grepl("^FAILED|^Error", lg)))
  if (!file.exists(f)) return(base %>% mutate(att_s = NA_real_, se_s = NA_real_,
                                              p_an_s = NA_real_, p_w_s = NA_real_))
  d <- read_csv(f, show_col_types = FALSE)
  base %>% mutate(att_s = d$att, se_s = d$se, p_an_s = d$p_analytic,
                  p_w_s = d$p_wild, n_obs_s = d$n_obs)
}))
cmp <- rs %>%
  left_join(fw %>% filter(inference == "analytic") %>%
              select(seed, delta, att_f = att, se_f = se, p_an_f = p), by = c("seed", "delta")) %>%
  left_join(fw %>% filter(inference == "wild") %>% select(seed, delta, p_w_f = p),
            by = c("seed", "delta")) %>%
  mutate(d_att = att_s - att_f, d_se = se_s - se_f)
cat("\n=== POOLED ATT: repo script vs framework (same simulated panel) ===\n")
print(cmp %>% select(seed, delta, variant, failed, att_f, att_s, d_att, se_f, se_s, d_se,
                     p_an_f, p_an_s, p_w_f, p_w_s) %>% as.data.frame(), digits = 6)
cat("\n=== sample lines from script logs ===\n")
print(cmp %>% distinct(variant, panel_line, usable) %>% as.data.frame())
cat("\nmax |d_att| nobal:", max(abs(cmp$d_att[cmp$variant == "nobal"]), na.rm = TRUE),
    " max |d_se| nobal:", max(abs(cmp$d_se[cmp$variant == "nobal"]), na.rm = TRUE), "\n")
write_csv(cmp, file.path(SCR, "parity_comparison.csv"))
