# 1.5.2.0 — 2026-11-13 — Restore missing cargo

- Fixes loaded pallets showing only wood: native product model paths now resolve against the original game or mod directory, following the game vehicle loader. Covers relative mod paths and base-game data paths.
- Fixes the missing CPU mesh flag on the shape used for tension belts.
- Keeps the 1 / 3 / 6 layers, capacities, stacking collision and 400 kg cap.
- Untested in game. Regression checks reproduce the 1.5.1.0 failure and pass after the correction.

# 1.5.1.0 — 2026-11-13 — Real product cargo and corrected heights

- Lettuce uses its original open crates and visible lettuce heads; carrot bags use the original bags, meshes and textures. Other products likewise load their original game or installed-mod cargo instead of HUD pictures on closed boxes.
- Full 1,000 L pallets are one layer tall (0.364 m including wood). Full 2,500 L pallets are three layers tall (0.804 m). The 5,000 L size remains six layers (1.464 m).
- Keeps the existing built-in stacking collision, fork gaps, 400 kg weight limit, litres and multiplayer synchronisation. Native cargo is visual only.
- Original material maps are loaded from the installed game/mods. No copied third-party models or texture cache is shipped.
- Lettuce and carrot-bag cargo rendered and visually checked in GIANTS Editor in all three sizes. Native crates, leaves, bag geometry and textures are present. Untested in game: physics, multiplayer and other products. Indivisible cargo is fitted as a complete assembly to the depot collision envelope.

# 1.5.0.1 — 2026-11-13 — Carton flicker fix

- Product pictures on the depot cartons no longer flicker with plain white boxes. The white backing box inside each carton was only 0.2 mm under the label (z-fighting); it is now 5 mm under it.

# 1.5.0.0 — 2026-11-13 — Pallets with matching heights

- Depot spawns now use our own product-labelled cartons in 1,000 L, 2,500 L and 5,000 L sizes.
- All three sizes use a 1.20 × 0.80 m base. Full heights, including the wooden pallet, are 0.584 m, 1.024 m and 1.464 m.
- Cartons appear in complete layers, rounded up. When goods are sold, the visible layers and built-in collision shrink together.
- Mix sizes when stacking or loading a truck. Universal Autoload measures the pallet collision using its own code.
- Keeps the 400 kg weight cap, fork gaps, product information, Spawn goods window, saved litres and multiplayer synchronisation.
- Pallets from earlier saves that use another product's model keep that model. Newly spawned depot sizes use the new models. Other productions keep their existing pallets.
- Untested in game. Offline game-Lua and source-build validation are recorded with the implementation handoff.
