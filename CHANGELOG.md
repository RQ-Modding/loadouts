# Changelog

Each section is a version of the mod, the `version` in `mod.json`. The release workflow copies the
section of a tagged version into the release notes.

## 1.1.0

- Skills the game sells only through others load: a load learns what such a skill needs on the
  way, at the game's price, and erases it after when the loadout does not have it. Healing 2 after
  Healing 1 at 3, Recovery Rain 2 after Healing 3, Post-Battle Recovery after Recovery Rain 1 and
  Full Revive, the second Attack, Magic or Stamina Boost after the first at rank 4, in any order of
  the loadout. The question names the skills learned on the way, and the price counts them.
- A loadout keeps the starting skills the build lacks, and a load erases them again (after a
  reset they are back), early when a new skill needs their row and nothing still to come needs
  them. The held item's skill is never one of them.
- A skill with no purchase record (bought before loader 2.45.0) is saved when the game sells it
  once it is erased, as Healing 2 after Healing 1 is erased.
- The third world's kept Boosts: a loadout remembers the Boosts whose effect the character keeps
  without the skill; after a reset, Load asks whether to raise each to rank 4 and erase it again,
  or to load the skills only, with each one's price.
- Refusals: the free rows still missing, and the skill on the way that cannot be learned.
- Needs loader 2.48.0 (`rq.chara.learnable`'s `after`, `needs` and `level`, `rq.chara.boosts`).

## 1.0.1

- The menus' comments are cut between words (loader 2.45.1); the comments no longer break their
  sentences by hand.

## 1.0.0

First version.
- A button on each character's status page (Skill Again's icon) opens three loadout slots: Save,
  Load, Rename and Wipe.
- A loadout keeps the skills the player learned (the steps above what the character started with,
  bought in the skill window), their uses or ranks, and the whole hotbar. Kept with the game's save.
- Load buys back what the character lacks at the game's price, after a question with the price,
  then puts the hotbar back. It is refused, with the reason, when a skill cannot be learned now, the
  points or the free skill rows are short, or the saved data no longer fits the game.
