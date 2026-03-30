# Naval Combat Prototype — Weapons Layer Requirements (v1.0)

## Intent

Shots are deliberate, readable, and earned through positioning, not spam or luck.

## Core Rules

- Projectile travel is always visible (no hitscan).
- Broadside alignment gates firing quality.
- Misses are understandable (distance, motion, angle).
- Stable, well-aligned broadsides at optimal range are reliable.

## Projectile Model

- Speed: target default **55 world units/sec**.
- Lifetime: target default **4.5s**.
- Max distance: roughly 300-400 units.
- Gravity: light arc.

## Accuracy Model

- No damage falloff; hit = full effect, miss = zero.
- Deterministic spread cone by distance:
  - <100u: +/-2-4 deg
  - 100-200u: +/-5-8 deg
  - max range: +/-10-15 deg
- Movement penalties:
  - shooter turning: +30-50% spread
  - shooter high speed: +25% spread

## Fire Modes

- Keep both Salvo and Ripple.
- Default cannons per side: 8 (acceptable range 6-12).
- Ripple interval: 0.3s.
- Full ripple duration: 2-4s.
- Fire is committed once sequence starts.

## Feedback Requirements

- Muzzle flash (0.1-0.2s).
- Muzzle smoke (1-3s).
- Cannonball trail.
- Water splash on miss (1-2s).
- Hull impact burst on hit.
- Audio: cannon boom, impact cue, optional near-miss whiz.

## Timing Targets

- Reload: target default **18s**.
- Projectile travel: 1-2.5s typical.
- Turn-to-align: 5-10s.
- Screen cross: ~15s.
- Engagement duration: 25-40s.
- Reaction window: 3-5s.

