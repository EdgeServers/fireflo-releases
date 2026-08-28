# 0.8.8 — superseded by 0.8.9. Works correctly; do not ship to new customers.

Retired 2026-08-28, the day after it was built.

## This is not 0.8.6

`DO-NOT-SHIP.md` next to this file describes a build that is **broken** — it
rejects every licence the server issues. Nothing of the sort is wrong here.

0.8.8 sends messages, verifies licences, and activates against
`verify.fireflo.au`. An install already running it is fine and is not at risk.
It is retired because 0.8.9 can do two things it cannot, and because it tells
operators one thing that is not true.

## Why it is superseded

**It cannot release a licence.** A machine being rebuilt, or replaced, or moved
to different hardware has no way to give up the licence it holds. Releasing on
the licence server alone does not free the machine: verification is offline
against a signature already on disk, so the old box keeps working — and keeps
adopting configuration — until that signature lapses, up to the 21-day
tolerance. 0.8.9 adds the local half: `POST /ops/license/release`, the Licence
page in the control panel, and `fireflo license release` for a box that is
stopped.

**It prints a false sentence.** `fireflo license activate` and
`fireflo license offline` both end by saying the running gateway picks the
licence up on its next configuration poll and needs no restart. It does not.
The licence store reads its file at startup and at no other time, and a running
process *writes* that file from the copy it already holds — so an offline
activation performed against a live gateway can be silently overwritten, and the
operator has been told it took effect. 0.8.9 says to restart, which is the
truth.

## What this means in practice

- **Do not hand 0.8.8 to a new customer.** They would receive an install that
  cannot be transferred to another machine without waiting out the tolerance
  window, and a CLI that misreports what an offline activation did.
- **Existing 0.8.8 installs are not broken and need no emergency upgrade.**
  Upgrade at the next convenient window; there is no data or licensing state to
  migrate.
- If you must move a licence off a 0.8.8 box before upgrading it, release it on
  the licence server, stop the gateway, and delete `license.json` from its data
  directory by hand — that is what `fireflo license release` automates, with the
  interlock and the verification that the write landed.

## Why it is kept rather than deleted

It is the first build on which network activation worked at all — 0.8.7 and
everything before it could not build the request under a native image — so it is
the artefact that dates that fix if a question about it ever arises.

## What to use instead

    ../fireflo-0.8.9-linux-x86_64.tar.gz
