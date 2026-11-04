# ForeverQuest

A compact smart quest focus and navigation addon for **WoW: Forever**.

ForeverQuest is built around one idea: **lots of quest information should be available, but very little of it should need to stay on your screen.**

## v0.2.1

The first playable version provides:

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

## Commands

- `/fq unlock` - unlock the focus card so it can be moved
- `/fq lock` - lock the card in place
- `/fq auto` - return to automatic quest selection
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

The first pass of overlapping *areas* uses live client waypoints when available, then a small separately sourced Classic/Forever starter database; this is not full quest coverage. A contextual quest-item button, full map pickup/turn-in guidance, learned Forever-specific quest data, and improved route planning are still to be built. The goal is to gain the useful parts of large questing addons without turning the game screen into a questing dashboard.

## License / project policy

ForeverQuest is an independent implementation. It may take inspiration from useful UX patterns in existing quest addons, but it does not copy proprietary addon code or assets.
