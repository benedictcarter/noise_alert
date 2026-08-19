# Lessons Learnt

Non-obvious gotchas hit while building noise_alert. Append as they happen — mechanism first, then the
incident that taught it.

## Flightradar24 has no free tier — do not design around it (2026-08-19)
**Mechanism:** the FR24 API is an enterprise, quote-based product gated behind sales; there is no
self-serve key. Designing the matcher against it would have stalled the project at the first API call.
**What to use instead:** live community ADS-B (`adsb.lol`, `airplanes.live` — free, no key, ~1 req/s)
queried *at the moment of the snap*, with OpenSky (free, OAuth2 client-credentials, 4,000 credits/day)
as the fallback. OpenSky is the only free source that serves **historical** data, and only for the
last **1 hour** — which is exactly why the offline back-fill window is one hour and not one day.

## Sound arrives late, so "the plane at time T" is the wrong query (2026-08-19)
**Mechanism:** sound travels ~343 m/s. An aircraft at 3,000 ft slant range was overhead ~2.7 s before
you heard it; at 10,000 ft, ~9 s. Add human reaction time to press the button and the true overhead
moment can be 20–40 s before the timestamp. Querying the instantaneous position at T will regularly
name the wrong aircraft — and a complaint naming the wrong airline is worse than one naming none.
**Rule:** search T−45 s to T+10 s and score by closest approach, not by position at T.
