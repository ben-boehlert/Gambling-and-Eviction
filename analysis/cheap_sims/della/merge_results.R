#!/usr/bin/env Rscript
# Merge Della shard outputs (output/cheap_power_sim/della_shard_*/results_raw.csv)
# into a single results_raw.csv for 03_summarize.R. Run from repo root.
suppressPackageStartupMessages(library(tidyverse))
shards <- Sys.glob("output/cheap_power_sim/della_shard_*/results_raw.csv")
stopifnot(length(shards) > 0)
merged <- map_dfr(shards, read_csv, show_col_types = FALSE) %>%
  distinct(rep, design, shape, delta, lag, .keep_all = TRUE)
write_csv(merged, "output/cheap_power_sim/results_raw.csv")
cat(sprintf("merged %d shards -> %d rows, %d reps\n",
            length(shards), nrow(merged), n_distinct(merged$rep)))
