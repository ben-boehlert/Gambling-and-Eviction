################################################################################
# R/power/blindness_checks.R
#
# Automated blindness enforcement for the power-simulation framework.
# Implements POWER_SIMULATION_BLINDNESS_PROTOCOL.md §5:
#   - assert_no_forbidden_paths(): refuse reads under output/, figures/, or
#     from result-bearing docs (CLAUDE.md, AGENTS.md, README.md, START_HERE,
#     QUICK_START, HANDOFF, SESSION_REPORT).
#   - guarded_read_csv(): the single guarded entry point for CSV reads.
#   - assert_blinded(): re-verify no returned row violates the cutoffs.
#   - blinded_output_path(): all writes stay under output_blinded_power/.
#
# Paths are relative to the repository root; no setwd() is used.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
})

# Sourced-alongside dependency: power_paths() lives in config.R.
if (!exists("power_paths", mode = "function")) {
  source("R/power/config.R")
}

#' Refuse to read a path that falls in a blindness-prohibited location
#'
#' Normalizes \code{path} and hard-errors if any path component is a
#' \code{output} or \code{figures} directory, or if the basename matches a
#' result-bearing document (case-insensitive). Note that the framework's own
#' \code{output_blinded_power/} directory is NOT blocked (its component is not
#' the literal \code{output}).
#'
#' @param path A file path (relative or absolute).
#' @return Invisibly TRUE if allowed; otherwise \code{stop()}s.
#' @export
assert_no_forbidden_paths <- function(path) {
  norm  <- normalizePath(path, winslash = "/", mustWork = FALSE)
  parts <- strsplit(norm, "/", fixed = TRUE)[[1]]
  parts <- tolower(parts[nzchar(parts)])

  if (any(parts %in% c("output", "figures"))) {
    stop("Blindness violation: refusing to read under a prohibited directory ",
         "(output/ or figures/): ", path, call. = FALSE)
  }

  base <- tolower(basename(norm))
  forbidden_exact <- c("claude.md", "agents.md", "readme.md", "session_report.md")
  if (base %in% forbidden_exact) {
    stop("Blindness violation: refusing to read result-bearing document: ",
         path, call. = FALSE)
  }
  if (grepl("start_here|quick_start|handoff", base, ignore.case = TRUE)) {
    stop("Blindness violation: refusing to read result-bearing document: ",
         path, call. = FALSE)
  }

  invisible(TRUE)
}

#' Guarded CSV read
#'
#' Calls \code{assert_no_forbidden_paths()} then \code{readr::read_csv()}.
#' The only sanctioned way for framework code to read a CSV.
#'
#' @param path Path to a CSV file.
#' @param ... Passed to \code{readr::read_csv}.
#' @return A tibble.
#' @export
guarded_read_csv <- function(path, ...) {
  assert_no_forbidden_paths(path)
  if (!file.exists(path)) {
    stop("Data file not found: ", path, " (working dir: ", getwd(),
         "). Run from the repository root.", call. = FALSE)
  }
  readr::read_csv(path, show_col_types = FALSE, ...)
}

#' Assert that a returned panel contains no treated / anticipation-period rows
#'
#' O(n) join-based re-verification. For every row, flags a violation when the
#' month is at or after the state's (first-definition) treatment date minus the
#' anticipation window. For sample S1 (identified via
#' \code{attr(panel, "sample_id")}) also flags any month beyond the universal
#' cutoff. Hard error listing up to 10 offending state-months.
#'
#' @param panel Panel tibble (needs state_abb, month_date; sample_id attr).
#' @param schedule Tibble with state_abb and g_first (Date; NA = never-treated).
#' @param anticipation_months Anticipation exclusion window in months.
#' @param universal_cutoff Universal untreated cutoff (Date).
#' @return Invisibly TRUE if clean; otherwise \code{stop()}s.
#' @export
assert_blinded <- function(panel, schedule, anticipation_months,
                           universal_cutoff = as.Date("2018-05-31")) {
  stopifnot(all(c("state_abb", "month_date") %in% names(panel)))
  stopifnot(all(c("state_abb", "g_first") %in% names(schedule)))
  anticipation_months <- as.integer(anticipation_months)

  sched <- schedule %>% distinct(.data$state_abb, .data$g_first)

  chk <- panel %>%
    select(dplyr::all_of(c("state_abb", "month_date"))) %>%
    left_join(sched, by = "state_abb") %>%
    mutate(
      cutoff = .data$g_first %m-% months(anticipation_months),
      viol_treat = !is.na(.data$g_first) & .data$month_date >= .data$cutoff
    )

  viol <- chk %>% filter(.data$viol_treat)

  sid <- attr(panel, "sample_id")
  if (!is.null(sid) && identical(sid, "S1")) {
    viol_uc <- chk %>% filter(.data$month_date > universal_cutoff)
    viol <- bind_rows(viol, viol_uc) %>% distinct()
  }

  if (nrow(viol) > 0L) {
    show <- viol %>%
      distinct(.data$state_abb, .data$month_date) %>%
      arrange(.data$state_abb, .data$month_date) %>%
      head(10)
    stop("assert_blinded FAILED: ", nrow(viol),
         " offending state-month row(s) violate the blindness cutoff. ",
         "First up to 10:\n",
         paste(sprintf("  %s %s", show$state_abb, show$month_date),
               collapse = "\n"),
         call. = FALSE)
  }

  invisible(TRUE)
}

#' Build a write path guaranteed to live under output_blinded_power/
#'
#' Joins \code{...} under the framework output root and hard-errors if the
#' normalized result escapes that root (e.g. via \code{..}). Creates the
#' parent directory unless \code{create = FALSE}.
#'
#' @param ... Path components under the output root.
#' @param root Output root (default from \code{power_paths()}).
#' @param create Create the parent directory (default TRUE).
#' @return Normalized absolute path string.
#' @export
blinded_output_path <- function(..., root = power_paths()$output_root,
                                create = TRUE) {
  # Lexical absolute normalization that collapses "." and ".." even for
  # non-existent paths (macOS normalizePath does not resolve ".." unless the
  # path exists, which would let "../output/x" slip through).
  .lexical_abs <- function(p) {
    if (!grepl("^(/|[A-Za-z]:)", p)) p <- file.path(getwd(), p)
    parts <- strsplit(p, "/", fixed = TRUE)[[1]]
    out <- character(0)
    for (part in parts) {
      if (part == "" || part == ".") next
      if (part == "..") {
        if (length(out) > 0L) out <- out[-length(out)]
        next
      }
      out <- c(out, part)
    }
    paste0("/", paste(out, collapse = "/"))
  }

  root_abs <- .lexical_abs(root)
  target   <- .lexical_abs(file.path(root, ...))

  inside <- identical(target, root_abs) ||
    startsWith(paste0(target, "/"), paste0(root_abs, "/"))
  if (!inside) {
    stop("Blindness violation: output path escapes ", root, ": ", target,
         call. = FALSE)
  }

  if (create) {
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  }
  target
}
