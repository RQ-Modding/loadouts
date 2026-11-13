-- Loadouts: three named skill builds per character, saved and loaded from the status page.
-- API reference: https://rq-modding.github.io/rq-modding-docs/reference/
--
-- A loadout keeps what the player learned (notes/plans/plan-new-mods.md in the workspace,
-- section 4): each skill above the character's starting level (rq.chara.base_skills) that was
-- bought, as the purchase record says (rq.chara.slots' cost, loader 2.45.0) or, for a purchase
-- older than the record, as the game's buy list still sells it (rq.chara.price). Its level, and the
-- whole hotbar. A skill a mod gave (record -1) or the game does not sell is never in a loadout.
--
-- A load buys back, at the game's price now, every step the character lacks (rq.chara.learn),
-- then puts the hotbar as it was. Skills the character learned since stay; one on the hotbar comes
-- off it only when a skill of the loadout needs its place. A load is refused, before anything is
-- bought, when a skill cannot be learned now, the points or the free rows are short, or the saved
-- data no longer fits the game.
--
-- Kept in rq.savedata (it follows the game's save), one key per character: "chara-<number>"
-- (or "chara-<text id>" for a mod's character) = { A = { name, skills = {{id, n}}, bar }, ... }.

local MOD = "Loadouts"
local ICON = 6381          -- Skill Again's icon (item 306)
local SLOTS = { "A", "B", "C" }
local NAME_MAX = 30
local BAR = 6              -- the hotbar's positions on the game's screens
local LIST_MAX = 6         -- skills named in one dialog (it takes 9 lines)

local ui = rq.uikit
local SKILL_SLOTS = rq.ids.skill.SKILL_SLOTS -- its rank + 2 is the hotbar's size

-- ---- the data ----

local function key_of(iic)
  local c = rq.chara.get(iic)
  if not c then return nil end
  return "chara-" .. tostring(c.id or c.no)
end

local function all(iic)
  local k = key_of(iic)
  local v = k and rq.savedata.get(k) or nil
  if type(v) ~= "table" then v = {} end
  return v, k
end

local function get(iic, slot)
  local v = all(iic)[slot]
  if type(v) == "table" then return v end
  return nil
end

local function put(iic, slot, entry)
  local v, k = all(iic)
  if not k then error("no character at " .. tostring(iic)) end
  v[slot] = entry
  if next(v) == nil then
    rq.savedata.delete(k)
  else
    rq.savedata.set(k, v)
  end
end

local function skill_name(id)
  local ok, s = pcall(rq.skill.get, id)
  local name = ok and s and s.name or ""
  if name == "" then return "Skill " .. tostring(id) end
  return name
end

local function skill_type(id)
  local ok, s = pcall(rq.skill.get, id)
  return ok and s and s.type or 0
end

local function level_text(id, n)
  if skill_type(id) == 10 then return n .. (n == 1 and " use" or " uses") end
  return "rank " .. n
end

local function short_name(iic)
  local c = rq.chara.get(iic)
  if not c then return "?" end
  if c.short and c.short ~= "" then return c.short end
  return c.name
end

local function plural(n, one, many)
  return n .. " " .. (n == 1 and one or many)
end

-- ---- what the character learned ----

-- The loadout of the character as it is now: the learned skills and the hotbar.
local function snapshot(iic)
  local base = {}
  for _, s in ipairs(rq.chara.base_skills(iic)) do base[s.id] = s.n end
  local skills, bar = {}, {}
  for i = 1, BAR do bar[i] = 0 end
  for _, s in ipairs(rq.chara.slots(iic)) do
    if s.skill > 0 then
      if s.bar >= 1 and s.bar <= BAR then bar[s.bar] = s.skill end
      local from = math.min(base[s.skill] or 0, s.n)
      if s.n > from and s.cost ~= -1 then
        if s.cost > 0 or rq.chara.price(iic, s.skill, from, s.n) ~= nil then
          skills[#skills + 1] = { id = s.skill, n = s.n }
        end
      end
    end
  end
  return skills, bar
end

-- What is wrong with a slot's data, or nil.
local function invalid(entry)
  if type(entry.name) ~= "string" or entry.name == "" then return "it has no name" end
  if type(entry.skills) ~= "table" then return "it has no skill list" end
  local seen = {}
  for i, s in ipairs(entry.skills) do
    if type(s) ~= "table" or math.type(s.id) ~= "integer" or math.type(s.n) ~= "integer" or s.n < 1 then
      return "skill entry " .. i .. " is damaged"
    end
    if s.id < 1 or s.id > 1000 or skill_name(s.id) == "Skill " .. s.id then
      return "skill " .. s.id .. " is not in the game (a mod's skill whose mod is gone?)"
    end
    if seen[s.id] then return skill_name(s.id) .. " is in it twice" end
    seen[s.id] = true
  end
  if entry.bar ~= nil then
    if type(entry.bar) ~= "table" or #entry.bar > BAR then return "its hotbar is damaged" end
    for _, id in ipairs(entry.bar) do
      if math.type(id) ~= "integer" or id < 0 or id > 1000 then return "its hotbar is damaged" end
    end
  end
  return nil
end

local function why_text(why, text)
  if why == "condition" and text then
    local last = tostring(text):match("([^\n]+)%s*$") or tostring(text)
    last = last:gsub("^%s*・%s*", "")
    return last
  end
  if why == "not sold" then return "not in this character's skill list" end
  if why == "max" then return "past its most uses or rank" end
  if why == "room" then return "no free row" end
  return tostring(why)
end

-- What a load would do: the steps, their price, the new rows. nil and why ("free", "bad", "skills",
-- "points", "room") and a detail when it cannot be done now.
local function check(iic, slot)
  local entry = get(iic, slot)
  if not entry then return nil, "free" end
  local bad = invalid(entry)
  if bad then return nil, "bad", bad end
  local have = {}
  for _, s in ipairs(rq.chara.slots(iic)) do
    if s.skill > 0 then have[s.skill] = s.n end
  end
  local plan = { entry = entry, steps = {}, points = 0, new = 0, raised = 0 }
  local cannot = {}
  for _, s in ipairs(entry.skills) do
    local cur = have[s.id] or 0
    if cur < s.n then
      local p, why, text = rq.chara.price(iic, s.id, cur, s.n)
      if p or why == "room" then
        -- "room": every skill row is taken, so the new skill could not even be priced
        plan.steps[#plan.steps + 1] = { id = s.id, from = cur, to = s.n, points = p or 0 }
        plan.points = plan.points + (p or 0)
        if cur == 0 then plan.new = plan.new + 1 else plan.raised = plan.raised + 1 end
      else
        cannot[#cannot + 1] = { id = s.id, why = why, text = why_text(why, text) }
      end
    end
  end
  if #cannot > 0 then return nil, "skills", cannot end
  local room = rq.chara.skill_room(iic)
  if plan.new > room then return nil, "room", { need = plan.new, have = room } end
  local free = rq.chara.skill_points(iic)
  if plan.points > free then return nil, "points", { need = plan.points, have = free } end
  return plan
end

-- The hotbar's size now: Skill Slots' rank + 2, at most the screens' 6.
local function bar_size(iic)
  local rank = rq.chara.rank(iic, SKILL_SLOTS)
  return math.min(BAR, math.max(rank, 1) + 2)
end

-- Puts the saved hotbar back: each saved skill the character has goes to its position, and what
-- sat there comes off. Positions the loadout left empty, or past the hotbar's size, stay as they are.
local function put_bar(iic, bar)
  if type(bar) ~= "table" then return 0 end
  local rows = rq.chara.slots(iic)
  local by_skill = {}
  for _, s in ipairs(rows) do
    if s.skill > 0 then by_skill[s.skill] = s end
  end
  local placed = 0
  for pos = 1, bar_size(iic) do
    local row = by_skill[bar[pos] or 0]
    if row and row.bar ~= pos then
      for _, s in ipairs(rows) do
        if s.bar == pos then
          rq.chara.set_bar(iic, s.slot, 0)
          s.bar = 0
        end
      end
      rq.chara.set_bar(iic, row.slot, pos)
      row.bar = pos
      placed = placed + 1
    end
  end
  return placed
end

-- ---- the four actions, without the dialogs (Lab tests call these) ----

local function save(iic, slot, name)
  local skills, bar = snapshot(iic)
  local old = get(iic, slot)
  name = name or (old and type(old.name) == "string" and old.name ~= "" and old.name) or ("Loadout " .. slot)
  local entry = { name = name, skills = skills, bar = bar }
  put(iic, slot, entry)
  rq.log(("%s: saved slot %s of character %d: %d skill(s)"):format(MOD, slot, iic, #skills))
  return entry
end

-- Loads a slot: true and what it did, or false and check's why and detail ("refused" when the
-- game refused a step: the steps before it stay bought).
local function load(iic, slot)
  local plan, why, detail = check(iic, slot)
  if not plan then return false, why, detail end
  local done = { learned = 0, points = 0 }
  for _, st in ipairs(plan.steps) do
    local ok, spent, more = rq.chara.learn(iic, st.id, { to = st.to })
    if not ok then
      rq.log(("%s: %s of character %d stopped at %s: %s"):format(MOD, slot, iic, skill_name(st.id),
        tostring(spent)))
      done.failed = { id = st.id, why = spent, text = why_text(spent, more) }
      done.placed = put_bar(iic, plan.entry.bar)
      rq.statuspage.refresh()
      return false, "refused", done
    end
    done.learned = done.learned + 1
    done.points = done.points + spent
  end
  done.placed = put_bar(iic, plan.entry.bar)
  rq.statuspage.refresh()
  rq.log(("%s: loaded slot %s of character %d: %d skill(s) for %d point(s), %d hotbar place(s)"):format(
    MOD, slot, iic, done.learned, done.points, done.placed))
  return true, done
end

local function rename(iic, slot, name)
  local entry = get(iic, slot)
  if not entry then return false end
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return false end
  entry.name = name
  put(iic, slot, entry)
  return true
end

local function wipe(iic, slot)
  if not get(iic, slot) then return false end
  put(iic, slot, nil)
  return true
end

-- ---- the menus ----

local prompt = nil -- { iic, slot, value }: the rename page, drawn by rq.on_frame
local open_menu, slot_menu

local function quote(entry)
  return "'" .. entry.name .. "'"
end

-- The comment box beside a slot's row: what it holds.
local function summary(entry, most)
  most = most or 8
  if invalid(entry) then return "Its data no longer fits the game." end
  if #entry.skills == 0 then return "No learned skills; only the hotbar." end
  local lines = {}
  for i, s in ipairs(entry.skills) do
    if i > most then
      lines[#lines + 1] = "... and " .. (#entry.skills - most) .. " more"
      break
    end
    lines[#lines + 1] = skill_name(s.id) .. " (" .. level_text(s.id, s.n) .. ")"
  end
  return table.concat(lines, "\n")
end

local function refusal(iic, entry, why, detail)
  local name = quote(entry or { name = "?" })
  if why == "bad" then
    return name .. "'s data no longer fits the game:\n" .. detail ..
      ".\nWipe the slot, then save it again."
  end
  if why == "skills" then
    local lines = { name .. " cannot be loaded now. " .. short_name(iic) .. " cannot learn:" }
    for i, c in ipairs(detail) do
      if i > LIST_MAX then
        lines[#lines + 1] = "... and " .. (#detail - LIST_MAX) .. " more"
        break
      end
      lines[#lines + 1] = skill_name(c.id) .. ": " .. c.text
    end
    return table.concat(lines, "\n")
  end
  if why == "points" then
    return ("%s costs %d skill points; %s has %d.\n%s more needed."):format(name, detail.need,
      short_name(iic), detail.have, plural(detail.need - detail.have, "point is", "points are"))
  end
  if why == "room" then
    return ("%s needs %s for its new skills; %s has %d.\nERASE skills to make room."):format(name,
      plural(detail.need, "free skill row", "free skill rows"), short_name(iic), detail.have)
  end
  return name .. " cannot be loaded now."
end

local function do_save(iic, slot)
  local old = get(iic, slot)
  if old then
    local yes = rq.ui.confirm(("Save %s's skills over %s?"):format(short_name(iic), quote(old)),
      { cursor = "no" })
    if not yes then return slot_menu(iic, slot) end
  end
  local ok, entry = pcall(save, iic, slot)
  if not ok then
    rq.log(MOD .. ": " .. tostring(entry))
    rq.ui.notice("The loadout could not be saved.")
    return slot_menu(iic, slot)
  end
  if old then
    rq.ui.notice(("%s is saved: %s."):format(quote(entry), plural(#entry.skills, "learned skill", "learned skills")))
    return open_menu(iic, slot)
  end
  -- A new loadout gets a name at once; Esc keeps "Loadout A".
  prompt = { iic = iic, slot = slot, value = entry.name, new = true }
end

local function do_load(iic, slot)
  local entry = get(iic, slot)
  local plan, why, detail = check(iic, slot)
  if not plan then
    rq.ui.notice(refusal(iic, entry, why, detail))
    return slot_menu(iic, slot)
  end
  if #plan.steps > 0 then
    local parts = {}
    if plan.new > 0 then parts[#parts + 1] = "learns " .. plural(plan.new, "skill", "skills") end
    if plan.raised > 0 then parts[#parts + 1] = "raises " .. plural(plan.raised, "skill", "skills") end
    local text = ("Load %s?\nIt %s for %s.\n%s has %d."):format(quote(entry), table.concat(parts, " and "),
      plural(plan.points, "skill point", "skill points"), short_name(iic), rq.chara.skill_points(iic))
    if not rq.ui.confirm(text, { remember = "load", remember_label = "Loading a loadout" }) then
      return slot_menu(iic, slot)
    end
  end
  local ok, done, more = load(iic, slot)
  if ok then
    if done.learned == 0 then
      rq.ui.notice(("%s is loaded: nothing to learn, the hotbar is set."):format(quote(entry)))
    else
      rq.ui.notice(("%s is loaded: %s for %s."):format(quote(entry),
        plural(done.learned, "skill", "skills"), plural(done.points, "point", "points")))
    end
  elseif done == "refused" then
    rq.ui.notice(("Loading %s stopped at %s: %s.\nThe %s before it %s learned."):format(quote(entry),
      skill_name(more.failed.id), more.failed.text, plural(more.learned, "skill", "skills"),
      more.learned == 1 and "is" or "are"))
  else
    rq.ui.notice(refusal(iic, entry, done, more))
  end
end

local function do_wipe(iic, slot)
  local entry = get(iic, slot)
  if rq.ui.confirm(("Wipe %s from slot %s?\n%s's skills do not change."):format(quote(entry), slot,
      short_name(iic)), { cursor = "no" }) then
    wipe(iic, slot)
    return open_menu(iic, slot)
  end
  return slot_menu(iic, slot)
end

slot_menu = function(iic, slot)
  if rq.statuspage.chara() ~= iic then return end
  local entry = get(iic, slot)
  local rows, message
  if entry then
    message = "What to do with " .. quote(entry) .. "?"
    rows = {
      { id = "save", text = "Save Loadout", comment = "Keep " .. short_name(iic) .. "'s learned skills and hotbar here, in place of these." },
      { id = "load", text = "Load Loadout", comment = "Learn what is missing at the game's price, then set the hotbar.\n\n" .. summary(entry, 5) },
      { id = "rename", text = "Rename Loadout" },
      { id = "wipe", text = "Wipe Loadout", comment = "Empty the slot. The skills do not change." },
    }
  else
    message = "Slot " .. slot .. " is free."
    rows = {
      { id = "save", text = "Save Loadout", comment = "Keep " .. short_name(iic) .. "'s learned skills and hotbar here." },
    }
  end
  rq.ui.choose(rows, function(id)
    if id == 0 then return open_menu(iic, slot) end
    if rq.statuspage.chara() ~= iic then return end
    if id == "save" then return do_save(iic, slot) end
    if id == "load" then return do_load(iic, slot) end
    if id == "rename" then
      prompt = { iic = iic, slot = slot, value = entry.name }
      return
    end
    if id == "wipe" then return do_wipe(iic, slot) end
  end, { message = message, back = "Back" })
end

open_menu = function(iic, cursor)
  if rq.statuspage.chara() ~= iic then return end
  local rows = {}
  for _, slot in ipairs(SLOTS) do
    local entry = get(iic, slot)
    rows[#rows + 1] = {
      id = slot,
      text = "Slot " .. slot .. ": " .. (entry and entry.name or "(Free)"),
      comment = entry and summary(entry) or "Free: save a loadout here.",
    }
  end
  rq.ui.choose(rows, function(id)
    if id ~= 0 then slot_menu(iic, id) end
  end, {
    message = "Loadouts of " .. short_name(iic) .. ": the skills you learned,\ntheir uses and ranks, and the hotbar.",
    back = "Cancel", cursor = cursor,
  })
end

-- ---- the rename page ----

local QW, QH = 520, 192
local DIM = { r = 170, g = 170, b = 190 }

local function label(x, y, str, size, col)
  col = col or { r = 245, g = 245, b = 255 }
  rq.hud.text(x + 1, y + 1, str, { size = size, r = 0, g = 0, b = 0 })
  rq.hud.text(x, y, str, { size = size, r = col.r, g = col.g, b = col.b })
end

local function draw_prompt()
  local sw, sh = rq.hud.screen()
  local x, y = (sw - QW) // 2, (sh - QH) // 2
  local p, act = prompt, nil
  local was = ui.theme
  ui.use(ui.themes.hub)
  local ok, err = pcall(function()
    rq.hud.rect(x, y, QW, QH, 0, 0, 0, 200)
    local still = ui.page({ id = "loadouts-name", title = "Rename", x = x, y = y, w = QW, h = QH }, function(cx, cy, cw)
      label(cx, cy + 6, "A name for slot " .. p.slot .. " of " .. short_name(p.iic) .. ".", 15)
      local value, _, ended = ui.input(p.value, { id = "loadouts-name", x = cx, y = cy + 30, w = cw,
        max = NAME_MAX, focus = true, placeholder = "A name" })
      p.value = value
      local blank = not value:match("%S")
      if ended == "enter" and not blank then act = "ok" end
      if ended == "esc" then act = "cancel" end
      label(cx, cy + 66, "Enter is OK, Esc cancels.", 13, DIM)
      if ui.button("OK", { x = cx + cw - 248, y = cy + 92, w = 120, id = "loadouts-ok", disabled = blank }) then
        act = act or "ok"
      end
      if ui.button("Cancel", { x = cx + cw - 120, y = cy + 92, w = 120, id = "loadouts-cancel" }) then
        act = act or "cancel"
      end
    end)
    if not still then act = act or "cancel" end
  end)
  ui.use(was)
  if not ok then error(err, 0) end
  return act
end

-- The page opens from a menu's pick: its field types from its first draw (focus), so the first draw
-- waits for the menu to close and the pick's mouse button and keys to be let go, for 3 updates in a
-- row: the kit holds its input back until the update after the release, and a field first drawn
-- then would never type.
local SETTLE_KEYS = {}
for _, k in ipairs({ "lmb", "rmb", "enter", "esc", "space" }) do SETTLE_KEYS[#SETTLE_KEYS + 1] = rq.input.code(k) end

local function settled()
  if rq.ui.choosing() then return false end
  for _, code in ipairs(SETTLE_KEYS) do
    if rq.input.key(code) then return false end
  end
  return true
end

rq.on_frame(function()
  if not prompt then return end
  if rq.statuspage.chara() ~= prompt.iic then
    prompt = nil
    return
  end
  if not prompt.shown then
    prompt.calm = settled() and (prompt.calm or 0) + 1 or 0
    if prompt.calm < 3 then return end
    prompt.shown = true
  end
  local act = draw_prompt()
  if act then
    local p = prompt
    prompt = nil
    if act == "ok" then rename(p.iic, p.slot, p.value) end
    open_menu(p.iic, p.slot)
  end
end)

-- ---- the button ----

rq.gamebutton.add({
  group = "status",
  id = "open",
  label = MOD,
  icon = ICON,
  shown = function(_, mode) return mode ~= "battle-result" end,
  enabled = function(iic) return iic ~= nil end,
  tip = "Save this character's learned skills and hotbar\nin one of three slots, and load them back.",
  on_click = function()
    local iic = rq.statuspage.chara()
    if iic and not prompt then open_menu(iic) end
  end,
})

rq.log(MOD .. " loaded")

-- For tests and other mods (rq.mod.get("loadouts")): the actions without their dialogs.
return {
  slots = SLOTS,
  get = get,
  snapshot = snapshot,
  check = check,
  save = save,
  load = load,
  rename = rename,
  wipe = wipe,
  put = put, -- writes a slot's data as it is: for tests of damaged data
  bar_size = bar_size,
  prompt = function() return prompt end,
}
