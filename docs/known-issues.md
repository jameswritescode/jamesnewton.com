# Known issues (upstream, monitored)

Issues in dependencies we can't fix in our own code, with why they're accepted
and what would resolve them.

## cowlib / hackney advisories (no in-range fix)

`mix hex.audit` reports `cowlib 2.19.0` (MEDIUM/LOW) and `hackney 1.25.0`
(HIGH/MEDIUM) with no patched releases available. Neither is exploitable in our
usage:

- **cowlib** is pulled by `plug_cowboy`, which only serves the private PromEx
  metrics port (9091, Fly private network — not publicly reachable).
- **hackney** is pulled by `tzdata`, which fetches timezone data from a fixed
  IANA host. The advisories (SOCKS5 timeout, SSRF allowlist bypass, CRLF
  injection) all require attacker-influenced URLs or request options, which
  that usage never exposes.

Re-check on any dependency work; bump when upstream ships fixes.
