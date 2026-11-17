# 1.5.8.3 - 2026-11-17 - GIANTS' ModHub guidelines

- Description in GIANTS' ModHub layout (category, price, upkeep or hotkeys at the top).
- New mod icon in the ModHub standard.
- Shop images without mipmaps, as ModHub wants.
- No modder names in the description and the game texts any more.

# 1.5.8.2 - 2026-11-17 - Current game version

- Updated for the current game version: modDesc descVersion 116 (the game build of 2026-10-27; GIANTS TestRunner 0.9.24 accepts only 116).

# 1.5.8.1 - 2026-11-16 - Pass GIANTS' ModHub checks

- Meets GIANTS' ModHub checks (TestRunner). The mod icon is 512 x 512 (DXT1, no mipmaps); the buildings' shop pictures keep 3 mipmaps (tools/dds_mips.py, which render_store.py now runs; it renders the icon at 512 px).
- The Spawn goods window names its own pictures (textures/ui_*.dds) by their full path, so the check sees they are used. No visible change.
- The zip leaves out what the game never loads: the source images in src/, the Blender export i3d/depot.i3d and the unused pallet_goods textures. tools/build_mod.py now reads .modignore, the same list the DTM CI uses.
- Both buildings state their daily upkeep in the shop data (0, so still no upkeep).
- Errors are no longer hidden: they show in the log. The production menu's lists, the month names of schedules and the goods shown on pallets now call the game directly instead of catching its errors; if a menu function stops with an error, the depot's own tables are still put back on the next frame, and a pallet gets its capacity back on its next fill change.

# 1.5.8.0 - 2026-11-16 - Restore depot pallet pickup

- Fixes the loading failure introduced in 1.5.7.0. Universal Autoload can recognize depot pallets again and offer its loading action.
- The size lookup now reads the collision's numeric node ID from the game's mapping record. Missing collision mappings retain Autoload's original measurement.
- Regression checks use the game's mapping format and Universal Autoload's actual pickup callback, eligibility counts and loading-action gate, covering all three sizes and access/material filters. The released code fails these checks; the correction passes all 50 offline tests. Untested in game.

# 1.5.7.0 - 2026-11-16 - Match plank height and Autoload spacing

- Full 5,000 L planks fill the large pallet's 1.464 m height, so the visible cargo reaches the existing stacking and belt surface. The 1,000 / 2,500 L sizes likewise fill their 0.364 / 0.804 m heights; part-filled loads follow the complete layers.
- Fixes the game-only cargo-loading error that left a short plank bundle inside the full-size collision.
- Depot pallets report their 1.20 x 0.80 m footprint to Universal Autoload, preventing a bad cached measurement from wasting trailer space. The Krone Profi Liner fits three narrow sides across; partially emptied pallets retain their current collision height.
- Verified in GIANTS Editor with the unavailable game function disabled, plus the installed Universal Autoload packing code. Offline checks cover all three pallet sizes, partial loads and a bad cached size. Untested in game.

# 1.5.6.0 - 2026-11-16 - Align plank stacks with their pallet

- Plank stacks stay square with their wooden pallet when spawned or turned. The original game mesh and its diffuse, normal and specular textures are retained.
- Planks fit the 1.20 x 0.80 m base and the full 0.364 / 0.804 / 1.464 m heights of the 1,000 / 2,500 / 5,000 L pallets. Part-filled stacks follow the existing complete-layer collision height.
- Removes the failed 1.5.4.0/1.5.5.0 experiments. This correction is limited to the native boards-stack model; other cargo, capacity, weight and autoload behavior are unchanged.
- Verified in GIANTS Editor at three rotations and every partial-load height; 44 offline tests pass. Untested in game.

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
