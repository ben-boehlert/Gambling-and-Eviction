# Public-repo cleanup before pushing `power-cs-arm-and-shift-mode` (2026-10-19)

**Status:** APPROVED by Ben 2026-10-19 (answers: ETS extract local only; papers and docs local only;
rewrite the unpushed commits; tidy the root folder).

## Why
The branch is 100 commits ahead of `origin/main`, and `origin` is a **public** GitHub repo. A push
would publish 2,907 new files, including:
- `data/raw/ny_oca/oca_index.csv`: 494 MB, over GitHub's 100 MB limit. It is the Housing Data
  Coalition's public NYC housing-court case index (`oca-2-dev.s3.amazonaws.com/public/oca_index.csv`),
  one row per case, with no names or addresses. No script reads it.
- `ets_county_month.csv`: the Eviction Lab internal county-month extract (unreleased).
- copyrighted papers (`Literature/`, root PDFs) and the grant/PAP Word drafts.
- compiled `.o` binaries, `.claude/worktrees/` copies, `tmp/`.

## Approach
1. Make a backup: branch `backup/pre-public-cleanup-2026-10-19` plus a git bundle in the scratchpad.
2. In a scratch clone, run `git filter-repo --refs origin/main..power-cs-arm-and-shift-mode` with the
   path list below, so `origin/main` is untouched. Then fetch the result back and `git reset --mixed`
   the branch onto it. That only moves the index, so the working tree and other sessions'
   uncommitted edits stay as they are, and every stripped file stays on disk.
3. Add `.gitignore` rules for everything stripped, so it can't be re-added by accident.
4. Tidy the root folder (moves recorded in MOVES.md, script paths checked).
5. Verify: no stripped path anywhere in `origin/main..HEAD`; no blob over 50 MB; scripts that read
   moved files still resolve them; re-list the push for Ben. **No push without his OK.**

## Paths stripped from the unpushed history (kept on disk, gitignored)
`data/raw/ny_oca/`, `ets_county_month.csv`, `Literature/`, `.claude/worktrees/`, `tmp/`, `*.o`, `*.so`,
`Arnold Housing Loss Gambling - Application.docx`, `preanalysis plan v1.docx`,
`preanalysis plan v1.1.docx`, `model gambling.docx`, `AV_Pre-Analysis_Plan_Guidance_202507.pdf`,
`Robust Signal Maximization in Spillover Experiments.pdf`, root `monthly_county_data_download.csv`
(a stale copy of the 2026-09-17 bulk download; scripts read `data/raw/`).

## Root tidy
- Grant/PAP drafts, AV guidance, `LP DiD Justification.docx`, `CO Court Website.png` → `private/` (gitignored)
- Root papers (untracked) → `Literature/` (gitignored); `Literature/INDEX.md` (tracked) lists the citations
- `WI/` (byte-identical copies of `data/raw/monthly_expansion/wi_raw/pdfs/`), `Rplots.pdf`, root
  `2018/2019CasesFiled.pdf` (copies of the OR raw PDFs), the 9_17 LSC bulk CSVs → `deprecated/`
- `Table-of-Contents-for-Web-2025.pdf` (Kansas Courts FY2025 annual report) → `data/raw/kansas/`
- `lt-writ-data-2014-2019-by-circuit_0.pdf` → `data/raw/new_hampshire/`
- `County.csv` (NJ county map export), `JusticeCivil_1336701014.csv` (TX JP civil export) → `data/raw/misc/`
- `County Court Data Methodology Report.md` → `docs/`, with references updated
- `ets_county_month.csv` stays at the root (seven build scripts read that path), untracked
