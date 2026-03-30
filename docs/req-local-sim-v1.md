# Local Simulation — Bot Spawning Requirements

**Project:** Naval Game
**System:** Local Simulation Controller
**Engine:** Godot (GDScript)
**Date:** 2026-03-29
**Version:** 1.0

---

## 1. Purpose

This document specifies the local simulation mode for testing the naval combat prototype. It handles automatic spawning of a bot enemy for 1v1 duel testing without any multiplayer infrastructure.

**Dependencies:**
- `req-ai-naval-bot-v1.md` — bot controller and behavior tree
- `req-master-architecture.md` — ShipContext, controller architecture

---

## 2. Requirements

### 2.1 Core Behavior

When running in local simulation mode:

- Automatically spawn one bot enemy ship
- Place it at a reasonable duel opening distance
- Ensure it is not inside immediate ideal firing range
- Orient it toward a usable opening trajectory (not direct head-on)
- Attach `NavalBotController` and LimboAI behavior tree to the bot

### 2.2 Spawn Parameters

| Parameter | Default | Notes |
|-----------|---------|-------|
| `spawn_distance` | `220–320` units | Outside preferred engagement range |
| `spawn_bearing_offset` | `15–45` degrees | Not direct head-on |
| `local_sim_enabled` | `true` | Easy toggle on/off |

### 2.3 Suggested Spawn Logic

- Calculate spawn position as an offset from the player ship
- Randomize distance within the spawn range
- Apply bearing offset so the opening is not a pure head-on line
- Orient the bot ship toward a usable intercept trajectory

---

## 3. Isolation Requirement

Bot spawning logic must be isolated from future multiplayer logic.

### 3.1 Implementation

Create `LocalSimController.gd` (or equivalent scene/service) that:

- Is a standalone node or autoload
- Only runs when `local_sim_enabled` is true
- Does not assume or depend on networking code
- Can be disabled cleanly without affecting other systems

### 3.2 Recommended Architecture

```text
LocalSimController
├── spawns player ship (if not already present)
├── spawns bot ship at calculated position
├── attaches NavalBotController to bot
└── sets bot_enabled = true on the bot's blackboard
```

---

## 4. Tunable Parameters

All spawn values must be `@export` variables for in-editor tuning.

---

## 5. Out of Scope

- Multiplayer networking
- Multiple bot spawning
- Bot difficulty selection (future phase)
- Respawning after destruction
