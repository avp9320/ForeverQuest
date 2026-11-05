# ForeverQuest

A compact smart quest focus and navigation addon for **WoW: Forever**.

ForeverQuest is built around one idea: **lots of quest information should be available, but very little of it should need to stay on your screen.**

## v0.6.0 — individual-objective planning and clearer route decisions

**ForeverQuest is now a standalone addon.** The release ZIP includes its own Classic + Forever quest catalog: 4,244 quests and thousands of quest-related NPCs, objects and item-drop references from a pinned factual snapshot. You do **not** need Questie, QuestieDB, or any other quest addon installed.

### Future quest discovery

- Uses the built-in quest catalog for quests not yet accepted.
- Looks up quest starters (NPCs/objects) and spawn positions on the current map.
- Filters candidates by level, known completion, current quest log, race/class, and common quest-chain prerequisites.
- Suppresses uncertain reputation/profession/spell-gated quests rather than claiming eligibility.
- Checks the current zone in small batches to limit login lag.
- Uses a nearby possible pickup as a suggestion when no active objective is worth interrupting.
- Shows an estimated questgiver location and offers a waypoint on explicit Shift-click or \`/fq navigate\`.
- Lists up to five candidate pickups with \`/fq plan\`. All candidates are **provisional** until the live client confirms them.

### Better decisions inside individual quests

- A quest with several unfinished targets now yields distinct route goals for its NPCs, interactable objects, and item collection sources.
- Completing a target removes it from planned destinations when the live quest log confirms completion.
- The compact card shows **the chosen target's progress**, and the directional arrow and explicit waypoint follow that same target instead of always pointing to the quest's first objective.
- Manual cycling can select a different objective within the same quest. Its goal identity remains stable as progress changes; right-click restores AUTO.
- Distant *unconfirmed* quest pickups won't derail a nearby active quest. Possible pickups are recommended if nearby, along accepted objectives, or when the quest log has no known local work.
- Exploration quests with documented location triggers now have a fallback search area when there's no unfinished kill/collection goal. Locations remain provisional.
- `/fq route` identifies nearby overlapping tasks, and `/fq why` explains the current automatic recommendation and its location confidence.

### Location-backed route planning

- Plans up to five stops in your current map, combining accepted objectives, possible unaccepted quest pickups and completed quest turn-ins.
- Weighs distance, opportunistic pickups and objective clusters rather than chasing one quest-log entry.
- Reads packaged NPC/object objective locations and known item drop sources as provisional search areas when Blizzard has no waypoint.
- Prioritizes native Forever map data and verified Forever-specific records over Classic-derived estimates.
- Hover on the compact card to see suggested next stops and possible follow-up quests.
- Left-click or mouse wheel cycles the **planned stops**, including future quest pickups even when your quest log is empty; right-click resumes AUTO.
- During combat the current objective holds steady rather than switching you to a new quest giver.
- When quest-log objective names match the database target, finished enemies/collection steps are filtered out.
- `/fq route` prints your next five approximate stops; `/fq navigate` sets an explicit waypoint to a selected estimated objective.
- `/fq skip` hides a wrong/unavailable pickup for the current character; `/fq unskip` restores your skipped pickup candidates.
- No persistent map pin clutter; user waypoints are only set on request.
- If there are no useful same-map stops, the compact card can suggest a **neighboring zone** with plausible quest starters rather than just saying your quest log is empty.
- `/fq zones` shows nearby potential leveling zones and approximate counts of eligible quests. It is explicitly **not** a travel route; availability is provisional.
- Starter suggestions now check recorded NPC friendliness against your faction and skip event-gated quests when the client cannot verify the event.


GitHub Actions validates every release using Lua 5.1 syntax, route and data-provider tests, a real bundled-catalog integration test, a mocked-client UI smoke test, and ZIP contents checks. These are not substitutes for live WoW verification.

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

## Standalone installation and data maintenance

Just install **ForeverQuest**. No separate addon or downloaded database is required. The release ZIP contains `CatalogData.lua` and `CatalogRuntime.lua`, plus our planner, small quest card, and waypoint integration.

The catalog is generated at build time from a pinned Classic/Forever source revision. It includes quest levels, prerequisite links, starter and turn-in entities, objective references, approximate sampled spawn positions, and location triggers for exploration quests. Guide prose is not distributed. See [DATA_SOURCES.md](DATA_SOURCES.md) for provenance and licensing.

Classic facts remain **provisional** until verified in Forever. Each future release can refresh the bundled catalog with documented Forever updates. No network access is needed while playing, and no addon-to-addon dependency exists.

This is still a same-map, multi-stop planner, not a validated 1–60 cross-zone leveling guide or navigable-road router. Live quest availability, mob spawn conditions, and terrain may differ from database assumptions.

## Commands

- `/fq unlock` - unlock the focus card so it can be moved
- `/fq lock` - lock the card in place
- `/fq auto` - return to automatic quest selection
- `/fq route` - suggest a short multi-stop route across active quests and unaccepted pickups
- `/fq why` - explain the currently recommended stop and how confident its location is
- `/fq zones` - inspect possible quests in neighboring leveling zones
- `/fq skip` - dismiss the currently suggested possible pickup for this character
- `/fq unskip` - restore all previously skipped possible pickups for this character
- `/fq plan` - list potential unaccepted nearby quests from ForeverQuest's built-in catalog
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

The current planner looks ahead to possible quest pickups using its embedded Classic/Forever catalog and resolves active objective positions with native waypoints, curated Forever corrections, or approximate database coordinates. It cannot yet build a reliable multi-zone leveling itinerary, model all quest availability, or guarantee optimal pickup/turn-in decisions. Those are the highest-priority improvements. The goal is to gain the useful parts of large questing addons without turning the game screen into a questing dashboard.

## Source and licensing

ForeverQuest's independent planning and UI code does not copy Questie/QuestieDB addon code, artwork or guide prose. The embedded factual dataset is derived from the Forever source snapshot and includes third-party acknowledgments and licensing text in the release ZIP. See [DATA_SOURCES.md](DATA_SOURCES.md).
