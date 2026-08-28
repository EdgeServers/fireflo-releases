# 0.8.6 — unusable. Do not install, do not distribute.

Retired 2026-08-27.

## What is wrong with it

The gateway binary in this tarball has the wrong Ed25519 public key compiled
into it:

    embedded in 0.8.6   MCowBQYDK2VwAyEA8t0hyIYwia+4/nuumzNgLmpD7EbjQYaBCfHmbAT+wLE=
    signed with today   MCowBQYDK2VwAyEA7cEZKZae5xBb8uwIgvCmxBzW7ceOKl0YiFE1AburdAI=

Both values are public keys and are safe to publish; that is what makes them
useful for identifying a build.

No private key corresponds to the first value. So this build **rejects every
licence the licence server issues**, as MALFORMED.

The trap worth naming is the symptom rather than the cause: it presents as a
licensing fault on the server side, so anyone debugging it starts in the wrong
repository. The cheap test is to read the key out of the binary —

    strings -a gateway/fireflo-gateway | grep -o 'MCowBQYDK2VwAyEA[A-Za-z0-9+/=]*'

— and compare it against the key the server signs with.

## Why it is kept rather than deleted

It is the only artefact recording what the superseded key looked like. If a
licence ever appears that this build accepts, that licence was signed by
something outside our control, and this binary is the evidence needed to
demonstrate it.

Keep. Never install.

## What to use instead

    ../fireflo-0.8.8-linux-x86_64.tar.gz

Carries the corrected key — first shipped in 0.8.7, from gateway commit
2a02944 — verified the same way, by extracting the key from the packaged binary
rather than by reading the source, because the source being right does not prove
the artefact is.

0.8.7 itself is now beside this file, retired for an unrelated and much less
serious reason. See `SUPERSEDED-0.8.7.md`: it works, and is retired on licensing
policy rather than on a fault.
