# BeltRouter Lite

Current version: **3.0.0**.

Factorio mod for automatically routing belts and pipes. Imported version: **2.7.0**, for Factorio **2.0**. The mod's original name, attribution and images are preserved. English comments explain the Lua files for readers new to the project. The routing implementation includes allocation and caching improvements while keeping the backward Weighted A* search and its existing settings.

## Origin and license

Extracted on 2026-10-14 from [PlexPt/small-factorio-mods](https://github.com/PlexPt/small-factorio-mods), branch `main`, directory [BeltRouter-lite](https://github.com/PlexPt/small-factorio-mods/tree/5c22602665f0bda74461f425b607a70291764a37/BeltRouter-lite), at source commit `5c22602665f0bda74461f425b607a70291764a37`.

Only this directory's contents were moved into the repository root. The source repository was not modified. This is an independent repository, rather than a GitHub fork of the complete collection.

The source repository supplies the [GNU GPL version 3](https://github.com/PlexPt/small-factorio-mods/blob/5c22602665f0bda74461f425b607a70291764a37/LICENSE). The existing GPL-3.0 `LICENSE` in this repository was retained unchanged. Original authorship notices remain in the files. The imported history identifies **plexpt**, the mod metadata identifies **pt**, and numerous files credit **seancheey**. The original homepage is [Seancheey/FactorioBeltRouter](https://github.com/Seancheey/FactorioBeltRouter). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the linked-list library's MIT notice.

## History extraction

The five commits affecting this directory on `main` were extracted with `git filter-repo --subdirectory-filter BeltRouter-lite` (git-filter-repo 2.47.0). Unrelated files and commits were excluded. Moving paths changes Git commit IDs.

Because local authenticated Git push was unavailable, these five filtered snapshots were reconstructed through the GitHub plugin, retaining their order, messages and file bytes. Original commit IDs, author and committer identities, and original dates are recorded in each import commit; the author is also credited as a co-author. GitHub's reconstructed commit author/committer timestamps differ from the originals. The existing target commit `7d0490e0e358c20ada03240a592f097655ccff78` remains an ancestor.

A separate `BeltRouter-lite-history.bundle` and metadata files were saved with the transfer deliverables. The bundle contains the complete filtered Git history with original author/committer metadata and dates.

| Original commit | Filtered commit | GitHub import commit | Original author date | Message |
| --- | --- | --- | --- | --- |
| [ea4abc15](https://github.com/PlexPt/small-factorio-mods/commit/ea4abc1511c27fec26b7a1e28faed859f3267fb4) | `2a02fa1bd57b923489e2be79a7faef7f5db93ead` | [96e1fb03](https://github.com/VexMex/BeltRouter/commit/96e1fb0358f15bac6d386446695404f6ba3a23f6) | 2024-10-30T08:21:21+08:00 | add BeltRouter-lite |
| [ceb51513](https://github.com/PlexPt/small-factorio-mods/commit/ceb515133f7fc51855724e406acce36032ed3c1b) | `a96cf6ac9ed0ecbba2ae3787a9fb5c59d71a90e2` | [c7db7d7b](https://github.com/VexMex/BeltRouter/commit/c7db7d7b7c84d7b810df977f3a47d5aed12793bf) | 2024-10-30T11:44:22+08:00 | add |
| [7b447047](https://github.com/PlexPt/small-factorio-mods/commit/7b4470472f6835239a5634db556fc6383ea614ba) | `f4016ef441c28794381e82101ff07704d22fd827` | [efd85671](https://github.com/VexMex/BeltRouter/commit/efd8567188dee6509eb7bba1eba908b17d3f9e57) | 2024-11-09T20:41:51+08:00 | BeltRouter-lite 2.0 |
| [66f6b35a](https://github.com/PlexPt/small-factorio-mods/commit/66f6b35a30f992ae4e1f588c73e3d16c5dfbceb2) | `1b9976e19833f5803ce21e23e6a9c19e7bbdd03b` | [699107f4](https://github.com/VexMex/BeltRouter/commit/699107f4fb1c89f9200c46bd7b8d6b9a619f9fea) | 2024-11-16T01:38:40+08:00 | up |
| [1df740a4](https://github.com/PlexPt/small-factorio-mods/commit/1df740a414320eb9b24bf46333081cc27fabb060) | `d933ec1d943a333af0700a930540a78facd179e1` | [4e6350a4](https://github.com/VexMex/BeltRouter/commit/4e6350a44c8ff872c0d0e67d1d565f4afb96c076) | 2024-12-10T03:01:56+08:00 | up |

At import, all 30 mod files were verified by their Git blob IDs against the pinned source directory. The first follow-up added English explanations as Lua comments only. Later performance changes reduced temporary allocations and repeated queries and corrected direction handling; origin and license notices remain intact.

## Reading the code

Start with `control.lua` for player input and placement, then `transport_line_connector.lua` for the weighted A* search. `path_find/path_segment.lua` describes possible building steps, and `path_find/path_node.lua` explains their costs and saved route links. The remaining Lua files include short explanations of transport rules, settings and helper functions.

## Routing performance and checks

Direction offsets and transport descriptions are reused instead of rebuilt in the inner search loop. Map-query caches are separate for each route and cleared before every search batch. Before placing any pieces, the chosen route is checked again using fresh world data; changed or deleted endpoints cancel the outdated connection.

The pathfinding algorithm, heuristic weight, route costs and candidate-pruning policy are retained. No path-finding setting or scheduler setting was raised: the default remains **15 search steps per tick**. Run the standalone Lua 5.2 regression suite with `lua tests/run.lua`; see [tests/README.md](tests/README.md) for scope and limitations.

