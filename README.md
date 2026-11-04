# ForeverQuest

A compact smart quest focus and navigation addon for **WoW: Forever**.

ForeverQuest is built around one idea: **lots of quest information should be available, but very little of it should need to stay on your screen.**

## v0.1.4

The first playable version provides:

- A compact 258x46 two-line quest focus card: title and distance together, objective below
- A subtle, translucent tracker-like appearance (no heavy tooltip border or permanent AUTO label)
- Automatic nearby quest selection
- Same-zone quest preference
- Current objective/progress text
- Distance to the focused quest when the client exposes it
- Directional arrow when WoW: Forever provides a usable waypoint
- Completed-quest/turn-in prioritization
- Anti-thrashing logic so AUTO mode does not constantly bounce between similar quests
- Manual quest cycling with left click or mouse wheel
- Right click to return to AUTO mode
- Movable/lockable frame
- Debug output for testing Forever-specific API behavior

## Commands

- `/fq unlock` - unlock the focus card so it can be moved
- `/fq lock` - lock the card in place
- `/fq auto` - return to automatic quest selection
- `/fq debug` - print useful quest/map/waypoint diagnostics
- `/fq reset` - reset the card position

## Install

Place the `ForeverQuest` folder in:

`World of Warcraft/_forever_/Interface/AddOns/`

The final layout should include:

`World of Warcraft/_forever_/Interface/AddOns/ForeverQuest/ForeverQuest.toc`

Restart WoW after installing a brand-new addon.

## Design direction

Planned additions include overlapping-objective detection, a contextual quest-item button, map integration, learned Forever-specific quest data, and smarter next-objective suggestions. The goal is to gain the useful parts of large questing addons without turning the game screen into a questing dashboard.

## License / project policy

ForeverQuest is an independent implementation. It may take inspiration from useful UX patterns in existing quest addons, but it does not copy proprietary addon code or assets.
