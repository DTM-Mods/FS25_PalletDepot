# 1.5.5.0 - 2026-11-16 - Fix skewed plank stacks (second attempt)

- 1.5.4.0 did not fix it and is reverted: cargo code is back to 1.5.3.0 with one change. One-mesh cargo (planks, barrels, wool, etc.) was copied with clone(), and the copy kept following the original model's bones, so the stacks drew skewed and off the pallet. It now uses the loaded model itself, like the game's own pallets.
- Test harness: added stand-ins for loadXMLFile, getName and setRotation (11 tests had failed since 1.5.3.0).
- Untested in game.

# 1.5.4.0 - 2026-11-16 - Fix leaning, sliding plank stacks

- Fixes planks (and other one-mesh cargo: barrels, buckets, cement bags, wool, etc.) leaning and hanging off the pallet. Uneven stretching sheared the skinned mesh; it is now scaled evenly and whole copies are stacked to fill the 1,000 / 2,500 / 5,000 L heights, with copies hidden as the pallet empties.
- Untested in game.

# 1.5.3.0 - 2026-11-15 - Fix stretched, overlapping cargo (planks and others)

- Fixes depot pallets showing tall stretched, overlapping slabs (planks, barrels, buckets, butter, cement bags, chocolate, potato chips, strawberries, tomatoes, wool, prefab walls, silage additive, and any mod pallet built the same way). Their layers are bones of one skinned mesh, so hiding a layer hid nothing and every layer drew the whole stack. Such cargo is now drawn once, fitted to the pallet's size (1,000 / 2,500 / 5,000 L) and shrinking with the fill level.
- Stacking collision, sizes, weights and litres unchanged (cargo stays visual only).
- Untested in game.

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
