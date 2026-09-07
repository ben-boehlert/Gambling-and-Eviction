suppressPackageStartupMessages(library(tidyverse))
SCR <- Sys.getenv("SCR")
fw <- read_csv(file.path(SCR, "framework_results.csv"), show_col_types = FALSE)
tags <- list.files(SCR, pattern = "^s[0-9]+_d[0-9]+$")
r <- map_dfr(tags, function(t) {
  f  <- file.path(SCR, t, "out_fixed", "lpdid_pooled_shift12_event_clean.csv")
  lg <- readLines(file.path(SCR, t, "out_fixed", "log.txt"), warn = FALSE)
  d  <- if (file.exists(f)) read_csv(f, show_col_types = FALSE) else tibble(att = NA, se = NA, p_wild = NA)
  tibble(seed = as.integer(sub("s([0-9]+)_.*", "\\1", t)),
         delta = as.integer(sub(".*_d([0-9]+)", "\\1", t)) / 100,
         att_s = d$att, se_s = d$se, p_w_s = d$p_wild,
         sample = grep("^Sample:", lg, value = TRUE)[1], err = any(grepl("^Error", lg)))
})
out <- r %>%
  left_join(fw %>% filter(inference == "analytic") %>% select(seed, delta, att_f = att, se_f = se), by = c("seed", "delta")) %>%
  left_join(fw %>% filter(inference == "wild") %>% select(seed, delta, p_w_f = p), by = c("seed", "delta")) %>%
  mutate(d_att = att_s - att_f, d_se = se_s - se_f)
print(out %>% select(seed, delta, err, att_f, att_s, d_att, d_se, p_w_f, p_w_s) %>% as.data.frame(), digits = 6)
cat("\nsample line:", out$sample[1], "\nmax |d_att|:", max(abs(out$d_att)), " max |d_se|:", max(abs(out$d_se)), "\n")
write_csv(out, file.path(SCR, "parity_comparison_fixed_script.csv"))
