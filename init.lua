-- Loadouts: three named skill builds per character, saved and loaded from the status page.
-- API reference: https://rq-modding.github.io/rq-modding-docs/reference/
--
-- A loadout keeps what the player did to the character's skills:
--   skills   each skill above the character's starting level (rq.chara.base_skills) that was
--            bought, as the purchase record says (rq.chara.slots' cost, loader 2.45.0) or, for a
--            purchase older than the record, as the game's buy list offers it (sold now, or listed
--            with the game's condition once erased, or a Boost). Its level. A skill a mod gave
--            (record -1) or the game does not offer is never in a loadout.
--   erased   the starting skills the player erased (the ones ERASE can erase)
--   boosts   the Boosts whose effect the character kept after an ERASE (rq.chara.boosts, the third
--            world only)
--   bar      the whole hotbar
--
-- A load is worked out first, on the character as the game would see it after each step
-- (rq.chara.learnable's after, loader 2.48.0, which changes nothing), then bought:
--   - each kept Boost the character lacks is raised to rank 4 (the game then keeps its effect) and
--     erased, unless the loadout keeps the skill; the player may leave them out
--   - each skill is raised step by step at the list's price. A skill the game sells only once
--     others are learned is reached through what its condition names (Recovery Rain 2: Healing 3
--     1+; Healing 3: Healing 2 3+), or, when the game names nothing (the second Attack Boost), the
--     one skill whose level puts it up for sale. A skill learned only on the way is erased at the end
--   - the starting skills the loadout lacks are erased at the end, or earlier when a new skill
--     needs their row and nothing still to come needs them
-- then the hotbar is put as it was. Skills the character learned since stay. A load is refused,
-- before anything is bought, when a skill cannot be reached, the points or the free rows are short,
-- or the saved data no longer fits the game.
--
-- A load's erasures are the player's (rq.chara.forget with player = true, loader 2.51.0), so a mod
-- that gives points back for ERASE (Skill Removal Payback) gives them back here too. The plan asks
-- what each erasure would give, as the row will be then (rq.chara.forget_points, loader 2.52.0;
-- 1.3.0), counts those points (its price less what comes back) and needs the most the load spends
-- at any one time, since a refund comes only when its skill is erased.
--
-- Kept in rq.savedata (it follows the game's save), one key per character: "chara-<number>"
-- (or "chara-<text id>" for a mod's character) =
-- { A = { name, skills = {{id, n}}, erased = {id}, boosts = {id}, bar }, ... }.

local MOD = "Loadouts"
local ICON = 6381          -- Skill Again's icon (item 306)
local SLOTS = { "A", "B", "C" }
local NAME_MAX = 30
local BAR = 6              -- the hotbar's positions on the game's screens
local LIST_MAX = 6         -- skills named in one dialog (it takes 9 lines)
local PROBES = 800         -- lists worked out for one plan at most
local DEPTH = 8            -- skills reached through others, one inside another
local HELD = 569           -- the held item's place: the game swaps it for the item's skill

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

-- The kinds the game buys and ERASE erases: uses (10) and ranks (20, 30).
local function buyable(id)
  local t = skill_type(id)
  return t == 10 or t == 20 or t == 30
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

local function sorted_keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function find_row(list, id)
  for _, r in ipairs(list or {}) do
    if r.skill == id then return r end
  end
  return nil
end

local function for_sale(list, id)
  local r = find_row(list, id)
  return r ~= nil and r.points > 0, r
end

-- The Boosts: { [skill] = row of rq.chara.boosts }, and whether this world keeps their effect.
local function boost_table(iic)
  local rows, keeps = rq.chara.boosts(iic)
  local by = {}
  for _, b in ipairs(rows) do by[b.skill] = b end
  return by, keeps
end

-- ---- what the character learned ----

-- Whether the game offers a skill the character has with no purchase record: its steps are for
-- sale now, the list names it once it is erased (for sale, or with the game's condition, as Healing 2
-- after Healing 1 is erased), or it is a Boost (the list stops naming a Boost once it is kept).
local function offered(iic, id, from, n, boosts)
  if rq.chara.price(iic, id, from, n) ~= nil then return true end
  if boosts[id] then return true end
  local rows = rq.chara.learnable(iic, { after = { { skill = id, n = 0 } } })
  return find_row(rows, id) ~= nil
end

-- The loadout of the character as it is now: the learned skills, the starting skills erased, the
-- kept Boosts and the hotbar.
local function snapshot(iic)
  local base, base_list = {}, rq.chara.base_skills(iic)
  for _, s in ipairs(base_list) do base[s.id] = s.n end
  local boosts = boost_table(iic)
  local skills, bar, have = {}, {}, {}
  for i = 1, BAR do bar[i] = 0 end
  for _, s in ipairs(rq.chara.slots(iic)) do
    if s.skill > 0 then
      have[s.skill] = true
      if s.bar >= 1 and s.bar <= BAR then bar[s.bar] = s.skill end
      local from = math.min(base[s.skill] or 0, s.n)
      if s.n > from and s.cost ~= -1 then
        if s.cost > 0 or offered(iic, s.skill, from, s.n, boosts) then
          skills[#skills + 1] = { id = s.skill, n = s.n }
        end
      end
    end
  end
  local erased = {}
  for _, s in ipairs(base_list) do
    if not have[s.id] and s.id ~= HELD and buyable(s.id) then erased[#erased + 1] = s.id end
  end
  local kept = {}
  for _, id in ipairs(sorted_keys(boosts)) do
    if boosts[id].kept then kept[#kept + 1] = id end
  end
  return skills, bar, erased, kept
end

local function bad_ids(list, what)
  if list == nil then return nil end
  if type(list) ~= "table" then return "its " .. what .. " list is damaged" end
  for _, id in ipairs(list) do
    if math.type(id) ~= "integer" or id < 1 or id > 1000 then return "its " .. what .. " list is damaged" end
  end
  return nil
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
  local bad = bad_ids(entry.erased, "erased skill") or bad_ids(entry.boosts, "kept Boost")
  if bad then return bad end
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

-- The Boosts a loadout kept without the skill (erased at rank 4) that the character does not keep
-- now, in the order the game sells them (the first of a pair before the second); none in a world
-- that does not keep them. A Boost the loadout has as a skill is one of its skills.
local function boosts_to_rebuild(iic, entry)
  local by, keeps = boost_table(iic)
  local out = {}
  if not keeps then return out end
  local skill = {}
  for _, s in ipairs(entry.skills) do skill[s.id] = true end
  for _, id in ipairs(entry.boosts or {}) do
    if by[id] and not by[id].kept and not skill[id] then out[#out + 1] = id end
  end
  table.sort(out, function(a, b)
    if by[a].step ~= by[b].step then return by[a].step < by[b].step end
    return a < b
  end)
  return out
end

-- ---- planning a load ----

-- The plan of a load: the actions in order ({skill, from, to, points} learns, {skill, forget,
-- back} erases), their price (points), what the mods give back for the erasures (back), the most
-- spent at one time (peak), and counts for the dialogs. nil, why ("skills",
-- "room", "points") and a detail when it cannot be done now.
local function plan_load(iic, entry, with_boosts)
  local P = { entry = entry, actions = {}, points = 0, new = 0, raised = 0, extra = 0, erased = 0,
    boosts = 0, back = 0, peak = 0 }
  local lv, start, rows0 = {}, {}, {}
  for _, s in ipairs(rq.chara.slots(iic)) do
    if s.skill > 0 then
      lv[s.skill] = s.n
      start[s.skill] = s.n
      rows0[s.skill] = s
    end
  end
  local base_n = {}
  for _, s in ipairs(rq.chara.base_skills(iic)) do base_n[s.id] = s.n end
  local paid, fresh = {}, {} -- points paid per skill in the plan; rows the plan made
  local spent = 0            -- the points spent so far, less what came back
  local want = {}
  for _, s in ipairs(entry.skills) do want[s.id] = math.max(want[s.id] or 0, s.n) end
  local drop, helper = {}, {}   -- erase once nothing needs them: lacked by the loadout; on the way
  for _, id in ipairs(entry.erased or {}) do
    if lv[id] and not want[id] and id ~= HELD then drop[id] = true end
  end
  local level = (rq.chara.get(iic) or {}).level or 0
  local after, goals = {}, {}
  local list, room, probes = nil, 0, 0

  -- The list and the free rows after the steps so far, and extra ones.
  local function look(extra)
    probes = probes + 1
    if probes > PROBES then error("more than " .. PROBES .. " tries", 0) end
    local steps = after
    if extra then
      steps = table.move(after, 1, #after, 1, {})
      for _, st in ipairs(extra) do steps[#steps + 1] = st end
    end
    local rows, free = rq.chara.learnable(iic, { after = steps })
    if rows then return rows, free end
    if extra then return nil, 0 end -- a try that needs a row the game has not got: nothing for sale
    error("no row left to try a skill in", 0)
  end

  local function now()
    if not list then list, room = look() end
    return list, room
  end

  local function push(id, n, pts)
    after[#after + 1] = { skill = id, n = n }
    list = nil
    local last = P.actions[#P.actions]
    if n == 0 then
      P.actions[#P.actions + 1] = { skill = id, forget = true, back = pts or 0 }
      lv[id] = nil
    else
      if last and not last.forget and last.skill == id then
        last.to = n
        last.points = last.points + (pts or 0)
      else
        P.actions[#P.actions + 1] = { skill = id, from = lv[id] or 0, to = n, points = pts or 0 }
      end
      lv[id] = n
    end
  end

  -- The purchase record id's row would have now, as rq.chara.learn writes it: a new row the points
  -- paid; a raised one its record plus them (a -1 record becomes them, a 0 one the older steps at
  -- the game's price plus them).
  local function record(id)
    local p = paid[id] or 0
    local r = rows0[id]
    if fresh[id] or not r then return p end
    if p == 0 then return r.cost end
    if r.cost > 0 then return r.cost + p end
    if r.cost == -1 then return p end
    local older, from = 0, base_n[id] or 0
    if r.n > from then older = rq.chara.price(iic, id, from, r.n) or 0 end
    return older + p
  end

  -- What the mods give back when id is erased now, as its row is after the steps so far.
  local function refund(id)
    local n = math.max(lv[id] or 1, 1)
    local by, keeps = boost_table(iic)
    local ok, back = pcall(rq.chara.forget_points, iic, id,
      { player = true, n = n, cost = record(id), kept = keeps and by[id] ~= nil and n >= 4 })
    if not ok then
      rq.log(("%s: what erasing %s gives back: %s"):format(MOD, skill_name(id), tostring(back)))
      return 0
    end
    return back
  end

  local function buy(id, n, pts)
    paid[id] = (paid[id] or 0) + pts
    spent = spent + pts
    if spent > P.peak then P.peak = spent end
    P.points = P.points + pts
    push(id, n, pts)
  end

  local function erase(id, group)
    local back = refund(id)
    P.back = P.back + back
    spent = spent - back
    paid[id], fresh[id] = nil, true
    push(id, 0, back)
    if group then group[id] = nil end
    if group == drop then P.erased = P.erased + 1 end
  end

  -- The skills still to reach: the loadout's and those on the way to one.
  local function pending()
    local out = {}
    for id, n in pairs(want) do
      if (lv[id] or 0) < n then out[id] = true end
    end
    for _, gl in ipairs(goals) do
      if (lv[gl.id] or 0) < gl.n then out[gl.id] = true end
    end
    return out
  end

  -- Whether a skill still to reach needs id: the game's condition names it, or erasing id takes
  -- one of its steps off sale.
  local function needed(id)
    local cur = now()
    local pend = pending()
    for p in pairs(pend) do
      local r = find_row(cur, p)
      for _, q in ipairs(r and r.needs or {}) do
        if q.id == id then return true end
      end
    end
    local without = look({ { skill = id, n = 0 } })
    for p in pairs(pend) do
      if for_sale(cur, p) and not for_sale(without, p) then return true end
    end
    return false
  end

  -- Frees a row: a skill learned only on the way, then a starting skill the loadout lacks, that
  -- nothing still to come needs.
  local function make_room()
    for _, group in ipairs({ helper, drop }) do
      for _, id in ipairs(sorted_keys(group)) do
        if lv[id] and not needed(id) then
          erase(id, group)
          return true
        end
      end
    end
    return false
  end

  -- When the game's condition names nothing the character lacks (or the list does not show the
  -- skill at all, as the second Attack Boost until the first is at rank 4): the one skill whose
  -- level puts id up for sale, tried at its top level, then from its level now up. A Boost's first
  -- of the pair, then a skill of the same name, then the loadout's skills, then the list's.
  local function unlock(id)
    local cur = now()
    local tried, order = { [id] = true }, {}
    local function add(c)
      if c and not tried[c] then
        tried[c] = true
        order[#order + 1] = c
      end
    end
    local boosts = boost_table(iic)
    if boosts[id] then add(boosts[id].first) end
    local name = skill_name(id)
    for _, r in ipairs(cur) do
      if skill_name(r.skill) == name then add(r.skill) end
    end
    for _, s in ipairs(entry.skills) do add(s.id) end
    for _, r in ipairs(cur) do add(r.skill) end
    for _, c in ipairs(order) do
      local t = skill_type(c)
      local top = (t == 20 or t == 30) and 4 or 9
      local from = lv[c] or 0
      if buyable(c) and from < top and for_sale(look({ { skill = c, n = top } }), id) then
        for k = from + 1, top do
          if k == top or for_sale(look({ { skill = c, n = k } }), id) then return { id = c, n = k } end
        end
      end
    end
    return nil
  end

  -- What id lacks to be for sale: { {id, n} }, or nil, why and the game's text.
  local function lacks(id, r)
    if r and r.level and level < r.level then return nil, "condition", r.why end
    local out = {}
    for _, q in ipairs(r and r.needs or {}) do
      if (lv[q.id] or 0) < q.n then out[#out + 1] = q end
    end
    if #out > 0 then return out end
    local u = unlock(id)
    if u then return { u } end
    if r then return nil, "condition", r.why end
    return nil, "not sold"
  end

  -- Raises id to n, step by step at the list's price, reaching what it needs first.
  local function reach(id, n, depth)
    if (lv[id] or 0) >= n then return true end
    if depth > DEPTH then return false, { id = id, why = "condition", text = "too many skills on the way" } end
    goals[#goals + 1] = { id = id, n = n }
    local ok, err = true, nil
    local turns = 0
    while ok and (lv[id] or 0) < n do
      turns = turns + 1
      if turns > 200 then
        ok, err = false, { id = id, why = "condition", text = "no way found" }
        break
      end
      local cur, free = now()
      local sale, r = for_sale(cur, id)
      if sale then
        if not lv[id] and free < 1 then
          if make_room() then goto again end -- the list is read again after the erase
          error({ no_room = id }, 0) -- the plan stops here; plan_load counts the rows
        end
        buy(id, (lv[id] or 0) + (r.step or 1), r.points)
      else
        local need, why, text = lacks(id, r)
        if not need then
          ok, err = false, { id = id, why = why, text = text }
        else
          local mark = #after
          for _, q in ipairs(need) do
            local had = lv[q.id]
            local ok2, e2 = reach(q.id, q.n, depth + 1)
            if not ok2 then
              ok, err = false, e2
              break
            end
            if not had and not want[q.id] and not helper[q.id] then
              helper[q.id] = true
              P.extra = P.extra + 1
            end
          end
          if ok and #after == mark then
            ok, err = false, { id = id, why = r and "condition" or "not sold", text = r and r.why }
          end
        end
      end
      ::again::
    end
    table.remove(goals)
    return ok, err
  end

  -- One skill of the loadout (or a kept Boost): reached, or left out of the plan with its reason.
  local cannot = {}
  local function attempt(id, n)
    local last = P.actions[#P.actions]
    local keep = {
      after = #after, actions = #P.actions, points = P.points, extra = P.extra,
      erased = P.erased, last_to = last and last.to, last_points = last and last.points,
      back = P.back, peak = P.peak, spent = spent,
      lv = {}, helper = {}, drop = {}, paid = {}, fresh = {},
    }
    for k, v in pairs(lv) do keep.lv[k] = v end
    for k in pairs(helper) do keep.helper[k] = true end
    for k in pairs(drop) do keep.drop[k] = true end
    for k, v in pairs(paid) do keep.paid[k] = v end
    for k in pairs(fresh) do keep.fresh[k] = true end
    local ok, err = reach(id, n, 0)
    if ok then return true end
    for i = #after, keep.after + 1, -1 do after[i] = nil end
    for i = #P.actions, keep.actions + 1, -1 do P.actions[i] = nil end
    last = P.actions[#P.actions]
    if last then last.to, last.points = keep.last_to, keep.last_points end
    P.points, P.extra, P.erased = keep.points, keep.extra, keep.erased
    P.back, P.peak, spent = keep.back, keep.peak, keep.spent
    lv, helper, drop, paid, fresh = keep.lv, keep.helper, keep.drop, keep.paid, keep.fresh
    list = nil
    if err.id ~= id then
      err.via, err.id = err.id, id
    end
    err.text = why_text(err.why, err.text)
    cannot[#cannot + 1] = err
    return false
  end

  local ran, stop = pcall(function()
    if with_boosts then
      for _, id in ipairs(boosts_to_rebuild(iic, entry)) do
        if attempt(id, 4) then
          P.boosts = P.boosts + 1
          helper[id] = nil
          erase(id)
        end
      end
    end
    for _, s in ipairs(entry.skills) do attempt(s.id, s.n) end
    for _, group in ipairs({ helper, drop }) do
      for _, id in ipairs(sorted_keys(group)) do
        if lv[id] then erase(id, group) end
      end
    end
  end)
  if not ran then
    if type(stop) ~= "table" or not stop.no_room then error(stop, 0) end
    -- No row for a new skill and nothing to erase: that skill and each of the loadout's skills
    -- the character still lacks needs one (at least: skills on the way to them may need more).
    local short = (want[stop.no_room] or lv[stop.no_room]) and 0 or 1
    for id in pairs(want) do
      if not lv[id] then short = short + 1 end
    end
    short = math.max(short, 1)
    local have = rq.chara.skill_room(iic)
    return nil, "room", { short = short, have = have, need = have + short }
  end

  for _, s in ipairs(entry.skills) do
    local from = start[s.id] or 0
    if from < s.n and (lv[s.id] or 0) >= s.n then
      if from == 0 then P.new = P.new + 1 else P.raised = P.raised + 1 end
    end
  end
  P.probes = probes
  if #cannot > 0 then return nil, "skills", cannot end
  local free = rq.chara.skill_points(iic)
  if P.peak > free then return nil, "points", { need = P.peak, have = free, back = P.back } end
  return P
end

-- What a load would do (plan_load's plan), or nil, why ("free", "bad", "plan", "skills", "room",
-- "points") and a detail. opts.boosts = false leaves the kept Boosts out.
local function check(iic, slot, opts)
  local entry = get(iic, slot)
  if not entry then return nil, "free" end
  local bad = invalid(entry)
  if bad then return nil, "bad", bad end
  local with_boosts = not (opts and opts.boosts == false)
  local ok, plan, why, detail = pcall(plan_load, iic, entry, with_boosts)
  if not ok and tostring(plan):find("no row left", 1, true) then
    local have = rq.chara.skill_room(iic)
    return nil, "room", { short = 1, have = have, need = have + 1 }
  end
  if not ok then
    rq.log(("%s: slot %s of character %d could not be worked out: %s"):format(MOD, slot, iic, tostring(plan)))
    return nil, "plan", tostring(plan)
  end
  return plan, why, detail
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
  local skills, bar, erased, boosts = snapshot(iic)
  local old = get(iic, slot)
  name = name or (old and type(old.name) == "string" and old.name ~= "" and old.name) or ("Loadout " .. slot)
  local entry = { name = name, skills = skills, bar = bar, erased = erased, boosts = boosts }
  put(iic, slot, entry)
  rq.log(("%s: saved slot %s of character %d: %d skill(s), %d erased, %d kept Boost(s)"):format(MOD,
    slot, iic, #skills, #erased, #boosts))
  return entry
end

-- Runs a plan: true and what it did, or false, "refused" and what it did when the game refused a
-- step (the steps before it stay done).
local function run(iic, slot, plan)
  local done = { learned = 0, erased = 0, points = 0, back = 0 }
  local function finish()
    rq.chara.recalc(iic)
    done.placed = put_bar(iic, plan.entry.bar)
    rq.statuspage.refresh()
  end
  for _, a in ipairs(plan.actions) do
    if a.forget then
      -- The player's erasure: a mod that pays back ERASE pays it back (the third value).
      local _, _, back = rq.chara.forget(iic, a.skill, { player = true })
      done.back = done.back + (back or 0)
      done.erased = done.erased + 1
    else
      local ok, spent, more = rq.chara.learn(iic, a.skill, { to = a.to })
      if not ok then
        rq.log(("%s: %s of character %d stopped at %s: %s"):format(MOD, slot, iic, skill_name(a.skill),
          tostring(spent)))
        done.failed = { id = a.skill, why = spent, text = why_text(spent, more) }
        finish()
        return false, "refused", done
      end
      done.learned = done.learned + 1
      done.points = done.points + spent
    end
  end
  finish()
  rq.log(("%s: loaded slot %s of character %d: %d purchase(s) for %d point(s), %d erased (%d point(s) back), %d hotbar place(s)"):format(
    MOD, slot, iic, done.learned, done.points, done.erased, done.back, done.placed))
  return true, done
end

-- Loads a slot: true and what it did, or false and check's why and detail ("refused" when the
-- game refused a step: the steps before it stay done). opts.boosts = false leaves the kept Boosts
-- out.
local function load(iic, slot, opts)
  local plan, why, detail = check(iic, slot, opts)
  if not plan then return false, why, detail end
  return run(iic, slot, plan)
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
  local lines = {}
  if #entry.skills == 0 then lines[1] = "No learned skills; only the hotbar." end
  for i, s in ipairs(entry.skills) do
    if i > most then
      lines[#lines + 1] = "... and " .. (#entry.skills - most) .. " more"
      break
    end
    lines[#lines + 1] = skill_name(s.id) .. " (" .. level_text(s.id, s.n) .. ")"
  end
  local more = {}
  if entry.erased and #entry.erased > 0 then
    more[#more + 1] = plural(#entry.erased, "starting skill", "starting skills") .. " erased"
  end
  if entry.boosts and #entry.boosts > 0 then
    more[#more + 1] = plural(#entry.boosts, "kept Boost", "kept Boosts")
  end
  if #more > 0 then lines[#lines + 1] = table.concat(more, ", ") .. "." end
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
      local text = why_text(c.why, c.text)
      if c.via then text = "needs " .. skill_name(c.via) .. ": " .. text end
      lines[#lines + 1] = skill_name(c.id) .. ": " .. text
    end
    return table.concat(lines, "\n")
  end
  if why == "points" then
    if (detail.back or 0) > 0 then
      return ("%s needs %d skill points before the skills it erases\ngive %d back; %s has %d.\n%s more needed."):format(
        name, detail.need, detail.back, short_name(iic), detail.have,
        plural(detail.need - detail.have, "point is", "points are"))
    end
    return ("%s costs %d skill points; %s has %d.\n%s more needed."):format(name, detail.need,
      short_name(iic), detail.have, plural(detail.need - detail.have, "point is", "points are"))
  end
  if why == "room" then
    local rows = "more free skill rows"
    if detail.short > 0 then rows = plural(detail.short, "more free skill row", "more free skill rows") end
    return ("%s needs %s for %s.\nERASE skills to make room."):format(short_name(iic), rows, name)
  end
  if why == "plan" then
    return name .. " could not be worked out:\n" .. tostring(detail)
  end
  return name .. " cannot be loaded now."
end

-- What a plan does, in a few words: "learns 8 skills, raises 1 and erases 6".
local function plan_text(plan)
  local parts = {}
  if plan.new > 0 then parts[#parts + 1] = "learns " .. plural(plan.new, "skill", "skills") end
  if plan.raised > 0 then parts[#parts + 1] = "raises " .. plural(plan.raised, "skill", "skills") end
  if plan.boosts > 0 then parts[#parts + 1] = "rebuilds " .. plural(plan.boosts, "kept Boost", "kept Boosts") end
  if plan.erased > 0 then parts[#parts + 1] = "erases " .. plural(plan.erased, "starting skill", "starting skills") end
  if #parts == 0 then return "sets the hotbar" end
  if #parts == 1 then return parts[1] end
  return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

local function on_the_way(plan)
  if plan.extra == 0 then return "" end
  return "\n" .. plural(plan.extra, "skill is", "skills are") .. " learned on the way and erased after."
end

-- A plan's price: "for 103 skill points. Crook has 120.", and what the mods give back for its
-- erasures on a line of its own.
local function price_text(iic, plan)
  local s = ("for %s. %s has %d."):format(plural(plan.points, "skill point", "skill points"),
    short_name(iic), rq.chara.skill_points(iic))
  if plan.back > 0 then
    s = s .. ("\nThe skills it erases give %d back: %d in all."):format(plan.back, plan.points - plan.back)
  end
  return s
end

-- What a load did, for the notice after it: "5 skills learned, 1 raised and ..." (two lines at most
-- in the notice's first box; the skills on the way are a sentence of their own after it).
local function done_text(plan)
  local parts = {}
  if plan.new > 0 then parts[#parts + 1] = plural(plan.new, "skill learned", "skills learned") end
  if plan.raised > 0 then
    parts[#parts + 1] = plan.new > 0 and (plan.raised .. " raised")
      or plural(plan.raised, "skill raised", "skills raised")
  end
  if plan.boosts > 0 then parts[#parts + 1] = plural(plan.boosts, "kept Boost rebuilt", "kept Boosts rebuilt") end
  if plan.erased > 0 then
    parts[#parts + 1] = plural(plan.erased, "starting skill erased", "starting skills erased")
  end
  if #parts == 0 then return "The hotbar is set" end
  if #parts == 1 then return parts[1] end
  return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
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

local function do_run(iic, slot, entry, plan)
  local ok, done, more = run(iic, slot, plan)
  if ok then
    if #plan.actions == 0 then
      rq.ui.notice(("%s is loaded: nothing to learn, the hotbar is set."):format(quote(entry)))
    else
      local way = plan.extra > 0 and ("\n" .. plural(plan.extra, "skill was", "skills were")
        .. " learned on the way and erased.") or ""
      local price = plural(done.points, "skill point", "skill points")
      if done.back > 0 then
        price = ("%s\n(%d spent, %d back for the erased skills)"):format(
          plural(done.points - done.back, "skill point", "skill points"), done.points, done.back)
      end
      rq.ui.notice(("%s is loaded for %s.\n%s.%s"):format(quote(entry), price, done_text(plan), way))
    end
  else
    rq.ui.notice(("Loading %s stopped at %s: %s.\nThe steps before it are done."):format(quote(entry),
      skill_name(more.failed.id), more.failed.text))
  end
end

-- A plan's row in the menu that offers the kept Boosts.
local function plan_row(iic, entry, id, text, plan, why, detail)
  local comment
  if plan then
    comment = ("It %s %s%s"):format(plan_text(plan), price_text(iic, plan), on_the_way(plan))
  else
    comment = refusal(iic, entry, why, detail)
  end
  return { id = id, text = text, comment = comment }
end

local function do_load(iic, slot)
  local entry = get(iic, slot)
  local lean, why, detail = check(iic, slot, { boosts = false })
  if not lean then
    rq.ui.notice(refusal(iic, entry, why, detail))
    return slot_menu(iic, slot)
  end
  local rebuild = #boosts_to_rebuild(iic, entry) > 0
  if rebuild then
    local full, fwhy, fdetail = check(iic, slot)
    local rows = {
      plan_row(iic, entry, "all", "Load with the kept Boosts", full, fwhy, fdetail),
      plan_row(iic, entry, "skills", "Load the skills only", lean, why, detail),
    }
    return rq.ui.choose(rows, function(id)
      if id == 0 then return slot_menu(iic, slot) end
      if rq.statuspage.chara() ~= iic then return end
      local plan, pwhy, pdetail = full, fwhy, fdetail
      if id == "skills" then plan, pwhy, pdetail = lean, why, detail end
      if not plan then
        rq.ui.notice(refusal(iic, entry, pwhy, pdetail))
        return slot_menu(iic, slot)
      end
      do_run(iic, slot, entry, plan)
    end, {
      message = ("%s kept %s.\nRebuild their lasting effects too?"):format(
        quote(entry), plural(#boosts_to_rebuild(iic, entry), "Boost", "Boosts")),
      back = "Back",
    })
  end
  if #lean.actions > 0 then
    local text = ("Load %s?\nIt %s\n%s%s"):format(quote(entry), plan_text(lean), price_text(iic, lean),
      on_the_way(lean))
    if not rq.ui.confirm(text, { remember = "load", remember_label = "Loading a loadout" }) then
      return slot_menu(iic, slot)
    end
  end
  do_run(iic, slot, entry, lean)
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
      { id = "load", text = "Load Loadout", comment = "Learn what is missing at the game's price, with the skills it needs on the way, erase what the loadout lacks, then set the hotbar.\n\n" .. summary(entry, 4) },
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
  boosts_to_rebuild = boosts_to_rebuild,
  save = save,
  load = load,
  rename = rename,
  wipe = wipe,
  put = put, -- writes a slot's data as it is: for tests of damaged data
  bar_size = bar_size,
  prompt = function() return prompt end,
}
