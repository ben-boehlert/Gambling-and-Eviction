#!/usr/bin/env Rscript
################################################################################
# download_county_adjacency.R
#
# Downloads the Census Bureau county adjacency flat file and parses it into a
# long edge list. The Census file is the canonical reference used by
# Dube, Lester & Reich (2010) and many other border-pair studies.
#
# Source format (two-column, with continuation rows):
#   "County Name, ST"<TAB><5-digit FIPS><TAB>"Neighbor, ST"<TAB><FIPS>
#   <TAB><TAB>"Neighbor, ST"<TAB><FIPS>     # continuation rows
#   ...
#
# A county is listed as its own first neighbor; we drop self-loops.
#
# Outputs:
#   data/raw/county_adjacency_census.txt        — raw flat file
#   data/processed/county_adjacency_edges.csv   — long edge list (fips_a, fips_b)
#                                                  symmetric (both directions)
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(tidyr)
})

set.seed(20260521L)

# ----------------------------- paths ------------------------------------------

repo_root <- normalizePath(".", winslash = "/")
raw_path  <- file.path(repo_root, "data", "raw", "county_adjacency_census.txt")
out_path  <- file.path(repo_root, "data", "processed", "county_adjacency_edges.csv")

dir.create(dirname(raw_path), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)

# Census 2010-vintage file: https://www2.census.gov/geo/docs/reference/county_adjacency.txt
#   - encoded latin1 (the only quirk that matters in practice)
#   - 5-digit county FIPS
#   - covers 50 states + DC + PR + territories
adjacency_url <- "https://www2.census.gov/geo/docs/reference/county_adjacency.txt"

# ----------------------------- download ---------------------------------------

if (!file.exists(raw_path)) {
  cat("Downloading from", adjacency_url, "...\n")
  utils::download.file(adjacency_url, raw_path, mode = "wb", quiet = FALSE)
} else {
  cat("Using cached file at", raw_path, "\n")
}

# ----------------------------- parse ------------------------------------------

# Read with latin1 — file contains Spanish accents in PR county names.
raw_lines <- readLines(raw_path, encoding = "latin1", warn = FALSE)
cat("Read", length(raw_lines), "lines from raw file.\n")

# Each line has 4 tab-separated columns; "anchor" rows have all 4 filled,
# "continuation" rows have the first two empty (the anchor county carries over).
parse_line <- function(line) {
  parts <- strsplit(line, "\t", fixed = TRUE)[[1]]
  # Pad to length 4 in case the trailing tab is missing.
  if (length(parts) < 4L) parts <- c(parts, rep("", 4L - length(parts)))
  parts <- parts[1:4]
  # Strip surrounding quotes from name fields.
  parts[1] <- str_remove_all(parts[1], '"')
  parts[3] <- str_remove_all(parts[3], '"')
  parts
}

parsed <- do.call(rbind, lapply(raw_lines, parse_line))
colnames(parsed) <- c("name_a", "fips_a", "name_b", "fips_b")
parsed <- as_tibble(parsed)

# Forward-fill the anchor county on continuation rows.
parsed <- parsed %>%
  mutate(
    name_a = na_if(str_trim(name_a), ""),
    fips_a = na_if(str_trim(fips_a), ""),
    name_b = na_if(str_trim(name_b), ""),
    fips_b = na_if(str_trim(fips_b), "")
  ) %>%
  tidyr::fill(name_a, fips_a, .direction = "down") %>%
  filter(!is.na(fips_b), nzchar(fips_b))

# Drop self-loops (each county lists itself as a neighbor).
edges <- parsed %>%
  mutate(
    fips_a = as.integer(fips_a),
    fips_b = as.integer(fips_b)
  ) %>%
  filter(!is.na(fips_a), !is.na(fips_b), fips_a != fips_b) %>%
  select(fips_a, fips_b, name_a, name_b)

cat("Parsed", nrow(edges), "directed adjacency edges.\n")

# Quick sanity: edges should be roughly symmetric (within the file's
# convention each pair appears twice — once in each direction).
n_unique_pairs <- edges %>%
  mutate(
    lo = pmin(fips_a, fips_b),
    hi = pmax(fips_a, fips_b)
  ) %>%
  distinct(lo, hi) %>%
  nrow()
cat("Unique undirected pairs:", n_unique_pairs, "\n")
cat("Symmetry ratio (directed / 2*undirected):",
    round(nrow(edges) / (2 * n_unique_pairs), 3), "\n")

# ----------------------------- write ------------------------------------------

write_csv(edges, out_path)
cat("Wrote", nrow(edges), "directed edges to:\n  ", out_path, "\n")
