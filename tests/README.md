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

The search remains backward Weighted A*: heuristic weights, route costs, successor
generation and minimum-cost pruning are unchanged. `settings.lua` and
`async_task.lua` are unchanged, including the default of 15 search steps per tick.

Map results are cached only until the next batch. The chosen route is checked
again against fresh map results before any pieces are placed. This final check
adds work at completion, but does not raise the search-step budget. As before,
placement of a completed route is performed together rather than spread over ticks.

These tests do not reproduce Factorio's native collisions, modded prototypes,
event interactions, or full fluid behavior. An in-game check is still needed
before treating the performance improvement as a measured Factorio speedup.
