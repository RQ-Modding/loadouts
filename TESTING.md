# Testing Loadouts

For people and agents who test the mod in the game. Read it before you use anything the mod adds.
Assume nothing about the mod when it is not installed: check `logs\rqmod.log` for
`Loading loadouts`.

## What it adds

- **Status page button:** the control `loadouts.open` of the `status` screen (a character's status
  page from the Party screen; not on the level-up after a fight). It opens the game's choice menu
  (screen `select`).
- With more than two mods' buttons on the status page (loader 2.59.0 and later), the buttons are
  one **MODS** button (`status-mods`) over both cells, and this button is a row of the list it
  opens: press `status-mods`, then `button-loadouts-open` (`rq.gamebutton.groups()` says which).
- **The menus** (screen `select`): the slots `Slot A: <name or (Free)>`, `Slot B: ...`,
  `Slot C: ...` and Cancel; then for a slot `Save Loadout`, `Load Loadout`, `Rename Loadout`,
  `Wipe Loadout` and Back (a free slot has only Save Loadout). Use the ids `rq.ui.get` lists there;
  do not guess them.
- **Dialogs:** Yes / No before a load (with the game's "don't ask again" row) and before saving
  over or wiping a slot; an OK notice after a load and for each refusal. When the loadout kept
  Boosts the character no longer keeps (the third world, after a reset), a choice menu instead of
  the Yes / No: `Load with the kept Boosts` (id `all`), `Load the skills only` (id `skills`) and
  Back, each row's comment with its price or its refusal.
- **Rename page:** a kit page over the status page with a text field `loadouts-name` (use
  `rqmod-ctl type`), `loadouts-ok` and `loadouts-cancel`. It opens after Rename Loadout and after
  the first save into a free slot.
- **Log:** `Loadouts: saved slot <A> of character <iic>: <n> skill(s), <e> erased, <b> kept
  Boost(s)`, `Loadouts: loaded slot <A> of character <iic>: <n> purchase(s) for <p> point(s), <e>
  erased (<b> point(s) back), <h> hotbar place(s)`, `Loadouts: ... stopped at <skill>: <why>` and `Loadouts: slot <A>
  of character <iic> could not be worked out: <error>`.
- **Data:** `rq.savedata` key `chara-<character number>` in the mod's own data (it follows the
  game's save): per slot `name`, `skills` (`{id, n}`), `erased` (starting skills the build lacks),
  `boosts` (kept Boosts) and `bar`.

## How to check it

1. Open a character's status page and buy a skill in **SKILLS**; put it on the hotbar.
2. `loadouts.open` → Slot A → Save Loadout; name it, Enter.
3. ERASE that skill in SKILLS (with Skill Removal Payback the points come back).
4. `loadouts.open` → Slot A → Load Loadout → Yes. The skill is back at its level and on its hotbar
   position, and the points are spent again.
5. Spend the free points, then Load again: the notice says how many points are missing, and
   nothing is bought.
6. A build through other skills, on a healer (Crook, level 35 or more): learn Healing 2 (Healing 1
   at 3 first), Healing 3, Recovery Rain 2, then ERASE Healing 3, Healing 1 and Recovery Rain 1.
   Save, equip Skill Again (or Morurun's reset), Load: the question names Healing 3 as learned on
   the way; after it, the build is as saved and Healing 1, 3 and Recovery Rain 1 are gone.
7. Step 6 with Skill Removal Payback 1.3.0: the question's last line says what comes back
   ("The skills it erases give N back: M in all."), the notice after the load says the points
   spent and back, and the free points went down by M only.

## Forcing it for a test

`rq.mod.get("loadouts")` returns `save(iic, slot, name)`, `load(iic, slot, opts)`,
`check(iic, slot, opts)`, `rename`, `wipe`, `get(iic, slot)`, `snapshot(iic)` and
`boosts_to_rebuild(iic, entry)`: the actions without their dialogs. `opts.boosts = false` leaves
the kept Boosts out.
- `check` returns the plan: `actions` in order (`{ skill, from, to, points }` to learn,
  `{ skill, forget = true, back }` to erase), `points` (the price), `back` (what the mods give
  back for the erasures, from `rq.chara.forget_points`; 0 when none does), `peak` (the most spent at one time: the
  points the character needs), `new`, `raised`, `extra` (skills learned on the way), `erased`
  (starting skills erased), `boosts` (kept Boosts rebuilt) and `probes` (lists worked out). Or nil
  and why with a detail.
- `load` returns true and `{ learned, erased, points, back, placed }`, or false and why with a
  detail:
  `"free"`, `"bad"` (what is damaged), `"skills"` (a list of `{ id, why, text, via }`, `via` the
  skill on the way that cannot be learned), `"points"` (`{ need, have, back }`, `need` the plan's `peak`), `"room"`
  (`{ short, have, need }` in free rows), `"plan"` (the error text) or `"refused"` (the game refused
  a step; the steps before it stay done).

Use `rq.chara.learn` and `rq.chara.forget` to change a character, and
`rq.ain.call("Ｃスキルドレイン", iic)` for the game's reset. Work on a copy of the save.

## Tested in the game

The Test Lab's scenario `loadouts` (with this mod installed): save and load on a character after an ERASE, the hotbar, the
refusals (points, a skill that cannot be learned, free rows, damaged data), rename and wipe, and
the button's menus. `loadouts-paths` (with Skill Removal Payback too): Crook's healer build through
Healing 1 and Healing 3 after the game's reset, with what Payback gives back, the refusal one point
short of the most at one time and the load with exactly that, two Attack Boosts in either order and the second
alone, the kept Boosts in the third world with the choice menu, and a level the character lacks.
