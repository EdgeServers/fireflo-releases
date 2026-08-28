# 0.8.7 — superseded by 0.8.8. Works correctly; do not ship to new customers.

Retired 2026-08-27, the same day it was built.

## This is not 0.8.6

`DO-NOT-SHIP.md` next to this file describes a build that is **broken** — it
rejects every licence the server issues. Nothing of the sort is wrong here.

0.8.7 sends messages, verifies licences, and activates against
`verify.fireflo.au` correctly. An install already running it is fine and does
not need to be touched urgently. It is retired for a **licensing policy**
reason, not a functional one, and the two should not be conflated when reading
this directory.

## Why it is superseded

A fresh 0.8.7 install grants **itself** a 14-day setup window, writing the
anchor into `license.json` and the `app_license` table — both of which the
customer owns and can edit. That makes the trial a delay rather than a limit:

    DELETE FROM app_license;  +  rm license.json      -> another 14 days
    UPDATE app_license SET first_seen_at = NULL;      -> an UNLIMITED window

The second is the worse of the two. A null anchor was read as *inside the setup
window* rather than as *no anchor at all*, so clearing one column granted an
unbounded window while the countdown still displayed the full 14 days. Neither
reset costs the customer anything: configuration, call records and prepaid
balance all survive.

0.8.8 inverts that null case and stops stamping the anchor, so a new install has
no window to reset and asks the licence server instead.

## What this means in practice

- **Do not hand 0.8.7 to a new customer.** They would receive an install that
  can renew its own trial indefinitely.
- **Existing 0.8.7 installs keep their remaining days** under 0.8.8 and are
  never granted another. Upgrading does not freeze them — that compatibility
  case is deliberate and tested.

## Why it is kept rather than deleted

It is the last build carrying the self-granted window, so it is the artefact to
reach for if a question ever arises about how a particular install obtained the
window it has.

## What to use instead

    ../fireflo-0.8.8-linux-x86_64.tar.gz
