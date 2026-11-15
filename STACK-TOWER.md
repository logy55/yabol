# Stack Tower

The Tools menu replaces Rummikub with Stack Tower (`#/tools/stack`). Retired game data and source are retained for recovery; the current router and member records no longer expose Rummikub.

## Build and source

`npm ci && npm run build:stack`

The Apache-2.0 core/view modules from [DevCol Stack Up](https://github.com/devcol-main/Stack-Up/tree/797f004667e448d4d09d2695fa1734098b233c18) are vendored in `src/stack-up`. Imports are flattened; the renderer uses a navy palette. The original logo, fonts, analytics and online services are not included. The browser distribution includes `stack-LICENSE.txt` and `stack-NOTICE.txt`.

`dist/stack-tower.js` supplies the site's own launch page, responsive modal, keyboard/pointer controls, pause lifecycle, sound effects and member rankings. Fixed 120 Hz movement is separate from painting. Pixel ratio is capped at 2; cached glow sprites and bounded effect pools avoid per-frame blur. Hidden tabs and loss of window focus pause both game and clock.

## Rules and ranking

Click, tap or press Space to place a block. Overhang is removed; no overlap ends the run. Each floor earns 1 point. A perfect placement adds the current perfect streak (maximum 5 bonus points). Five consecutive perfect placements restore 8% of the initial width, capped at the starting width.

Migration `058_stack_tower.sql` adds approved-member-only begin, complete and ranking functions. Completion saves the current snapshot immediately, using lightweight consistency checks rather than a replay simulation. Retries use the same run ID and are idempotent. Each member's best score for the current KST month enters TOP 30; ties use shorter active play time, then earlier achievement time. A KST month boundary hides old entries immediately and scheduled maintenance removes prior-month records. Migration `059_stack_hall_of_fame.sql` also connects Stack Tower to the existing monthly top-three podium and all-time record archive. The category starts in November 2026; earlier finalized months keep their original four categories. A before-change trigger freezes the old month before a new-month best or cleanup replaces its rows. Existing games and their archived entries are preserved.

The marble lobby heading includes its eyebrow and final classes in the initial synchronous markup, before the room list request, so loading no longer inserts a second heading row later.
