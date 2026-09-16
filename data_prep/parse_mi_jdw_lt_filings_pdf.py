"""Parse the Michigan SCAO Judicial Data Warehouse landlord/tenant filings PDF.

Source (statewide only -- there are NO county values in this document):
  https://www.courts.michigan.gov/49bb33/siteassets/covid/covid-19/conditional-dismissals.pdf

The PDF has four pages. This script reads two of them:
  page 1  Landlord/Tenant New Filings, clustered bar chart, calendar month x year
  page 3  Landlord/Tenant New Filings, table, week-of-year x year

Two traps in this document, both handled explicitly:

  1. YEARS ARE BARS, AND ONE COLOUR IS REUSED. The page-1 legend assigns 2019
     and 2023 the SAME fill colour (0.0667, 0.5529, 1.0). Colour therefore
     cannot identify a series. Bars are identified by their ORDER within each
     month cluster (2019..2026 left to right); the legend colour is used only
     as an assertion.

  2. THE BAR LABELS ARE ROTATED AND READ BOTTOM-TO-TOP. Their glyphs advance
     upward, so reading order is DESCENDING `top`. pdfplumber's extract_words()
     assembles them top-to-bottom, i.e. REVERSED -- it returns the May-2020
     label "302" as "203". Palindromic values (545, 646) mask the bug. Labels
     are therefore rebuilt from raw chars, and extract_words is never used.

  On page 3, cells are assigned to years by their right edge (values are
  right-aligned), never by reading order: blank cells would otherwise shift
  every later value into the wrong year column.

Validation enforced (the script aborts if any of these fail):
  * page 3: every row's year cells sum to that row's printed Total
  * page 3: every year column sums to the printed grand total (and 1,090,431)
  * page 1: bar fill colour matches the legend colour for its position
  * page 1: for years whose 12 months are all labelled (2019, 2022), the
    monthly values sum to that year's page-3 annual total

Where exactly one month of a year is unlabelled, its value is DERIVED by
subtracting the labelled months from that year's published annual total and
flagged `derived_from_annual_total`. Where more than one is missing, the cells
are left empty -- never zero.

Coverage caveat carried from the source: these are statewide counts EXCLUDING
Berrien Co., Grand Rapids, Dearborn Hts, Center Line & Warren, Northern Macomb
Co., and Grandville & Walker. Data is preliminary and not vetted by individual
courts; the refresh week and the week prior may be incomplete.

Requires: pdfplumber.  Usage from project root:
  python3 data_prep/parse_mi_jdw_lt_filings_pdf.py [path/to/conditional-dismissals.pdf]
"""
import sys, re, csv, os
from collections import defaultdict
import pdfplumber

PDF = sys.argv[1] if len(sys.argv) > 1 else "data/raw/michigan/conditional-dismissals.pdf"
OUT = "data/raw/michigan"

VAL = re.compile(r"^\d{1,3}(?:,\d{3})*$|^\d+$")
num = lambda s: int(s.replace(",", ""))

LEGEND = [(2019,(0.0667,0.5529,1.0)), (2020,(0.0549,0.102,0.4667)),
          (2021,(0.0039,0.7216,0.6667)), (2022,(0.3412,0.2314,0.5725)),
          (2023,(0.0667,0.5529,1.0)),                    # same colour as 2019
          (2024,(0.0706,0.1373,0.6196)), (2025,(0.902,0.4235,0.2157)),
          (2026,(0.4196,0.0,0.4824))]
MONTHS = ["January","February","March","April","May","June",
          "July","August","September","October","November","December"]

# page-3 column right edges (values are right-aligned)
L_COLS = {2019:146.24,2020:180.74,2021:212.99,2022:244.49,
          2023:276.74,2024:308.99,2025:338.24,2026:367.49}; L_TOT = 407.25
R_COLS = {2019:552.74,2020:590.24,2021:631.49,2022:672.74,
          2023:716.99,2024:759.32,2025:797.07}; R_TOT = 880.46   # no Jul-Dec 2026
TOL = 4.5
WK_MONTH = {"jan":1,"feb":2,"march":3,"april":4,"may":5,"june":6,
            "july":7,"aug":8,"sept":9,"oct":10,"nov":11,"dec":12}
PRINTED = {2019:181440,2020:87863,2021:116307,2022:158566,
           2023:161332,2024:159997,2025:160859,2026:64067}
GRAND = 1090431

def tokenize(chars, gap=1.2):
    chars = sorted(chars, key=lambda c: c["x0"])
    if not chars: return []
    toks, cur = [], [chars[0]]
    for c in chars[1:]:
        if c["x0"] - cur[-1]["x1"] > gap: toks.append(cur); cur = [c]
        else: cur.append(c)
    toks.append(cur)
    return [("".join(x["text"] for x in t).strip(), t[-1]["x1"]) for t in toks]

def parse_weeks(page):
    by_top = defaultdict(list)
    for c in page.chars: by_top[round(c["top"], 1)].append(c)
    recs = []
    for top in sorted(by_top):
        for lo, hi, cols, tot_e in ((0,410,L_COLS,L_TOT), (410,1000,R_COLS,R_TOT)):
            toks = tokenize([c for c in by_top[top] if lo <= c["x0"] < hi])
            if not toks: continue
            m = re.match(r"^(\d+)(?:st|nd|rd|th)\s+W[Ee]ek,\s*([A-Za-z]+)$", toks[0][0])
            if not m: continue
            wk, mon = int(m.group(1)), m.group(2).lower()
            assert mon in WK_MONTH, f"unrecognised month {mon!r}"
            total, cells = None, {}
            for text, x1 in toks[1:]:
                assert VAL.match(text), f"non-numeric cell {text!r} in {toks[0][0]!r}"
                if abs(x1 - tot_e) <= TOL: total = num(text); continue
                y, e = min(cols.items(), key=lambda kv: abs(x1 - kv[1]))
                assert abs(x1 - e) <= TOL, f"cell {text!r} matches no year column"
                assert y not in cells, f"duplicate year {y}"
                cells[y] = num(text)
            assert total is not None, f"no Total in {toks[0][0]!r}"
            assert sum(cells.values()) == total, \
                f"{toks[0][0]!r}: row sum {sum(cells.values())} != Total {total}"
            for y, n in cells.items():
                recs.append({"week_of_year":wk, "week_month_bucket":WK_MONTH[mon],
                             "year":y, "filings":n})
    col = defaultdict(int)
    for r in recs: col[r["year"]] += r["filings"]
    for y, t in PRINTED.items():
        assert col[y] == t, f"{y} column sum {col[y]} != printed {t}"
    assert sum(col.values()) == GRAND, "grand total mismatch"
    return recs

def parse_months(page):
    bars = sorted([r for r in page.rects
                   if abs((r["x1"]-r["x0"]) - 7.3) < 0.5 and r["top"] > 60],
                  key=lambda r: r["x0"])
    clusters, cur = [], [bars[0]]
    for b in bars[1:]:
        if b["x0"] - cur[-1]["x1"] > 6: clusters.append(cur); cur = [b]
        else: cur.append(b)
    clusters.append(cur)
    assert len(clusters) == 12, f"expected 12 month clusters, got {len(clusters)}"

    # rebuild rotated labels from chars: reading order is DESCENDING top
    labels = []
    g = defaultdict(list)
    for c in page.chars:
        if not c.get("upright") and c["top"] > 60: g[round(c["x0"], 1)].append(c)
    for cs in g.values():
        cs.sort(key=lambda c: -c["top"])
        s = "".join(c["text"] for c in cs)
        if re.fullmatch(r"\d{1,3}(,\d{3})*", s):
            labels.append((sum((c["x0"]+c["x1"])/2 for c in cs)/len(cs),
                           min(c["top"] for c in cs), num(s)))

    index = {}
    for mi, cl in enumerate(clusters):
        cl.sort(key=lambda r: r["x0"])
        for yi, bar in enumerate(cl): index[(mi, yi)] = bar
    assign = {}
    for lcx, ltop, lval in labels:
        cand = [(abs(((b["x0"]+b["x1"])/2) - lcx), k)
                for k, b in index.items() if ltop < b["top"]]
        d, k = min(cand)
        assert d < 5, f"label {lval} matched no bar (nearest {d:.2f}pt)"
        assert k not in assign, f"two labels claim bar {k}"
        assign[k] = lval

    rows = []
    for mi, cl in enumerate(clusters):
        cl.sort(key=lambda r: r["x0"])
        for yi, bar in enumerate(cl):
            year, col = LEGEND[yi]
            assert tuple(round(v,4) for v in bar["non_stroking_color"]) == \
                   tuple(round(v,4) for v in col), f"colour/position mismatch {MONTHS[mi]} {year}"
            v = assign.get((mi, yi))
            rows.append({"month_num":mi+1, "month":MONTHS[mi], "year":year,
                         "filings":v,
                         "source":"chart_label" if v is not None else None})

    # fill single-missing months exactly from the published annual total
    by_year = defaultdict(list)
    for r in rows: by_year[r["year"]].append(r)
    for y, rs in by_year.items():
        miss = [r for r in rs if r["filings"] is None]
        known = sum(r["filings"] for r in rs if r["filings"] is not None)
        if not miss:
            assert known == PRINTED[y], f"{y} labelled months sum {known} != annual {PRINTED[y]}"
        elif len(miss) == 1:
            miss[0]["filings"] = PRINTED[y] - known
            miss[0]["source"] = "derived_from_annual_total"
    return rows

with pdfplumber.open(PDF) as pdf:
    weeks = parse_weeks(pdf.pages[2])
    months = parse_months(pdf.pages[0])

os.makedirs(OUT, exist_ok=True)
wp = os.path.join(OUT, "mi_lt_statewide_week_year.csv")
with open(wp, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["week_of_year","week_month_bucket","year","filings"])
    w.writeheader(); w.writerows(sorted(weeks, key=lambda r:(r["year"], r["week_of_year"])))
mp = os.path.join(OUT, "mi_lt_statewide_month_year.csv")
with open(mp, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["year","month_num","month","filings","source"])
    w.writeheader()
    for r in sorted(months, key=lambda r:(r["year"], r["month_num"])):
        w.writerow({"year":r["year"], "month_num":r["month_num"], "month":r["month"],
                    "filings":"" if r["filings"] is None else r["filings"],
                    "source":r["source"] or "unlabelled_in_source"})

lab = sum(1 for r in months if r["source"] == "chart_label")
der = sum(1 for r in months if r["source"] == "derived_from_annual_total")
mis = sum(1 for r in months if r["filings"] is None)
print(f"weekly : {len(weeks)} cells, {len({r['week_of_year'] for r in weeks})} weeks -> {wp}")
print(f"monthly: {len(months)} cells ({lab} from labels, {der} derived, {mis} unavailable) -> {mp}")
print("all validations passed")
