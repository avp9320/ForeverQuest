# ForeverQuest

A compact smart quest focus and navigation addon for **WoW: Forever**.

ForeverQuest is built around one idea: **lots of quest information should be available, but very little of it should need to stay on your screen.**

## v0.4.0 — pickup + objective + turn-in route planning

This version introduces future-quest planning using the **optional QuestieDB-Forever data addon**. It does not require running the Questie quest tracker. Our own one-card UI remains unchanged.

### Future quest discovery

- Reads the QuestieDB public API for quests not yet accepted.
- Looks up quest starters (NPCs/objects) and spawn positions on the current map.
- Filters candidates by level, known completion, current quest log, race/class, and common quest-chain prerequisites.
- Suppresses uncertain reputation/profession/spell-gated quests rather than claiming eligibility.
- Checks the current zone in small batches to limit login lag.
- Uses a nearby possible pickup as a suggestion when no active objective is worth interrupting.
- Shows an estimated questgiver location and offers a waypoint on explicit Shift-click or \`/fq navigate\`.
- Lists up to five candidate pickups with \`/fq plan\`. All candidates are **provisional** until the live client confirms them.

### Location-backed route planning

- Plans up to five stops in your current map, combining accepted objectives, possible unaccepted quest pickups and completed quest turn-ins.
- Weighs distance, opportunistic pickups and objective clusters rather than chasing one quest-log entry.
- Reads QuestieDB NPC/object objective locations and known item drop sources as provisional search areas when Blizzard has no waypoint.
- Prioritizes native Forever map data and verified Forever-specific records over Classic-derived estimates.
- Hover on the compact card to see suggested next stops and possible follow-up quests.
- `/fq route` prints your next five approximate stops; `/fq navigate` sets an explicit waypoint to a selected estimated objective.
- `/fq skip` hides a wrong/unavailable pickup for the current character; `/fq unskip` restores your skipped pickup candidates.
- No persistent map pin clutter; user waypoints are only set on request.

These are **same-map map-coordinate estimates**, not walkable paths. The system cannot detect blocked terrain, precise mob spawn phases, or every Forever quest-giver requirement. It deliberately labels database pickup suggestions as possible, never guaranteed.

### Existing active-quest guidance



- A compact 258x46 two-line quest focus card: title and distance together, objective below
- A subtle, translucent tracker-like appearance (no heavy tooltip border or permanent AUTO label)
- An independently authored and sourced Valley of Trials quest-location starter database, including Forever's new Wayward Weapons quest; native Forever coordinates override Classic fallback estimates
- The tracker uses known *objective* map positions for recommendations, avoiding quest-log distance estimates that may actually point toward turn-in NPCs
- With a data-only fallback, the top-right label shows approximate map coordinates rather than pretending to know an exact yard distance
- Shift-click (or `/fq navigate`) sets an ordinary Blizzard map waypoint for a curated objective, if the game permits it
- Automatic nearest relevant *unfinished* quest selection, with a modest preference for quests whose map waypoints are clustered
- An optional `+N` badge when other unfinished quest objectives appear near the focused objective on the same map (estimated from live map pins/waypoints)
- Hover details explaining possible same-area quest tasks, plus the client's next-waypoint description when available
- Shift-left-click to make Blizzard navigate to the focused quest (never overrides the selected waypoint automatically)
- `/fq area` to list estimated co-located quests, or `/fq navigate` to use Blizzard's built-in quest tracking
- Same-zone quest preference
- Current objective/progress text
- Distance to the focused quest when the client exposes it
- Directional arrow when WoW: Forever provides a usable waypoint
- Unfinished-quest prioritization; turn-in-ready quests remain available manually and become AUTO's fallback after unfinished quests are exhausted
- Anti-thrashing logic so AUTO mode does not constantly bounce between similar quests
- Manual quest cycling with left click or mouse wheel
- Right click to return to AUTO mode
- Movable/lockable frame
- Debug output for testing Forever-specific API behavior

## Optional install for broad quest coverage

Install **[QuestieDB-Forever](https://github.com/Questie/QuestieDB/releases/latest)** alongside ForeverQuest (the `QuestieDB-Forever.zip` release asset), through WoWUp if available or by extracting the `QuestieDB` addon folder into WoW Forever's AddOns directory. You don't need the full Questie UI.

Without QuestieDB, the addon retains its active quest tracker and small independently curated quest-location fallback, but **future quest discovery is unavailable**. QuestieDB's Forever dataset contains Classic-derived assumptions and launch revisions, and may miss altered quests, blocked availability, or new spawns. Install and update the Forever-specific data release, not a Vanilla release.

This is a zone-by-zone multi-stop quest planner, **not** a fully verified 1–60 cross-zone leveling path. Full quest chain planning, objective clustering beyond the current quest log, multi-stop routing and turn-in optimization remain future work.

## Commands

- `/fq unlock` - unlock the focus card so it can be moved
- `/fq lock` - lock the card in place
- `/fq auto` - return to automatic quest selection
- `/fq route` - suggest a short multi-stop route across active quests and unaccepted pickups
- `/fq skip` - dismiss the currently suggested possible pickup for this character
- `/fq unskip` - restore all previously skipped possible pickups for this character
- `/fq plan` - list potential unaccepted nearby quests from QuestieDB
- `/fq data` - check future quest database coverage/status
- `/fq area` - list quests whose known objective points appear near your current focused objective
- `/fq navigate` - tell Blizzard to supertrack the current focused quest
- `/fq debug` - print useful quest/map/waypoint diagnostics
- `/fq reset` - reset the card position

## Install

Place the `ForeverQuest` folder in:

`World of Warcraft/_forever_/Interface/AddOns/`

The final layout should include:

`World of Warcraft/_forever_/Interface/AddOns/ForeverQuest/ForeverQuest.toc`

Restart WoW after installing a brand-new addon.

## Design direction

The current planner can look ahead to possible quest pickups using QuestieDB and resolve active objective positions with native waypoints or a small curated fallback. It cannot yet build a reliable multi-zone leveling itinerary, model all quest availability, or guarantee optimal pickup/turn-in decisions. Those are the highest-priority improvements. The goal is to gain the useful parts of large questing addons without turning the game screen into a questing dashboard.

## License / project policy

ForeverQuest is an independent implementation. It may take inspiration from useful UX patterns in existing quest addons, but it does not copy proprietary addon code or assets.
