# Pre-PASPA gambling institutions — provenance

**Compiled:** 2026-08-21, in-session, from the sources below.
**Status:** SECONDARY-SOURCE COMPILATION. Adequate for a predictor block in a
50-observation diagnostic. **Not** adequate for a published table without
independent verification against primary statutes / regulator records.

## Lottery adoption year

Primary source used: LotteryUSA, "History of the lottery: First offerings by
state", https://www.lotteryusa.com/news/history-lottery-first-offerings-by-state
(retrieved 2026-08-21). Gives first-offering year for all 45 lottery states.

Non-lottery states per the same source: **AL, AK, HI, NV, UT** (5). This matches
the conventionally reported count of five states without a lottery, which is the
one internal consistency check available without a second full table.

**Correction applied:** the source only *implied* a DC year (1987, via a
Multi-State Lottery Association reference). DC is coded **1982**, verified
separately: the DC Council authorized the lottery in 1982 and the first game
("Match 3") went on sale 25 August 1982
(https://en.wikipedia.org/wiki/D.C._Lottery, https://dclottery.com, retrieved
2026-08-21).

## Commercial (non-tribal) casino authorization

Primary source used: I. Nelson Rose, "Pivotal Dates", Gambling and the Law,
https://www.gamblingandthelaw.com/article/pivotal-dates/ (retrieved 2026-08-21).
Corroborated on individual states by search results citing the Iowa Racing and
Gaming Commission, the South Dakota Commission on Gaming, Colorado LegiSource,
and UPI's 1991 report of the Louisiana legislature's riverboat approval.

Timeline used: NV re-legalized 1931; NJ voters 1976, Resorts International
opened 1978; SD Deadwood approved Nov 1988, opened Nov 1989; IA riverboats
opened April 1991; IL riverboats opened 1991; CO mountain-town casinos opened
1991; MS riverboat/dockside launched 1992 (statute 1990); LA legislature
approved riverboats July 1991, casinos opened 1993.

Two codings are carried because "legalized" is genuinely ambiguous here:

- `casino_op_by_1991`   — commercial casinos **operating** by 31 Dec 1991:
                          NV NJ SD IA IL CO (6)
- `casino_auth_by_1991` — commercial casinos **authorized** by statute or
                          referendum by 31 Dec 1991: adds MS, LA (8)

`casino_auth_by_1991` is the primary measure: authorization is the legislative
act, and the hypothesis is that a legislature which has already authorized
casino gambling is quicker to authorize sports betting.

## Deliberately NOT coded

A "commercial casinos as of 2017" indicator was attempted and **abandoned**. The
AGA reports 24 commercial-casino states as of 2017 but the list was not
retrievable, and a Wikipedia casino-list extraction returned Alabama as having
commercial casinos, which is wrong. A variable that cannot be verified is worse
than a missing variable.

Tribal gaming is not coded here. IGRA passed in 1988, so a pre-PASPA tribal
measure is possible in principle, but it needs NIGC/BIA compact records rather
than a secondary compilation, and tribal exclusivity can *block* commercial
expansion — the sign is not obvious, so a badly measured version is actively
misleading.
