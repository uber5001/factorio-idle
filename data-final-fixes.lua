-- IdleX100: prototype adjustments
local SCALE = 100
local SPOIL_SCALE = 10  -- only used in runtime via difficulty settings
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
  return {type = x.type or "item", name = x[1], amount = x[2], fluidbox_index = x[3]}
end

-- Build the set of “final products”.
local FINAL = {}
local function mark_final(name) if name then FINAL[name] = true end end

local item_types = {
  "item", "item-with-entity-data", "module", "armor", "capsule", "repair-tool",
  "tool", "item-with-tags", "item-with-inventory", "item-with-label", "rail-planner"
}

local function scan_items(tbl)
  if not tbl then return end
  for name, proto in pairs(tbl) do
    if proto.place_result or proto.place_as_tile then
      FINAL[name] = true
    end
  end
end

for _, t in pairs(item_types) do scan_items(data.raw[t]) end
mark_final("cliff-explosives")

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

-- Rockets: treat rocket parts as final so rockets cost/time scale properly
mark_final("rocket-part")

-- Ensure key categories are final even if not placeable
for name in pairs(data.raw.armor or {}) do mark_final(name) end
for name in pairs(data.raw.module or {}) do mark_final(name) end
for name in pairs(data.raw.gun or {}) do mark_final(name) end

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

-- Increase rocket cargo inventory size if present on prototypes
for _, s in pairs(data.raw["rocket-silo"] or {}) do
  if s.to_be_inserted_to_rocket_inventory_size then
    s.to_be_inserted_to_rocket_inventory_size = math.floor(s.to_be_inserted_to_rocket_inventory_size * SCALE)
  end
  if s.result_inventory_size then
    s.result_inventory_size = math.floor(s.result_inventory_size * SCALE)
  end
end
for _, r in pairs(data.raw["rocket-silo-rocket"] or {}) do
  if r.inventory_size then r.inventory_size = math.floor(r.inventory_size * SCALE) end
  if r.rocket_inventory_size then r.rocket_inventory_size = math.floor(r.rocket_inventory_size * SCALE) end
  if r.cargo_inventory_size then r.cargo_inventory_size = math.floor(r.cargo_inventory_size * SCALE) end
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
  if r.result then return {{type = "item", name = r.result, amount = r.result_count or 1}} end
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
for _, t in pairs({"locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon"}) do
  for _, e in pairs(data.raw[t] or {}) do x100_health(e) end
end

-- 2) Buildings (exclude vehicles/units/resources/trees/naturals)
local EXCLUDE_TYPES = {
  car=true, ["spider-vehicle"]=true, unit=true, resource=true, tree=true,
  ["locomotive"]=true, ["cargo-wagon"]=true, ["fluid-wagon"]=true, ["artillery-wagon"]=true
}
for type_name, list in pairs(data.raw) do
  if type(list)=="table" and not EXCLUDE_TYPES[type_name] then
    for _, e in pairs(list) do
      if e and e.max_health and not e.autoplace then x100_health(e) end
    end
  end
end

-- 2b) Enemy spawners and worm turrets are buildings; ensure they are scaled
for _, e in pairs(data.raw["unit-spawner"] or {}) do x100_health(e) end
for _, e in pairs(data.raw["turret"] or {}) do
  if e.type == "turret" and (e.subgroup == "enemies" or (e.flags and table.concat(e.flags, ","):find("not-blueprintable") )) then
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
  if type(list)=="table" then
    for name, e in pairs(list) do
      if e and e.autoplace and e.minable and name ~= "pentapod-shell" then
        if e.type ~= "resource" then
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

-- Set rocket lift weight ×100 in utility-constants (leave default_item_weight unchanged)
local uc_tbl = data.raw["utility-constants"]
local uc = uc_tbl and uc_tbl["default"]
if uc then
  uc.rocket_lift_weight = (uc.rocket_lift_weight or 1) * SCALE
end

-- (Removed) Infinite resource depletion adjustment; richness is scaled at runtime and
-- pumpjacks are slower, so depletion proceeds ~100× slower naturally.