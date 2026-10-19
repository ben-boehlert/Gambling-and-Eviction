# Maine FED report: the "June judicial year" explanation was wrong (2026-10-19)

Corrects the mechanism in [2026-09-17_maine-lsc-corruption-and-repair.md](2026-09-17_maine-lsc-corruption-and-repair.md)
and the 2026-09-17 header of `data_prep/add_me_to_state_panel.R`.

**What was said on 2026-09-17.** The Maine Judicial Branch "15-Year Monthly FED Filing Trends" PDF was said to
label June–December one year late because Maine's judicial year starts in June. The fix shifted June–December
back 12 months.

**What is actually going on.** The PDF has one page per calendar month, and each page is a rolling 15-year
window that the court updates only once that month has closed. So the pages do not share a year header. In the
copy with newest ref date 2026-09-18, the January–August pages run 2012–2026 and the September–December pages run
2011–2025. The old parser read every page with one header, which put the pages that had not yet been updated a
year late. In the older copy those pages happened to be June–December. Nothing about this is a judicial year.

**Was the old fix right?** For that copy, yes. On the 120 overlapping months the new per-page-header parse
matches the shifted series in 118 months, and the other two differ by 1 filing (a warehouse refresh). The panel
values from 2026-09-17 were correct. Only the explanation was wrong, and the fix cannot be reused: on the new copy
the boundary sits at September, so a June–December shift would mislabel September–December.

**What changed.** The new parser, `data_prep/monthly_panel_expansion/07c_parse_me_fed_monthly15yr.R`, reads each
page's own header and checks that counties and court locations sum to the Statewide row on every page.
`add_me_to_state_panel.R` now uses its output with no relabel. Maine runs to 2026-08 (+15 months). The panel goes
from 4,429 to 4,444 rows, and no non-ME row changes. This is a new vintage (see CLAUDE.md).
