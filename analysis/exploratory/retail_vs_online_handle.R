## Retail vs. online sports-betting handle, per capita
## Data: data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv (state totals)
##       data/raw/sports_gambling_legalization_dates.csv (channel start dates)
## Population: 2020 Census resident population (April 1, 2020), from Census/Wikipedia.
## Note: LSR handle is a STATE TOTAL (retail+online combined), not split by channel.
## We recover the split from legalization TIMING: a state-month is "retail-only"
## if online betting was not yet legal there that month, "online-available" otherwise.

suppressPackageStartupMessages({library(tidyverse); library(lubridate)})

proj <- "/Users/bb1806/Documents/GitHub Doc/Gambling-and-Eviction"
handle <- read_csv(file.path(proj, "data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv"),
                   show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date)) %>%
  filter(!is.na(Handle))   # 64 state-months report revenue but not handle; drop them
dates <- read_csv(file.path(proj, "data/raw/sports_gambling_legalization_dates.csv"),
                  show_col_types = FALSE) %>%
  mutate(online_start_date = as.Date(online_start_date),
         retail_start_date = as.Date(retail_start_date))

## 2020 Census resident population
pop <- tribble(
  ~State, ~pop,
  "California",39538223,"Texas",29145505,"Florida",21538187,"New York",20201249,
  "Pennsylvania",13002700,"Illinois",12812508,"Ohio",11799448,"Georgia",10711908,
  "North Carolina",10439388,"Michigan",10077331,"New Jersey",9288994,"Virginia",8631393,
  "Washington",7705281,"Arizona",7151502,"Tennessee",6910840,"Massachusetts",7029917,
  "Indiana",6785528,"Missouri",6154913,"Maryland",6177224,"Colorado",5773714,
  "Wisconsin",5893718,"Minnesota",5706494,"South Carolina",5118425,"Alabama",5024279,
  "Louisiana",4657757,"Kentucky",4505836,"Oregon",4237256,"Oklahoma",3959353,
  "Connecticut",3605944,"Utah",3271616,"Nevada",3104614,"Iowa",3190369,
  "Arkansas",3011524,"Kansas",2937880,"Mississippi",2961279,"New Mexico",2117522,
  "Idaho",1839106,"Nebraska",1961504,"West Virginia",1793716,"Hawaii",1455271,
  "New Hampshire",1377529,"Maine",1362359,"Montana",1084225,"Rhode Island",1097379,
  "Delaware",989948,"South Dakota",886667,"North Dakota",779094,"Alaska",733391,
  "Vermont",643077,"Wyoming",576851,"District of Columbia",689545)

## Assemble. Restrict to the 29 states in the legalization file, where channel
## timing is known. This drops NV, KY, ME, NE, VT (no start-date classification;
## NV is a pre-PASPA tourism market whose per-capita handle is not comparable).
df <- handle %>%
  inner_join(dates %>% select(state, online_start_date, retail_start_date,
                             online_only, retail_only, both),
            by = c("State" = "state")) %>%
  left_join(pop, by = "State") %>%
  mutate(
    online_live = !is.na(online_start_date) & month_date >= online_start_date,
    regime = if_else(online_live, "online-available", "retail-only"),
    handle_pc = Handle / pop)      # dollars of handle per resident, that month

stopifnot(all(!is.na(df$pop)))     # every state matched a population

## ---- 1. National pooled: mean monthly per-capita handle by regime ----
regime_tab <- df %>%
  group_by(regime) %>%
  summarise(state_months = n(),
            mean_handle_pc = mean(handle_pc),
            median_handle_pc = median(handle_pc),
            total_handle_bil = sum(Handle)/1e9, .groups="drop")

## ---- 2. Aggregate volume: share of all handle under each regime ----
vol <- df %>% summarise(total = sum(Handle),
                        retail_only = sum(Handle[regime=="retail-only"]),
                        online = sum(Handle[regime=="online-available"]))

## ---- 3. Within-state transition: retail-only period vs online period ----
## states that ran retail BEFORE online (a genuine retail-only window >= 2 months)
trans <- dates %>%
  filter(!is.na(retail_start_date), !is.na(online_start_date),
         online_start_date > retail_start_date,
         interval(retail_start_date, online_start_date) %/% months(1) >= 2) %>%
  pull(state)

trans_tab <- df %>%
  filter(State %in% trans) %>%
  group_by(State, regime) %>%
  summarise(mo = n(), mean_pc = mean(handle_pc), .groups="drop") %>%
  pivot_wider(names_from=regime, values_from=c(mo, mean_pc)) %>%
  mutate(online_multiple = `mean_pc_online-available` / `mean_pc_retail-only`) %>%
  arrange(desc(online_multiple))

## ---- 4. Pure retail-only states (never legalized online) as retail benchmark ----
pure_retail <- dates %>% filter(retail_only) %>% pull(state)
pure_online <- dates %>% filter(online_only) %>% pull(state)

bench <- df %>%
  mutate(grp = case_when(State %in% pure_retail ~ "pure retail-only states",
                         State %in% pure_online ~ "online-only states",
                         TRUE ~ "both-channel states")) %>%
  group_by(grp) %>%
  summarise(states = n_distinct(State), state_months = n(),
            mean_handle_pc = mean(handle_pc), .groups="drop")

## ---- print ----
cat("\n==================================================================\n")
cat("RETAIL vs ONLINE SPORTS-BETTING HANDLE, PER CAPITA (2020 Census pop)\n")
cat("Sample: 29 states with known channel start dates, June 2018 - latest month\n")
cat("==================================================================\n")

cat("\n[1] National pooled mean MONTHLY handle per resident, by regime:\n")
regime_tab %>%
  mutate(across(c(mean_handle_pc, median_handle_pc), ~round(.,2)),
         total_handle_bil = round(total_handle_bil,1)) %>%
  print()
cat(sprintf("    -> online-available regime is %.1fx the retail-only regime (mean per-capita).\n",
    regime_tab$mean_handle_pc[regime_tab$regime=="online-available"] /
    regime_tab$mean_handle_pc[regime_tab$regime=="retail-only"]))

cat("\n[2] Aggregate HANDLE VOLUME, all state-months pooled:\n")
cat(sprintf("    Total handle              : $%.1f billion\n", vol$total/1e9))
cat(sprintf("    Under retail-only regime  : $%.1f billion (%.1f%%)\n",
            vol$retail_only/1e9, 100*vol$retail_only/vol$total))
cat(sprintf("    Under online-available    : $%.1f billion (%.1f%%)\n",
            vol$online/1e9, 100*vol$online/vol$total))

cat("\n[3] Within-state transition (retail-first states, >=2mo retail-only window):\n")
cat("    mean monthly $/resident, retail-only period vs online period:\n")
trans_tab %>%
  transmute(State,
            retail_mo = `mo_retail-only`, retail_pc = round(`mean_pc_retail-only`,2),
            online_mo = `mo_online-available`, online_pc = round(`mean_pc_online-available`,2),
            online_x_retail = round(online_multiple,1)) %>%
  print(n=Inf)
cat(sprintf("    -> median state: online handle/capita is %.0fx its retail-only handle/capita.\n",
            median(trans_tab$online_multiple)))

cat("\n[4] Benchmark by channel availability (whole-series mean $/resident/month):\n")
bench %>% mutate(mean_handle_pc = round(mean_handle_pc,2)) %>% print()

## save
outdir <- file.path(proj, "output/retail_vs_online")
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
write_csv(regime_tab, file.path(outdir, "regime_per_capita.csv"))
write_csv(trans_tab, file.path(outdir, "within_state_transition.csv"))
write_csv(bench, file.path(outdir, "channel_availability_benchmark.csv"))
cat(sprintf("\nSaved CSVs to %s\n", outdir))
cat(sprintf("Latest month in data: %s\n", format(max(df$month_date))))
