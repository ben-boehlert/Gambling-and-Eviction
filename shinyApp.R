# app.R
# DiD Power Explorer with FIXED switcher dates (no free "treatment start" slider)

library(shiny)
library(tidyverse)
library(fixest)

# ----------------------------
# Load panel
# ----------------------------
load("power_analysis_FINAL.RData")
stopifnot(all(c("state", "month", "outcome") %in% names(analysis_panel)))

analysis_panel <- analysis_panel %>%
  mutate(
    state = as.character(state),
    month = as.Date(month)
  )

# ----------------------------
# Load adoption dates (switcher dates)
# ----------------------------
dates_path <- "sports_gambling_legalization_dates.csv"
stopifnot(file.exists(dates_path))

adopt_raw <- readr::read_csv(dates_path, show_col_types = FALSE)

# Choose which date column is your "switcher date"
# Default: first_start_date (change in UI too)
date_cols <- intersect(names(adopt_raw), c("first_start_date", "online_start_date", "retail_start_date"))
stopifnot(length(date_cols) >= 1)

# Coerce to Date if not already
for (cc in date_cols) {
  adopt_raw[[cc]] <- as.Date(adopt_raw[[cc]])
}

# We'll join a chosen adoption date column into the panel dynamically in server.

# ----------------------------
# Helpers
# ----------------------------

make_panel_N <- function(panel, N_total) {
  # Sample observed states with replacement; relabel duplicates as distinct synthetic states.
  states <- unique(panel$state)
  picked <- sample(states, N_total, replace = TRUE)
  
  purrr::map_dfr(seq_along(picked), function(i) {
    panel %>%
      filter(state == picked[i]) %>%
      mutate(state = paste0("SYN_", i))
  })
}

# One simulated p-value for D, using fixed adoption dates per state
one_pval_fixed_dates <- function(panel, effect, k_treated, switcher_states) {
  # switcher_states: vector of states with non-NA adopt_date in THIS panel
  if (length(switcher_states) < 2) return(NA_real_)
  if (k_treated >= length(unique(panel$state))) return(NA_real_)
  if (k_treated > length(switcher_states)) return(NA_real_)
  
  treated <- sample(switcher_states, k_treated, replace = FALSE)
  
  sim <- panel %>%
    mutate(
      D = as.integer(state %in% treated & !is.na(adopt_date) & month >= adopt_date),
      outcome_sim = outcome - effect * D
    )
  
  m <- tryCatch(
    feols(outcome_sim ~ D | state + month, data = sim, cluster = ~state),
    error = function(e) NULL
  )
  if (is.null(m)) return(NA_real_)
  
  ct <- fixest::coeftable(m)
  if (!("D" %in% rownames(ct))) return(NA_real_)
  
  as.numeric(ct["D", "Pr(>|t|)"])
}

simulate_power <- function(panel, effect, k_treated,
                           n_sims, alpha,
                           size_correct = TRUE, n_calib = NULL) {
  
  switcher_states <- panel %>%
    distinct(state, adopt_date) %>%
    filter(!is.na(adopt_date)) %>%
    pull(state)
  
  if (is.null(n_calib)) n_calib <- n_sims
  
  if (!size_correct) {
    pvals <- replicate(n_sims, one_pval_fixed_dates(panel, effect, k_treated, switcher_states))
    power <- mean(pvals <= alpha, na.rm = TRUE)
    return(list(power = power, crit_p = alpha, size_hat = NA_real_))
  }
  
  # size-correct: calibrate critical p-value using effect=0
  p0 <- replicate(n_calib, one_pval_fixed_dates(panel, 0, k_treated, switcher_states))
  crit_p <- as.numeric(stats::quantile(p0, probs = alpha, na.rm = TRUE))
  size_hat <- mean(p0 <= crit_p, na.rm = TRUE)
  
  p1 <- replicate(n_sims, one_pval_fixed_dates(panel, effect, k_treated, switcher_states))
  power <- mean(p1 <= crit_p, na.rm = TRUE)
  
  list(power = power, crit_p = crit_p, size_hat = size_hat)
}

simulate_curve <- function(panel, effects, k_treated,
                           n_sims, alpha,
                           size_correct = TRUE, n_calib = NULL) {
  
  switcher_states <- panel %>%
    distinct(state, adopt_date) %>%
    filter(!is.na(adopt_date)) %>%
    pull(state)
  
  if (is.null(n_calib)) n_calib <- n_sims
  
  if (!size_correct) {
    curve <- map_dfr(effects, function(eff) {
      pvals <- replicate(n_sims, one_pval_fixed_dates(panel, eff, k_treated, switcher_states))
      tibble(effect = eff, power = mean(pvals <= alpha, na.rm = TRUE))
    })
    return(list(curve = curve, crit_p = alpha, size_hat = NA_real_))
  }
  
  p0 <- replicate(n_calib, one_pval_fixed_dates(panel, 0, k_treated, switcher_states))
  crit_p <- as.numeric(stats::quantile(p0, probs = alpha, na.rm = TRUE))
  size_hat <- mean(p0 <= crit_p, na.rm = TRUE)
  
  curve <- map_dfr(effects, function(eff) {
    pvals <- replicate(n_sims, one_pval_fixed_dates(panel, eff, k_treated, switcher_states))
    tibble(effect = eff, power = mean(pvals <= crit_p, na.rm = TRUE))
  })
  
  list(curve = curve, crit_p = crit_p, size_hat = size_hat)
}

interp_mde <- function(curve_df, target_power = 0.80) {
  df <- curve_df %>% arrange(effect)
  if (all(is.na(df$power))) return(NA_real_)
  if (max(df$power, na.rm = TRUE) < target_power) return(NA_real_)
  if (min(df$power, na.rm = TRUE) >= target_power) return(min(df$effect, na.rm = TRUE))
  
  idx <- which(df$power >= target_power)[1]
  if (idx == 1) return(df$effect[1])
  
  x0 <- df$effect[idx - 1]; y0 <- df$power[idx - 1]
  x1 <- df$effect[idx];     y1 <- df$power[idx]
  x0 + (target_power - y0) * (x1 - x0) / (y1 - y0)
}

parse_effects <- function(txt) {
  nums <- suppressWarnings(as.numeric(strsplit(gsub("[\\s]+", ",", txt), ",")[[1]]))
  nums <- nums[is.finite(nums)]
  sort(unique(nums))
}

find_min_k <- function(panel, effect, target_power,
                       k_grid, n_sims, alpha,
                       size_correct = TRUE, n_calib = NULL) {
  
  out <- map_dfr(k_grid, function(k) {
    res <- simulate_power(panel, effect, k, n_sims, alpha, size_correct, n_calib)
    tibble(k_treated = k, power = res$power, crit_p = res$crit_p, size_hat = res$size_hat)
  })
  
  k_needed <- if (any(out$power >= target_power, na.rm = TRUE)) min(out$k_treated[out$power >= target_power]) else NA_integer_
  list(grid = out, k_needed = k_needed)
}

# ----------------------------
# UI
# ----------------------------
ui <- fluidPage(
  titlePanel("DiD Power Explorer (States / Switchers / Effect Size) — fixed switcher dates"),
  sidebarLayout(
    sidebarPanel(
      h4("Panel size"),
      radioButtons(
        "panel_mode",
        "Total states (N):",
        choices = c("Use observed states only" = "observed",
                    "Extrapolate by resampling states (synthetic N)" = "resample"),
        selected = "observed"
      ),
      sliderInput("N_total", "Total states (N)", min = 8, max = 120, value = length(unique(analysis_panel$state)), step = 1),
      
      hr(),
      
      h4("Switcher dates (not a free variable)"),
      selectInput("adopt_col", "Adoption date column to use:", choices = date_cols, selected = "first_start_date"),
      
      hr(),
      
      h4("Design knobs"),
      sliderInput("k_treated", "Treated switcher states (K)", min = 2, max = 20, value = 10, step = 1),
      
      hr(),
      
      h4("Inference + simulation"),
      numericInput("effect_single", "Effect size (single effect)", value = 1.5, min = 0, step = 0.1),
      numericInput("alpha", "Alpha", value = 0.05, min = 0.001, max = 0.2, step = 0.005),
      numericInput("n_sims", "# simulations per point", value = 250, min = 50, max = 5000, step = 50),
      
      checkboxInput("size_correct", "Size-correct (calibrate cutoff using effect=0)", value = TRUE),
      numericInput("n_calib", "# calibration sims (effect=0)", value = 250, min = 50, max = 5000, step = 50),
      
      hr(),
      
      h4("Power curve + MDE"),
      textInput("effects_grid", "Effect grid (comma-separated)", value = "0,0.5,1,1.5,2,2.5,3,4,5"),
      numericInput("target_power", "Target power (for MDE)", value = 0.80, min = 0.5, max = 0.95, step = 0.01),
      
      hr(),
      
      h4("Solve for K"),
      numericInput("effect_for_k", "Effect size (solve for K)", value = 1.5, min = 0, step = 0.1),
      numericInput("target_power_k", "Target power (solve for K)", value = 0.80, min = 0.5, max = 0.95, step = 0.01),
      numericInput("min_k", "Min K to consider", value = 6, min = 2, step = 1),
      
      actionButton("run_single", "Run single-effect power", class = "btn-primary"),
      actionButton("run_curve", "Run power curve + MDE", class = "btn-success"),
      actionButton("run_findk", "Find min K for target power", class = "btn-warning"),
      
      hr(),
      helpText("It auto-runs once on load. Use 250 sims for exploring; 1000+ for grant tables.")
    ),
    
    mainPanel(
      h4("Summary"),
      verbatimTextOutput("summary_txt"),
      hr(),
      
      tabsetPanel(
        tabPanel("Single effect",
                 tableOutput("single_tbl")),
        tabPanel("Power curve",
                 tableOutput("curve_tbl"),
                 plotOutput("curve_plot", height = 350)),
        tabPanel("Find min K",
                 tableOutput("findk_tbl"),
                 plotOutput("findk_plot", height = 350))
      )
    )
  )
)

# ----------------------------
# Server
# ----------------------------
server <- function(input, output, session) {
  
  # Build a panel with adopt_date joined
  base_panel <- reactive({
    # adoption dates from CSV (state names)
    adopt_map <- adopt_raw %>%
      transmute(
        state_name = as.character(state),
        state_key  = tolower(state_name),
        adopt_date = as.Date(.data[[input$adopt_col]])
      )
    
    # --- Name/ABB/FIPS crosswalk (no datasets::state.fips dependency) ---
    # FIPS for the 50 states + DC in the order of state.abb/state.name + DC appended
    fips_50 <- c(
      1, 2, 4, 5, 6, 8, 9, 10, 11, 12,
      13, 15, 16, 17, 18, 19, 20, 21, 22, 23,
      24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
      34, 35, 36, 37, 38, 39, 40, 41, 42, 44,
      45, 46, 47, 48, 49, 50, 51, 53, 54, 55,
      56
    )
    name_51 <- c(state.name, "District of Columbia")
    abb_51  <- c(state.abb,  "DC")
    fips_51 <- c(fips_50,    11L)  # DC is 11; note it is also in fips_50? (no)
    
    crosswalk <- tibble(
      state_key  = tolower(name_51),
      state_abb  = abb_51,
      state_fips = as.integer(fips_51)
    )
    
    adopt_map <- adopt_map %>%
      left_join(crosswalk, by = "state_key") %>%
      select(state_name, state_abb, state_fips, adopt_date)
    
    # --- Detect panel state coding and join appropriately ---
    p <- analysis_panel
    st_u <- unique(p$state)
    
    is_numericish <- is.numeric(p$state) ||
      (is.character(p$state) && all(grepl("^\\d+$", st_u)))
    
    is_abb <- is.character(p$state) && all(nchar(st_u) == 2)
    
    if (is_numericish) {
      p %>%
        mutate(state_fips = as.integer(state)) %>%
        left_join(adopt_map %>% select(state_fips, adopt_date), by = "state_fips") %>%
        select(-state_fips)
    } else if (is_abb) {
      p %>%
        left_join(adopt_map %>% select(state = state_abb, adopt_date), by = "state")
    } else {
      p %>%
        mutate(state_key = tolower(as.character(state))) %>%
        left_join(adopt_map %>% select(state_key, adopt_date), by = "state_key") %>%
        select(-state_key)
    }
  })
  
  
  
  panel_reactive <- reactive({
    p <- base_panel()
    
    if (input$panel_mode == "observed") {
      p
    } else {
      make_panel_N(p, input$N_total)
    }
  })
  
  # Update N slider bounds based on mode
  observeEvent(input$panel_mode, {
    if (input$panel_mode == "observed") {
      updateSliderInput(session, "N_total",
                        value = length(unique(analysis_panel$state)),
                        min = 8,
                        max = length(unique(analysis_panel$state)))
    } else {
      updateSliderInput(session, "N_total", min = 8, max = 120)
    }
  })
  
  # Update K bounds based on number of switchers available
  observeEvent(list(panel_reactive(), input$min_k), {
    p <- panel_reactive()
    n_switchers <- p %>% distinct(state, adopt_date) %>% filter(!is.na(adopt_date)) %>% nrow()
    n_states <- length(unique(p$state))
    
    max_k <- max(2, min(n_switchers, n_states - 2))
    min_k <- max(2, min(input$min_k, max_k))
    
    updateSliderInput(session, "k_treated",
                      min = 2,
                      max = max_k,
                      value = min(max(input$k_treated, 2), max_k))
    
    # also clamp min_k input if user set it too high
    if (input$min_k != min_k) updateNumericInput(session, "min_k", value = min_k)
  })
  
  # Reactive holders so app isn't blank
  single_store <- reactiveVal(NULL)
  curve_store  <- reactiveVal(NULL)
  findk_store  <- reactiveVal(NULL)
  
  run_single_now <- function() {
    p <- panel_reactive()
    simulate_power(
      panel = p,
      effect = input$effect_single,
      k_treated = input$k_treated,
      n_sims = input$n_sims,
      alpha = input$alpha,
      size_correct = input$size_correct,
      n_calib = input$n_calib
    )
  }
  
  run_curve_now <- function() {
    p <- panel_reactive()
    effects <- parse_effects(input$effects_grid)
    stopifnot(length(effects) >= 2)
    
    res <- simulate_curve(
      panel = p,
      effects = effects,
      k_treated = input$k_treated,
      n_sims = input$n_sims,
      alpha = input$alpha,
      size_correct = input$size_correct,
      n_calib = input$n_calib
    )
    res$mde <- interp_mde(res$curve, target_power = input$target_power)
    res
  }
  
  run_findk_now <- function() {
    p <- panel_reactive()
    n_switchers <- p %>% distinct(state, adopt_date) %>% filter(!is.na(adopt_date)) %>% nrow()
    n_states <- length(unique(p$state))
    max_k <- max(2, min(n_switchers, n_states - 2))
    k_grid <- seq(max(2, input$min_k), max_k, by = 1)
    
    find_min_k(
      panel = p,
      effect = input$effect_for_k,
      target_power = input$target_power_k,
      k_grid = k_grid,
      n_sims = input$n_sims,
      alpha = input$alpha,
      size_correct = input$size_correct,
      n_calib = input$n_calib
    )
  }
  
  # Auto-run once so the app isn't empty
  # Auto-run once (ignoreInit = FALSE) and also re-run when you click
  observeEvent(input$run_single, {
    single_store(run_single_now())
  }, ignoreInit = FALSE)
  
  observeEvent(input$run_curve, {
    curve_store(run_curve_now())
  }, ignoreInit = FALSE)
  
  observeEvent(input$run_findk, {
    findk_store(run_findk_now())
  }, ignoreInit = FALSE)
  
  
  observeEvent(input$run_single, {
    single_store(run_single_now())
  })
  
  observeEvent(input$run_curve, {
    curve_store(run_curve_now())
  })
  
  observeEvent(input$run_findk, {
    findk_store(run_findk_now())
  })
  
  output$summary_txt <- renderPrint({
    p <- panel_reactive()
    N <- length(unique(p$state))
    rng <- range(p$month)
    
    # switcher coverage
    sw <- p %>% distinct(state, adopt_date)
    n_switchers <- sw %>% filter(!is.na(adopt_date)) %>% nrow()
    missing <- sw %>% filter(is.na(adopt_date)) %>% pull(state) %>% unique() %>% sort()
    
    cat("Panel info\n---------\n")
    cat("States (N):", N, "\n")
    cat("Months:", format(rng[1]), "to", format(rng[2]), "\n")
    cat("Rows:", nrow(p), "\n\n")
    
    cat("Switcher dates\n-------------\n")
    cat("Adoption date column:", input$adopt_col, "\n")
    cat("Switcher states with dates:", n_switchers, "\n")
    cat("States missing an adoption date mapping:", length(missing), "\n")
    if (length(missing) > 0) {
      cat("Missing states (first 20):", paste(head(missing, 20), collapse = ", "), "\n")
    }
    cat("\n")
    
    cat("Current design\n-------------\n")
    cat("Treated switchers (K):", input$k_treated, "\n")
    cat("Alpha:", input$alpha, "\n")
    cat("Sims per point:", input$n_sims, "\n")
    cat("Size-correct:", input$size_correct, "\n")
  })
  
  output$single_tbl <- renderTable({
    res <- single_store()
    if (is.null(res)) return(tibble(note = "No results yet."))
    
    tibble(
      effect = input$effect_single,
      K_treated = input$k_treated,
      alpha = input$alpha,
      sims = input$n_sims,
      size_correct = input$size_correct,
      crit_p_used = res$crit_p,
      size_hat_under_null = res$size_hat,
      power = res$power
    )
  }, digits = 4)
  
  output$curve_tbl <- renderTable({
    res <- curve_store()
    if (is.null(res)) return(tibble(note = "No results yet."))
    
    res$curve %>%
      mutate(K_treated = input$k_treated) %>%
      select(K_treated, effect, power)
  }, digits = 4)
  
  output$curve_plot <- renderPlot({
    res <- curve_store()
    if (is.null(res)) return(NULL)
    
    df <- res$curve
    
    ggplot(df, aes(x = effect, y = power)) +
      geom_line() +
      geom_point() +
      geom_hline(yintercept = input$target_power, linetype = 2) +
      labs(
        x = "Effect size",
        y = "Power",
        title = paste0(
          "Power curve (K = ", input$k_treated,
          if (input$size_correct) paste0(", size-corrected; crit_p=", signif(res$crit_p, 3)) else ""
        ),
        subtitle = paste0("MDE at target power = ", input$target_power, ": ", signif(res$mde, 4))
      ) +
      theme_minimal()
  })
  
  output$findk_tbl <- renderTable({
    res <- findk_store()
    if (is.null(res)) return(tibble(note = "No results yet."))
    
    tibble(
      effect = input$effect_for_k,
      target_power = input$target_power_k,
      k_needed = res$k_needed
    )
  }, digits = 4)
  
  output$findk_plot <- renderPlot({
    res <- findk_store()
    if (is.null(res)) return(NULL)
    
    df <- res$grid
    
    ggplot(df, aes(x = k_treated, y = power)) +
      geom_line() +
      geom_point() +
      geom_hline(yintercept = input$target_power_k, linetype = 2) +
      labs(
        x = "K treated switchers",
        y = "Power",
        title = paste0("Power vs K (effect=", input$effect_for_k, "; target=", input$target_power_k, ")"),
        subtitle = paste0("Min K achieving target: ", res$k_needed)
      ) +
      theme_minimal()
  })
}

shinyApp(ui, server)

