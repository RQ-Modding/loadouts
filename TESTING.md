# Testing Loadouts

For people and agents who test the mod in the game. Read it before you use anything the mod adds.
Assume nothing about the mod when it is not installed: check `logs\rqmod.log` for
`Loading loadouts`.

## What it adds

- **Status page button:** the control `loadouts.open` of the `status` screen (a character's status
  page from the Party screen; not on the level-up after a fight). It opens the game's choice menu
  (screen `select`).
- **The menus** (screen `select`): the slots `Slot A: <name or (Free)>`, `Slot B: ...`,
  `Slot C: ...` and Cancel; then for a slot `Save Loadout`, `Load Loadout`, `Rename Loadout`,
  `Wipe Loadout` and Back (a free slot has only Save Loadout). Use the ids `rq.ui.get` lists there;
  do not guess them.
- **Dialogs:** Yes / No before a load (with the game's "don't ask again" row) and before saving
  over or wiping a slot; an OK notice after a load and for each refusal.
- **Rename page:** a kit page over the status page with a text field `loadouts-name` (use
  `rqmod-ctl type`), `loadouts-ok` and `loadouts-cancel`. It opens after Rename Loadout and after
  the first save into a free slot.
- **Log:** `Loadouts: saved slot <A> of character <iic>: <n> skill(s)`, `Loadouts: loaded slot ...`
  and `Loadouts: ... stopped at <skill>: <why>`.
- **Data:** `rq.savedata` key `chara-<character number>` in the mod's own data (it follows the
  game's save).

## How to check it

1. Open a character's status page and buy a skill in **SKILLS**; put it on the hotbar.
2. `loadouts.open` → Slot A → Save Loadout; name it, Enter.
3. ERASE that skill in SKILLS (with Skill Removal Payback the points come back).
4. `loadouts.open` → Slot A → Load Loadout → Yes. The skill is back at its level and on its hotbar
   position, and the points are spent again.
5. Spend the free points, then Load again: the notice says how many points are missing, and
   nothing is bought.

## Forcing it for a test

`rq.mod.get("loadouts")` returns `save(iic, slot, name)`, `load(iic, slot)`, `check(iic, slot)`,
`rename`, `wipe`, `get(iic, slot)` and `snapshot(iic)`: the actions without their dialogs. `load`
returns true and `{ learned, points, placed }`, or false and why (`"free"`, `"bad"`, `"skills"`,
`"points"`, `"room"`, `"refused"`) with a detail. Use `rq.chara.learn` and `rq.chara.forget` to
change a character. Work on a copy of the save.

## Test Lab

`loadouts` (with this mod installed): save and load on a character after an ERASE, the hotbar, the
refusals (points, a skill that cannot be learned, damaged data), rename and wipe, and the button's
menus.
