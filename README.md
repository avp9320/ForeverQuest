# ForeverQuest

**A standalone, compact questing assistant for World of Warcraft: Forever.**

ForeverQuest plans what to pick up, which objective to do next, which tasks
overlap, when to turn in, and where to quest afterward. It keeps the interface
small: one two-line objective card, with optional hover details and a secure
quest-item button. Nothing is continuously posted to chat.

## Version 1.0 — core leveling assistant

### Entire quest database inside one addon

- Ships its own Classic/Forever source snapshot (4,244 quests in the pinned
  baseline, thousands of associated NPCs, objects and item sources).
- Works with an **empty quest log**: predicts nearby quest pickups instead
  of waiting for you to accept something first.
- Filters predicted pickups by race/class, level, completion, prerequisites,
  exclusions, redundant breadcrumbs and known skill/reputation/spell gates.
- Marks database-derived locations as **provisional**, not verified NPC offers.
- Native client waypoints and separately documented Forever corrections take
  priority over inherited Classic guesses.
- No Questie, QuestieDB, Internet access during gameplay, or other quest addon
  is needed. Install **only ForeverQuest**.

### Decisions and routing

- Combines possible pickups, active objectives and completed turn-ins into
  a five-stop *same-map* plan rather than just tracking the nearest quest.
- Understands separate enemy, object, collection and exploration objectives
  within a quest; completed steps stop taking route slots.
- Groups multiple possible quests at the same/nearby NPC into one stop.
- Prefers nearby overlapping tasks, chains with useful follow-ups, and
  practical turn-in opportunities while minimizing repeated backtracking.
- Treats level-inappropriate, group and elite quests more cautiously when
  playing alone; considers actual party size where available.
- Recognizes many prerequisite chain links, including reverse dependencies,
  optional prerequisites and direct follow-ups.
- Can suggest **connected next zones**, including a conservative two-zone
  transition when local opportunities run out. The handoff explains which
  neighboring zone to pass through, not a made-up road or travel time.
- Replans on quest/level/zone changes, periodically as you travel, with a
  short anti-flicker window. Combat does not cause random new pickup prompts.
- Understands three preferences: `fast`, `balanced` (default), `complete`.

### Built for the game, not another giant UI

- One draggable two-line quest card. Left-click / wheel cycles possible stops;
  right-click resumes AUTO.
- The displayed objective, direction and explicit waypoint follow the
  **selected individual target**, even when several tasks share a quest.
- Shift-left-click requests a Blizzard map waypoint; waypoints are not
  spammed onto the map automatically.
- A **small special quest-item button** appears when the native quest-log API
  reports a usable special item. It uses a secure action button and never
  changes protected attributes during combat.
- When an objective is on another map layer, the direct arrow is hidden
  rather than pretending it knows a cave entrance or indoor route.
- On hover, see suggested nearby stops, related active work, potential
  chain follow-ups, source confidence and transition cautions.

### Learns as you play

- Saves actually observed quest pickups and turn-in positions in account-level
  SavedVariables, so your next character can benefit.
- Learns a selected objective location when its live kill/collection progress
  advances. First readings establish a baseline; no fabricated coordinates.
- `/fq here` allows you to correct a specific objective location while
  standing where you found it.
- `/fq skip` hides an incorrect possible pickup for your character;
  `/fq avoid` tells AUTO to avoid an accepted quest.
- Stores observed flight-path names if the client exposes them when the taxi
  map opens. These are observations, not a claim every alt can fly there.
- No external telemetry or account data uploads.

## Install

Install or update **ForeverQuest** from the latest GitHub release ZIP through
WoWUp, or copy the *ForeverQuest* directory from the release ZIP into the
WoW: Forever `Interface/AddOns` folder. Do **not** use GitHub's generic
source-code ZIP: the generated `CatalogData.lua` is included in the
**built release**, not checked into the source tree.

**Only one addon folder is required.** No QuestieDB download is needed.

## Compact controls

- **Left click / mouse wheel** — cycle current planned actions.
- **Right click** — resume automatic route selection.
- **Shift + left click** — navigate to selected quest/pickup (explicit
  waypoint when available).
- **Hover** — explanation, related objectives and short route preview.
- **Quest-item icon** — use the relevant special quest item if supplied
  by WoW's quest log.

## Slash commands

- `/fq` — help.
- `/fq route` — print up to five approximate same-map stops and nearby tasks.
- `/fq why` — explain why AUTO chose this action.
- `/fq zones` — show connected zones with plausible quests and handoff notes.
- `/fq plan` — possible unaccepted pickups near the current location.
- `/fq mode fast` / `balanced` / `complete` — set a leveling preference.
- `/fq avoid` / `/fq unavoid` — avoid/restore accepted quests in AUTO.
- `/fq skip` / `/fq unskip` — dismiss/restore provisional pickups.
- `/fq here` — store current position as the selected objective location.
- `/fq knowledge` — show observed pickup, turn-in and objective counts;
  `/fq knowledge clear` resets account-observed positions.
- `/fq data` — check the bundled quest catalog status.
- `/fq report` — print a concise diagnostic for a bad recommendation.
- `/fq debug` — more detail about the active quest and client APIs.
- `/fq unlock`, `/fq lock`, `/fq reset` — move and reset the card.

## Data, accuracy and limits

**This is not a guarantee of a mathematically optimal 1–60 speedrun.**
WoW: Forever has changes that may not yet exist in the inherited Classic
quest facts. Group difficulty, unavailable NPCs, one-time event conditions,
quest rewards, phasing and some cave interiors may differ.

- Positions are approximate map-relative search areas unless the game itself
  provides a waypoint or your account has observed the location.
- Zone transitions are conservative adjacency suggestions, **not terrain
  pathfinding or timed flight/boat/zeppelin directions**.
- Quest items appear only if the current client exposes their special-item
  information; secure actions are restricted during combat.
- Unverified Classic/Forever records remain labeled. New confirmed Forever
  changes can be incorporated with regular ForeverQuest releases.
- Newly added races/classes or undocumented game APIs may require additional
  client-specific fixes.
- Code and the generated release have automated Lua 5.1, simulated-client,
  quest graph, catalog, security and ZIP integrity checks. **Real in-game
  testing is still required** to validate that the Forever client behaves as
  documented and to improve route quality.

Source and licensing details: [DATA_SOURCES.md](DATA_SOURCES.md).
The release ZIP contains relevant third-party attribution/license text.

## Development

Relevant tests:
`tests/route_spec.lua`, `tests/core_smoke.lua`,
`tests/catalog_smoke.lua`, `tests/roadmap_spec.lua`,
`tests/chains_spec.lua`.

The release workflow downloads a pinned, attributed source revision,
extracts a facts-only bundled dataset, runs tests and checks that the
installer contains just the **ForeverQuest** addon.
