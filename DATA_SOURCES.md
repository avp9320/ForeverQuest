# ForeverQuest bundled quest data — provenance and licensing

ForeverQuest now ships **one self-contained addon**. No Questie or QuestieDB runtime addon is required.

The generated `CatalogData.lua` in release ZIPs is a *facts-only* snapshot
(quest and entity IDs, names, level/eligibility prerequisites, objective
references, approximate sampled coordinates) derived at build time from
[QuestieDB's World of Warcraft: Forever source data](https://github.com/Questie/QuestieDB)
and its Forever AreaID→UiMapID reference. It does not redistribute
QuestieDB's addon runtime or Questie UI, quest-description prose, quest guide
instructions, images, or exact full spawn point arrays.

Source revision (pinned, not a moving branch):

- QuestieDB **v1.0.10**, commit
  `a37877c1490027ee48e5722bf602adf34f95a6dc`
- Fields extracted from:
  `data/Forever/foreverQuestDB.lua`,
  `foreverNpcDB.lua`, `foreverObjectDB.lua`, `foreverItemDB.lua`,
  `support/Forever/Zones/areaIdToUiMapId.lua`.
- Reproducible generator: `tools/build_catalog.lua` in this repository.
- ForeverQuest's own `QuestData.lua` can override provisional Classic
  guesses with better documented Forever-specific locations.

**Acknowledgment / licensing:** QuestieDB's root `LICENSE.md` describes
historic author permissions and complexities, and a GPLv3 licensing effort.
That provenance matters: names and factual positions are not the authors'
original guide prose, but contributors still deserve acknowledgment.
The release includes the upstream `LICENSE.md` and `gpl-3.0.md`.
See the source revision and original contributors for full details. Where
QuestieDB material is copyright-protected, distribution of the derived
material is intended under GPLv3 terms, subject to the upstream license notes.
ForeverQuest's independent UI/planner code is also published in source form
in this public repository.

The snapshot is a launch **baseline**, not proof that every quest or spawn
has the same availability on Forever. Names, prerequisites and sampled
coordinates can be incomplete, obsolete or wrong. The game client's native
quest log/waypoints take precedence, then separately verified Forever data,
then this catalog. `/fq skip` hides an incorrect pickup candidate, while
`/fq unskip` restores it.

This catalog is refreshed only with a new ForeverQuest build/release;
addons cannot fetch remote files while the game is running.


## Authored pickup landmark additions in v1.0.1

- **Quest 791, Carry Your Weight**: Furl Scornbrow (NPC 3147), the Razor Hill watchtower's upper level, Durotar ~49.9, 40.4. This is a location published for the Forever game by [Bind on Forever](https://bindonforever.com/quest/791) and cross-checked against [Questing.wiki's data record](https://questing.wiki/wow-forever/quests/791/). No source guide prose or route instructions are copied. Still a *published waypoint*, not a quest pickup directly observed by ForeverQuest on this account.

Positions are approximate destination points; buildings may have upper/lower floors. Actual acceptance remains determined by the game.
