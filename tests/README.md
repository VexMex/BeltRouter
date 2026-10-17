# Lua regression tests

Run from the repository root with Lua 5.2:

```sh
lua tests/run.lua
```

No Factorio installation or third-party Lua packages are required for this suite.
The tests run the actual routing modules with small stand-ins for game objects.

Coverage includes:

- Independent vectors and all eight compass directions.
- Position caches, including `nil`, `false`, fractional coordinates and isolated queries.
- Reused prototype descriptions and skipped disabled debug formatting.
- Quarter turns, U-turns, and the threshold for checking route self-collisions.
- Pump/splitter footprints and parallel versus crossing underground belts.
- The existing 15-step search batch limit.
- Final validation after obstacles or interfering belts are added between batches.
- Endpoint deletion/rotation, four-direction belt routes, pipes and underground routing.
- The real `control.lua` entry point: input handlers, start selection and ghost placement.
- Existing building, belt and pipe ghosts, with Force Build on and off.
- Large building footprints, rotated planned pumps and underground endpoints.
- Ghost start/destination selections and blueprints added during search or build events.
- Tile ghost preservation, cheat-mode placement and failed entity creation.

The search remains backward Weighted A*: heuristic weights, route costs, successor
generation and minimum-cost pruning are unchanged. `settings.lua` and
`async_task.lua` are unchanged, including the default of 15 search steps per tick.

Map results are cached only until the next batch. The chosen route is checked
again against fresh map results before any pieces are placed. This final check
adds work at completion, but does not raise the search-step budget. As before,
placement of a completed route is performed together rather than spread over ticks.

Ghost-protection cases in `tests/ghost_protection.lua` simulate overlapping rectangular
footprints, ghost deletion on deconstruction, and callbacks from other mods.
They deliberately allow the ordinary placement check to accept occupied ghost tiles,
so the explicit protection must work independently of Force Build.

These tests do not reproduce Factorio's native collisions, modded prototypes,
event interactions, or full fluid behavior. An in-game check is still needed
before treating the performance improvement as a measured Factorio speedup.
