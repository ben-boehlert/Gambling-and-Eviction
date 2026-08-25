# Legal Sports Report Handle and Revenue Snapshot

- Source: https://www.legalsportsreport.com/sports-betting/states/revenue/
- Retrieved and audited: 2026-08-14
- Source page last updated: 2026-07-06
- Grain: one row per state and calendar month
- Coverage: June 2018 through May 2026
- Rows: 2,270
- States: 35
- SHA-256: `d89df7b93828db8bf8b090a92876a856a76a5ec33f1266251a47fd1bfcb0290c`

The CSV is a direct normalization of the state-level monthly tables rendered on
the source page. Currency symbols and thousands separators were removed, Hold
was converted from displayed percentages to decimal rates, and `month_date` was
set to the first day of each reported month.

The source warns that the most recent months may be incomplete. At retrieval,
Arizona, Illinois, and Kentucky ended in April 2026; most other reporting states
ended in May 2026.

Historical revisions relative to the prior repository snapshot include 64
previously blank West Virginia Handle values, 23 earlier West Virginia months,
and a Rhode Island November 2020 Handle revision from $35,098,445 to
$177,643,128. Negative Revenue or Taxes and zero-Handle months are retained as
reported because they can reflect losses, adjustments, or market closures.

Run `Rscript scripts/audit_lsr_handle_data.R` after future refreshes. The audit
checks schema, State-by-month uniqueness, calendar continuity, Handle
completeness and validity, Month/date agreement, and displayed Hold consistency.
