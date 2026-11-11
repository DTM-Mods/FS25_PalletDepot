<p align="center">
  <a href="https://github.com/DTM-Mods"><img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/dtm-header.jpg" alt="DTM Mods by PropaineX & Fennell" width="100%"></a>
</p>

<div align="center">

<img src="docs/images/banner.jpg" alt="Logistics Hub" width="100%">

# Logistics Hub

**A pallet hall for Farming Simulator 25 that stores your products and sends them on.**

[![Build](https://github.com/DTM-Mods/FS25_PalletDepot/actions/workflows/build.yml/badge.svg)](https://github.com/DTM-Mods/FS25_PalletDepot/actions/workflows/build.yml)
![Farming Simulator 25](https://img.shields.io/badge/Farming%20Simulator-25-2e7d32)
![Version](https://img.shields.io/badge/version-1.1.0.1-1565c0)
![Multiplayer](https://img.shields.io/badge/multiplayer-supported-2e7d32)
![Languages](https://img.shields.io/badge/languages-EN%20%7C%20DE-555)
![Upkeep](https://img.shields.io/badge/daily%20upkeep-none-555)

</div>

Drop pallets on the unload pad at the front, then choose per product where it goes next. One hub can hold up to **1,000,000 L of every product** it takes.

```mermaid
flowchart LR
    A([Pallets in]) --> B[Unload pad<br/>front]
    B --> C[(Storage<br/>up to 1,000,000 L<br/>per product)]
    C -->|Storing| C
    C -->|Spawning| D[Pallets at the<br/>pickup lanes, back]
    C -->|Distributing| E[Your other<br/>productions]
    C -->|Selling| F[Sold every<br/>full hour]
```

Pallets only: bulk goods, field crops and bales are not accepted.

## Two hubs

<table>
<tr>
<td width="50%"><img src="docs/images/hero_food.jpg" alt="Food & Drinks hub"></td>
<td width="50%"><img src="docs/images/hero_goods.jpg" alt="Textiles & Goods hub"></td>
</tr>
<tr>
<td><b>Food &amp; Drinks</b> (green sign)<br/>Dairy, bread and cakes, oils, flour, sugar, honey, vegetables, fruit, juices, canned and preserved food, rice products, soups.</td>
<td><b>Textiles &amp; Goods</b> (blue sign)<br/>Fabric, clothes, wool, rope, furniture, paper and carton, building materials (cement, planks, boards, roof plates, prefab walls), seeds, fertilizer, herbicide, lime, road salt.</td>
</tr>
</table>

Both cost 50,000 and have no daily upkeep. They also take the products of:

- the **FedMods** packs (standard or ProEdition)
- the **Beans & Alpacas** pack: bananas and banana products, coffee and coffee products, and tiramisu go into Food & Drinks; alpaca goods, pigments, resin, paint buckets and fungicide go into Textiles & Goods.

With everything loaded that is up to 199 products in Food & Drinks and 81 in Textiles & Goods. Without these packs the hubs offer the base-game products.

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/features.jpg" alt="Features" width="100%">
</p>


- **Per-product routing**: store, spawn as pallets, deliver to your productions, or sell every full hour.
- **Capacity option** per hub: 100,000 / 500,000 / 1,000,000 L per product.
- **Your own pallets for every production**: any production with pickup lanes can spawn the game's pallets or this mod's **1,000 L / 5,000 L pallets**, which take any product of any map or mod.
- **Racks that fill up**: 84 pallet places that show the stock as it grows.
- **Working roller doors** on three sides. Open and close them like a garage door; their state is saved.
- **Daily report at 06:00**: what came in, went out, was delivered and was sold at each hub.
- **Hide empty materials** in the game's production menu (C), so a hub doesn't list 180 rows of 0 L.
- **AutoDrive route** imported when the hub is placed.

<table>
<tr>
<td width="50%"><img src="docs/images/inside_aisle.jpg" alt="Aisle through the racks to the back door"></td>
<td width="50%"><img src="docs/images/inside_racks.jpg" alt="Racks inside the open front"></td>
</tr>
<tr>
<td width="50%"><img src="docs/images/back_lanes.jpg" alt="Back of the hall with roller door"></td>
<td width="50%"><img src="docs/images/workbench.jpg" alt="Workbench inside the hall"></td>
</tr>
</table>

## Productions window

Press **Right Shift + P** for one table of **all** your productions, not only the hubs, with their inputs (five per line), recipes, finances and logistics.

| Key | Main page | Logistics page |
|:---:|---|---|
| <kbd>X</kbd> | inputs / outputs | schedule: the months a line runs |
| <kbd>C</kbd> | recipes | hide inactive |
| <kbd>Q</kbd> | finances | spawn goods |
| <kbd>E</kbd> | logistics | |
| <kbd>Enter</kbd> | settings | change output |
| <kbd>Backspace</kbd> | spawn goods | recipe on / off |
| <kbd>Space</kbd> | CSV export | |
| <kbd>Esc</kbd> | close | close |

The **settings** page has:

- **Auto-management**: pauses stuck lines so they stop costing money, and restarts them when they can run again.
- **Alerts** for paused or restarted lines, low inputs and nearly full outputs.
- **Building options** for the selected production: the hub's capacity, and which pallets it spawns.

Settings, schedules and options are saved with the savegame and shared with all players on a server.

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/compatibility.jpg" alt="Compatibility" width="100%">
</p>

| Mod | Needed? | What it adds |
|---|---|---|
| FedMods (standard or ProEdition) | optional | Fed products in both hubs |
| Beans & Alpacas (DLC) | optional | banana, coffee, alpaca and paint products in both hubs |
| Production Storage Control | optional | "Spawn goods" opens its spawn window with the product already selected; without it the button is hidden |
| AutoDrive | optional | imports the hub's route when it is placed |
| Price Ticker | optional | the hubs are taken out of its station list (its files are not changed) |

Multiplayer works; the server and every player need the same zip.

<!-- dtm-screenshots -->

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/screenshots.jpg" alt="Screenshots" width="100%">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/screens/FS25_PalletDepot/1_food_hub.jpg" alt="The Food & Drinks hub" width="49%">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/screens/FS25_PalletDepot/2_goods_hub.jpg" alt="The Goods hub" width="49%">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/screens/FS25_PalletDepot/3_inside_aisle.jpg" alt="Inside: the racks and the pallet lane" width="49%">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/screens/FS25_PalletDepot/4_inside_racks.jpg" alt="Inside: racks full of stored pallets" width="49%">
</p>

<!-- /dtm-screenshots -->

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/installation.jpg" alt="Installation" width="100%">
</p>

1. Download a zip from [Releases](https://github.com/DTM-Mods/FS25_PalletDepot/releases). Both zips are the same build:
   - `FS25_PalletDepot.zip`: for savegames that already have the mod. It was called Pallet Depot until 1.1.0.1, and only the old file name keeps the buildings you already own.
   - `FS25_LogisticsHub.zip`: the new name, for a new map or savegame.

   Use only **one** of them, never both.
2. Put it into your mods folder, e.g. `Documents\My Games\FarmingSimulator2025\mods\`.
3. Don't rename the zip: savegames would treat it as a different mod.

The full changelog is at the end of the description in [`modDesc.xml`](modDesc.xml).

<details>
<summary><h2>Building from source</h2></summary>

The building, textures and pallets are generated by scripts, not modelled by hand; [`tools/layout.py`](tools/layout.py) holds every position. You need:

- Python 3
- Blender 5 with the GIANTS I3D exporter (10.0.x)
- GIANTS Editor 10 (for `textureTool.exe`)
- Farming Simulator 25 (reads `maps_fillTypes.xml`)

The paths to these are constants at the top of the scripts (default Steam and install locations); change them if yours differ.

Run from the repository root:

```sh
python tools/make_textures.py                                            # textures -> src/textures/, textures/*.dds
blender --background --factory-startup --python tools/build_warehouse.py # building -> i3d/depot.i3d, build/depot.blend
python tools/finish_i3d.py                                               # checks, food/goods i3d, build/i3d_mappings.json
blender --background --factory-startup --python tools/build_pallets.py   # pallets -> vehicles/*.i3d
python tools/gen_pallets.py                                              # vehicles/depotPallet*.xml
blender --background build/depot.blend --python tools/render_store.py    # shop images and mod icon -> store/
python tools/build_mod.py                                                # validate and zip -> build/FS25_PalletDepot.zip + FS25_LogisticsHub.zip
```

`build_mod.py` regenerates the product lists (`products.py`, from the game data, [`tools/product_map.csv`](tools/product_map.csv) and the FedMods packs in your mods folder) and the placeable XMLs (`gen_placeables.py`) before it validates and zips the mod. `--bump` raises the version in `modDesc.xml` first. It checks XML, i3d mappings, file references, translations, Lua syntax and the GIANTS limits (at most 128 files, Lua files at most 0.5 MB).

GitHub Actions ([`.github/workflows/build.yml`](.github/workflows/build.yml)) runs `build_mod.py --ci` on every push: it skips `products.py` (which needs the game and the FedMods zips) and uses the committed `build/products.json`. A tag `vX.Y.Z.W` matching the version in `modDesc.xml` publishes a release with both zips.

For script or XML changes only, `build_mod.py` alone is enough; rerun the earlier steps only when the model, textures or layout change. The README images come from `blender --background build/depot.blend --python tools/render_readme.py`.

### Repository layout

| Path | Contents |
|---|---|
| `modDesc.xml` | Mod definition, all texts (English, German), full changelog |
| `scripts/` | Lua scripts (one file per feature) |
| `gui/` | Productions window and schedule dialog |
| `placeables/`, `i3d/`, `vehicles/`, `textures/`, `store/` | Game files packed into the zip (generated) |
| `src/` | PNG sources of the textures and shop images |
| `tools/` | Python and Blender pipeline: model, textures, placeables, pallets, zip |
| `build/` | Build output; only `products.json` and `i3d_mappings.json` are committed |
| `docs/images/` | README images |

</details>

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/patch-notes.jpg" alt="Patch notes" width="100%">
</p>

The full changelog is at the end of the description in [`modDesc.xml`](modDesc.xml). Builds are on the [releases page](https://github.com/DTM-Mods/FS25_PalletDepot/releases).

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/credits.jpg" alt="Credits" width="100%">
</p>

Building, textures and scripts by Fennell. Sign lettering set in Inter (SIL Open Font License).

---

<p align="center">
  <a href="https://github.com/DTM-Mods"><img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/dtm-intro.gif" alt="DTM Mods by PropaineX & Fennell" width="420"></a><br>
  <sub>Part of <a href="https://github.com/DTM-Mods">DTM Mods</a> (Dead To Me) by PropaineX & Fennell</sub>
</p>
