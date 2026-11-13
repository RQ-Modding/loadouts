# Changelog

Each section is a version of the mod, the `version` in `mod.json`. The release workflow copies the
section of a tagged version into the release notes.

## 1.0.0

First version.
- A button on each character's status page (Skill Again's icon) opens three loadout slots: Save,
  Load, Rename and Wipe.
- A loadout keeps the skills the player learned (the steps above what the character started with,
  bought in the skill window), their uses or ranks, and the whole hotbar. Kept with the game's save.
- Load buys back what the character lacks at the game's price, after a question with the price,
  then puts the hotbar back. It is refused, with the reason, when a skill cannot be learned now, the
  points or the free skill rows are short, or the saved data no longer fits the game.
