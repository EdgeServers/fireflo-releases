# FireFlo releases

Built release artefacts for the FireFlo SMS Gateway, kept so that any version
ever handed to a customer can be recovered byte for byte and identified later.

FireFlo is commercial software, licensed per deployment, created and maintained
by [Remotiq](https://fireflo.au). Downloading a build from here grants no
licence to run it — see `LICENSE` inside the tarball. An unlicensed install
starts and carries traffic, but stops adopting configuration changes.

## Current

| | |
|---|---|
| **Version** | 0.8.7 |
| **File** | `fireflo-0.8.7-linux-x86_64.tar.gz` |
| **SHA-256** | `0d7c80564e5215a654fb684fb6fa10fbc6fb0f2ed7a587c8ed04660dbdba0d90` |
| **Built** | 2026-08-27, from gateway commit `2a02944` |
| **Platform** | linux-x86_64 — a native image, it will not run on another architecture |

Verify before installing:

```
sha256sum -c SHA256SUMS
```

**These tarballs are not signed.** A checksum detects a corrupted download and
nothing else: anyone able to replace the file can replace the checksum beside
it. Treat the checksum as an integrity check, not as proof of origin.

## Retired

`retired/` holds builds that must not be installed, with the reason beside each.
They are kept rather than deleted because a withdrawn build is sometimes the
only evidence of what went wrong. Read `retired/DO-NOT-SHIP.md` before touching
anything in there.

## Which signing key a build trusts

Each gateway binary has one Ed25519 public key compiled into it and accepts
licences signed only by the matching private key. That key is not configurable
at runtime, by design — an install that could be told which key to trust could
be told to trust a key its holder generated.

So the question "will this build accept our licences?" is answered by reading
the key out of the binary:

```
strings -a gateway/fireflo-gateway | grep -o 'MCowBQYDK2VwAyEA[A-Za-z0-9+/=]*'
```

0.8.7 answers `MCowBQYDK2VwAyEA7cEZKZae5xBb8uwIgvCmxBzW7ceOKl0YiFE1AburdAI=`.
That is a public value; publishing it is safe and is what makes a build
identifiable. A mismatch here presents as licences being rejected as MALFORMED,
which reads like a fault in the licence server rather than in the binary — the
reason it is worth checking directly.

## What is not here

The private signing key is **not in this repository and must never be**, in any
form, in any commit, including history. See `.gitignore`.

The control panel is a separate repository and ships as source; these tarballs
are gateway-only.
