# NY OCA housing-court case index (local only, not in git)

`oca_index.csv` (493.6 MB, 2,268,452 cases) is the Housing Data Coalition's public NYC housing-court
case index, built from NY Office of Court Administration (OCA) records:
https://oca-2-dev.s3.amazonaws.com/public/oca_index.csv (saved here 2026-04-15).

One row per case. Columns: `indexnumberid, court, fileddate, propertytype, classification,
specialtydesignationtypes, status, disposeddate, disposedreason, firstpaper, primaryclaimtotal,
dateofjurydemand`. It has no party names and no addresses.

**Why it is not committed:** it is case-level, it is over GitHub's 100 MB file limit, and no script in
this repo reads it. It was removed from the unpushed history on 2026-10-19. To get it again:

```bash
curl -L -o data/raw/ny_oca/oca_index.csv https://oca-2-dev.s3.amazonaws.com/public/oca_index.csv
```

For NY state-month filings, the NY OCA "Statewide Eviction Information" dashboard is the intended
source (see docs/DATA_PROVENANCE.md).
