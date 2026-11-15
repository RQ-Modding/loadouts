# Loadouts

Three named skill builds per character. Save the skills you learned and the hotbar, try another
build, and load the first one back, from the character's status page.

## What it adds

- **A button on the status page**, in the title row beside the character's name, with Skill
  Again's icon. It opens the game's menu: **Slot A**, **Slot B** and **Slot C**, each with its
  name or "(Free)". Hover a slot to see what it holds.
- **Save Loadout** keeps, in that slot, the skills you **learned** for the character (the uses and
  ranks you bought above what the character started with) and the whole hotbar. Skills the
  character came with, and skills a story event or another mod gave, are not part of it. A new
  loadout asks for a name at once; Esc keeps "Loadout A".
- **Load Loadout** buys back, at the game's price, every skill and step of the loadout the
  character lacks, then puts the hotbar as it was. It tells you what it learns and the price first.
  Skills you learned since stay; one on the hotbar comes off it only when a skill of the loadout
  needs its place. After Morurun's reset or Skill Again, a load puts the whole build back.
- **Skills the game sells only through others** load too. Healing 2 is for sale once Healing 1 is
  at 3, Recovery Rain 2 once Healing 3 is learned, the second Attack Boost once the first is at
  rank 4: a load learns what such a skill needs on the way, at the game's price, and erases it
  after when the loadout does not have it. The starting skills you had erased (to make room, or
  because a build did not want them) are erased again, early when a new skill needs their row. The
  question before a load names the skills learned on the way, and its price counts them.
- **Boosts whose effect stays.** In the third world, a Boost raised to rank 4 keeps its effect
  after an ERASE, until Morurun's reset or Skill Again. A loadout remembers those Boosts. After a
  reset, Load asks: **Load with the kept Boosts** raises each one to rank 4 again and erases it, so
  its effect is back; **Load the skills only** costs less and leaves them out. Each row shows its
  price.
- **Rename Loadout** and **Wipe Loadout** (wiping changes no skill).

A load is refused, before anything is bought, when:
- the character cannot learn a skill of it now, or one it needs on the way (the menu lists them,
  with the game's reason, such as a level it lacks),
- the character lacks the points (it says how many more are needed),
- there are not enough free skill rows for its new skills, after erasing what the build lacks
  (it says how many more; ERASE some first),
- the saved data no longer fits the game, such as a skill of a mod you removed (wipe the slot and
  save it again).

With [Skill Removal Payback](https://github.com/RQ-Modding/skill-removal-payback) the points of an
ERASE come back, so switching between loadouts costs nothing in the end. The erasures a load makes
give points back too (Skill Removal Payback 1.3.0, or any mod that pays back the skills you
erase): the skills learned on the way and the starting skills the build lacks. The question before
a load says how many come back and the price in all, so a build costs only its own skills. A load
still needs the points it spends before those come back. Without such a mod, the price a load
shows is what it costs, the skills on the way included.

## Keys and settings

None. The question before a load has the game's "don't ask again" row; Config → Mods →
Confirmations turns it back on.

## Saves

The loadouts are kept with the game's save, in `RanceQuestMagnum_030.rqmod.json` beside it, so each
save has its own. The game ignores that file; without the mod it stays as it is.

## Install

Needs [RQ MOD](https://github.com/RQ-Modding/RQ-Mod) with loader **2.52.0** or newer. Extract the
release zip into the game's `mods` folder, so that you have `mods/loadouts/mod.json`.

## How it works

The button is `rq.gamebutton`'s `"status"` group and the menus are `rq.ui.choose`. What was bought
comes from the loader's purchase record (`rq.chara.slots`' `cost`) and the starting set
(`rq.chara.base_skills`); for a skill bought before RQ MOD 2.45.0, one the game's buy list sells, or
names once the skill is erased (`rq.chara.price`, `rq.chara.learnable`'s `after`). A load works
out its steps on the game's own list as it would be after the steps so far
(`rq.chara.learnable`'s `after`, the game's conditions as `needs` and `level`), with the kept
Boosts from `rq.chara.boosts`; then it buys with `rq.chara.learn` (the game's own buy), erases with
`rq.chara.forget` and `player = true` (the player's erasure, which Skill Removal Payback pays
back; `rq.chara.forget_points` gives what each erasure of the plan would give back) and places the hotbar with `rq.chara.set_bar`. The data is in `rq.savedata`.

## License

MIT, see [LICENSE](LICENSE).
