-- IdleX100: prototype adjustments
local SCALE = 100
local SPOIL_SCALE = 10   -- only used in runtime via difficulty settings
local MAX_AMOUNT = 65535 -- engine limit for amount fields

-- --- helpers ---------------------------------------------------------------
local function multiply_amount_fields(p, mul)
  mul = mul or SCALE
  if p.amount then p.amount = math.max(1, math.min(MAX_AMOUNT, math.floor(p.amount * mul))) end
  if p.amount_min then p.amount_min = math.max(1, math.min(MAX_AMOUNT, math.floor(p.amount_min * mul))) end
  if p.amount_max then p.amount_max = math.max(1, math.min(MAX_AMOUNT, math.floor(p.amount_max * mul))) end
  if p.catalyst_amount then p.catalyst_amount = math.max(0, math.min(MAX_AMOUNT, math.floor(p.catalyst_amount * mul))) end
end

local function normalize_ingredient(x)
  if x.name then return x end
  -- short form {name, amount}
  return { type = x.type or "item", name = x[1], amount = x[2], fluidbox_index = x[3] }
end

-- Build the set of “final products”.
local FINAL = {}
local function mark_final(name) if name then FINAL[name] = true end end

local item_types = {
  "item", "item-with-entity-data", "module", "armor", "capsule", "repair-tool",
  "tool", "item-with-tags", "item-with-inventory", "item-with-label", "rail-planner", "ammo"
}

mark_final("cliff-explosives")
mark_final("construction-robot")
mark_final("logistic-robot")

-- Equipment items: mark any equipment prototype names (they all have a `shape` field)
for type_name, list in pairs(data.raw) do
  if type(list) == "table" then
    for name, proto in pairs(list) do
      if type(proto) == "table" and proto.shape then
        mark_final(name)
      end
    end
  end
end

-- Ensure key categories are final even if not placeable
for name in pairs(data.raw.armor or {}) do mark_final(name) end
for name in pairs(data.raw.module or {}) do mark_final(name) end
for name in pairs(data.raw.gun or {}) do mark_final(name) end
for name in pairs(data.raw["item-with-entity-data"] or {}) do mark_final(name) end

-- Capture bot rockets: treat as final (explicitly detect capture-themed rockets)
for name in pairs(data.raw.ammo or {}) do
  if string.find(name, "capture", 1, true) and string.find(name, "rocket", 1, true) then
    mark_final(name)
  end
end

-- Land mines are temporary: do NOT consider them final
FINAL["land-mine"] = nil

local function is_final_item(name) return FINAL[name] == true end

-- Scale custom item weights for finals (leave default_item_weight unchanged)
for _, t in pairs(item_types) do
  for name, proto in pairs(data.raw[t] or {}) do
    if is_final_item(name) and proto.weight then
      proto.weight = proto.weight * SCALE
    end
  end
end

-- Scale stack sizes for all items ×100 (skip not-stackable and finals)
local function has_flag(flags, name)
  if not flags then return false end
  for _, f in pairs(flags) do if f == name then return true end end
  return false
end
for _, t in pairs(item_types) do
  for name, proto in pairs(data.raw[t] or {}) do
    if has_flag(proto.flags, "not-stackable") or is_final_item(name) then
      if has_flag(proto.flags, "not-stackable") then proto.stack_size = 1 end
    elseif proto.stack_size then
      proto.stack_size = math.max(1, math.floor((proto.stack_size or 1) * SCALE))
    end
  end
end

-- Decide if a recipe involves any final-products on either side.
local function list_has_final(list)
  if not list then return false end
  for _, e in pairs(list) do
    local x = normalize_ingredient(e)
    if (x.type or "item") == "item" and is_final_item(x.name) then return true end
  end
  return false
end

local function get_products(r)
  if r.results then return r.results end
  if r.result then return { { type = "item", name = r.result, amount = r.result_count or 1 } } end
  return nil
end

local function scale_recipe_block(r)
  local ings = r.ingredients
  local prods = get_products(r)
  local involves_final = list_has_final(ings) or list_has_final(prods)
  if not involves_final then return end

  -- Scale non-final ingredients (and all fluids)
  if ings then
    local out = {}
    for i, e in pairs(ings) do
      local x = normalize_ingredient(e)
      local t = x.type or "item"
      if t == "item" then
        if not is_final_item(x.name) then
          multiply_amount_fields(x, SCALE)
        end
      elseif t == "fluid" then
        multiply_amount_fields(x, SCALE)
      end
      out[i] = x
    end
    r.ingredients = out
  end

  -- Scale non-final products (and all fluids)
  prods = get_products(r)
  if prods then
    for _, p in pairs(prods) do
      local t = p.type or "item"
      if t == "item" then
        if not is_final_item(p.name) then
          multiply_amount_fields(p, SCALE)
        end
      elseif t == "fluid" then
        multiply_amount_fields(p, SCALE)
      end
    end
    r.results = prods; r.result = nil; r.result_count = nil
  end

  -- Scale craft time
  r.energy_required = (r.energy_required or 0.5) * SCALE
end

-- Apply to all recipes (including normal/expensive)
for name, rec in pairs(data.raw.recipe) do
  if rec.normal or rec.expensive then
    if rec.normal then scale_recipe_block(rec.normal) end
    if rec.expensive then scale_recipe_block(rec.expensive) end
  else
    scale_recipe_block(rec)
  end
end

-- Entity HP scaling --------------------------------------------------------
local function x100_health(e)
  if e and e.max_health then e.max_health = math.floor(e.max_health * SCALE) end
end

-- 1) Trains only (locos & wagons)
for _, t in pairs({ "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon", "car", "spider-vehicle" }) do
  for _, e in pairs(data.raw[t] or {}) do x100_health(e) end
end

-- 2) Buildings (exclude vehicles/units/resources/trees/naturals)
local EXCLUDE_TYPES = {
  car = true,
  ["spider-vehicle"] = true,
  unit = true,
  resource = true,
  tree = true,
  plant = true,
  ["land-mine"] = true,
  ["locomotive"] = true,
  ["cargo-wagon"] = true,
  ["fluid-wagon"] = true,
  ["artillery-wagon"] = true
}
for type_name, list in pairs(data.raw) do
  if type(list) == "table" and not EXCLUDE_TYPES[type_name] then
    for _, e in pairs(list) do
      if e and e.max_health and not e.autoplace then x100_health(e) end
    end
  end
end

-- 2b) Enemy spawners and worm turrets are buildings; ensure they are scaled
for _, e in pairs(data.raw["unit-spawner"] or {}) do x100_health(e) end
for _, e in pairs(data.raw["turret"] or {}) do
  if e.type == "turret" and (e.subgroup == "enemies" or (e.flags and table.concat(e.flags, ","):find("not-blueprintable"))) then
    x100_health(e)
  end
end

-- 3) Naturals that spawn on the map (trees, ruins, etc.)
--    HP ×100; keep mining time and ore drop scaling off for resources.
local function scale_minable_results(minable)
  if not minable then return end
  if minable.results then
    for _, r in pairs(minable.results) do
      if (r.type or "item") == "item" and not is_final_item(r.name) then
        multiply_amount_fields(r, SCALE)
      end
    end
  elseif minable.result and not is_final_item(minable.result) then
    minable.count = (minable.count or 1) * SCALE
  end
end

for type_name, list in pairs(data.raw) do
  if type_name ~= "resource" and type_name ~= "plant" and type(list) == "table" then
    for name, e in pairs(list) do
      if e and e.autoplace and e.minable and name ~= "pentapod-shell" then
        if e.type ~= "resource" and e.type ~= "plant" then
          if e.max_health then e.max_health = math.floor(e.max_health * SCALE) end
          if e.minable.mining_time then e.minable.mining_time = (e.minable.mining_time or 0.1) * SCALE end
          scale_minable_results(e.minable)
        else
          -- do not slow ore mining; leave mining_time and drops unchanged for resources
        end
      end
    end
  end
end

-- Demolishers (Space Age enemy): give them 100× HP specifically
for name, u in pairs(data.raw.unit or {}) do
  if u.max_health and string.find(name, "demolisher", 1, true) then x100_health(u) end
end

-- Slow pumpjacks (fluid mining drills) by 100×
local function is_fluid_drill(d)
  if d.output_fluid_box then return true end
  if d.resource_categories then
    for _, cat in pairs(d.resource_categories) do
      if cat == "basic-fluid" or cat == "lithium-brine" then return true end
    end
  end
  return false
end

for name, d in pairs(data.raw["mining-drill"] or {}) do
  if is_fluid_drill(d) then
    d.mining_speed = (d.mining_speed or 1) / SCALE
  end
end

-- Simple placeable_by handling: if missing, add same-name item with count=1, then scale counts ×SCALE
local function scale_pb_counts(pb)
  if type(pb) ~= "table" then error() end
  if pb[1] and type(pb[1]) == "table" and pb[1].item then
    for _, entry in ipairs(pb) do
      entry.count = math.max(1, math.floor((entry.count or 1) * SCALE))
    end
  elseif pb.item then
    pb.count = math.max(1, math.floor((pb.count or 1) * SCALE))
  end
end

-- Entities
-- for name, e in pairs(data.raw or {}) do end
for type_name, list in pairs(data.raw) do
  for name, e in pairs(list) do
    if e and name ~= "construction-robot" and name ~= "logistic-robot" and name ~= "land-mine" then
      if name == "rail-ramp" then
        e.placeable_by = { { item = "rail-ramp", count = 1 } }
      elseif name == "stone-path" or name == "frozen-stone-path" then
        -- there's a more robust way to handle this using place_as_tile, but this works for now
        e.placeable_by = { { item = "stone-brick", count = 1 } }
      elseif not e.placeable_by and data.raw.item[name] then
        e.placeable_by = { { item = name, count = 1 } }
      end
      if e.placeable_by then
        scale_pb_counts(e.placeable_by)
        if e and e.minable then e.__idlex100_was_minable = true end
      end
    end
  end
end


-- Ensure mined return matches placeable_by counts (so you get back what you place ×SCALE)
local function ensure_minable_return(ent, item_name, count)
  if not ent or not ent.__idlex100_was_minable then return end
  ent.minable = ent.minable or { mining_time = 0.2 }
  local m = ent.minable
  if m.results then
    local found = false
    for _, r in pairs(m.results) do
      if (r.type or "item") == "item" and r.name == item_name then
        r.amount = count
        r.amount_min = nil; r.amount_max = nil
        found = true
        break
      end
    end
    if not found then
      table.insert(m.results, { type = "item", name = item_name, amount = count })
    end
    m.result = nil; m.count = nil
  elseif m.result then
    if m.result == item_name then
      m.results = { { type = "item", name = item_name, amount = count } }
      m.result = nil; m.count = nil
    else
      m.results = {
        { type = "item", name = m.result,  amount = m.count or 1 },
        { type = "item", name = item_name, amount = count }
      }
      m.result = nil; m.count = nil
    end
  else
    m.results = { { type = "item", name = item_name, amount = count } }
  end
end

-- Apply minable return only to entities that were already minable in vanilla
for type_name, list in pairs(data.raw) do
  if type_name ~= "resource" and type_name ~= "plant" and type(list) == "table" then
    for _, e in pairs(list) do
      local pb = e and e.placeable_by
      if e and e.__idlex100_was_minable and pb then
        if pb[1] and type(pb[1]) == "table" and pb[1].item then
          for _, entry in ipairs(pb) do
            ensure_minable_return(e, entry.item, entry.count or 1)
          end
        elseif pb.item then
          ensure_minable_return(e, pb.item, pb.count or 1)
        end
      end
    end
  end
end

-- nerf cargo-wagon
data.raw["cargo-wagon"]["cargo-wagon"].inventory_size = 1
data.raw["character-corpse"]["character-corpse"].time_to_live = data.raw["character-corpse"]["character-corpse"]
    .time_to_live * 1000
