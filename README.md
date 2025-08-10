This mod stretches Factorio by ~100× while keeping the vanilla ratios you’re used to.

## What it does
- **Recipes:** Any recipe that touches a *final product* (as input or output) gets 100× craft time, and all **non-final** ingredients/products are scaled 100×. Final products are: placeable buildings/tiles/vehicles, modules, armor, equipment modules, combat equipment (not ammo), and cliff explosives. Science packs count as **non-final**. Fluids in those recipes are also scaled 100×.
- **Science:** Global research cost ×100 (uses difficulty setting). Research *time per unit* is unchanged.
- **Biters:** Evolution from time, pollution, and destruction is 100× slower. Enemy expansion is disabled.
- **HP:** All buildings get 100× HP (including enemy buildings). **Trains** (locos & wagons) get 100× HP. (Cars/tanks/spiders are intentionally excluded.) **Demolishers** also get 100× HP.
- **Naturals:** Trees, jellystems, ruins, lithium-ice-like map objects, etc. (anything with `autoplace` and `minable`, except pentapod shells) have 100× HP, take 100× longer to mine, and yield 100× of their **non-final** drops (e.g., wood, jellynuts).
- **Resources:** All resource fields (including oil and lithium brine) spawn ~100× richer. Pumpjacks mine ~100× slower so per-pump throughput stays roughly vanilla while fields last ~100× longer.
- **Space:** Rockets cost ~100× more (marking rocket-part as final), rocket cargo slot counts are ~100× larger where supported, and rocket_lift_weight is ×100. Item default weight is unchanged, but any custom item weight on finals is ×100.
- **Spoilage:** Items spoil ~10× slower globally.

## Patchwork fix for 65,535 cap
- Factorio caps ingredient/product stack amounts in recipes at 65,535. Some 100× scalings (e.g., rocket-silo requiring 1000 steel becomes 100,000) exceed this.
- To avoid load errors, amounts are clamped to 65,535.

## Clarifications
- Biter buildings (spawners and worm turrets) now also get 100× HP.
- Ores keep their vanilla mining time; only their field amounts are ~100× richer.
- Capture-bot rockets are treated as final.
- Land mines are not treated as final.
- Ensures armor, modules, guns, and equipment items are treated as final for recipe scaling.

## Install
1. Copy the `IdleX100_0.1.0/` folder to your `mods` directory.
2. Start Factorio → Mods → ensure “Idle x100 — really long idle” is enabled.
3. Load a save or start a new game. The runtime settings apply immediately.

## Notes
- Resource richening scans existing chunks once at init; new chunks are handled on generation.
- If you want to re-run richening by hand: open console and run: `/c remote.call("IdleX100", "rerich")`.
- The mod doesn’t alter ammo, weapon DPS, or vehicle HP (except trains) for balance.
- Science pack recipes commonly output 100× packs because they typically use final items (inserter, belt) as inputs — this matches the 100× research cost.