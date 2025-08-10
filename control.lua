-- IdleX100: runtime behaviors
local SCALE = 100
local SPOIL_SLOW = 10
local MAX_RESOURCE_AMOUNT = 4294967295 -- engine limit for resource entity amount

local function apply_map_settings()
  local ms = game.map_settings
  -- Evolution 100× slower (time, pollution, but not by-destroying)
  ms.enemy_evolution.time_factor      = ms.enemy_evolution.time_factor / SCALE
  ms.enemy_evolution.pollution_factor = ms.enemy_evolution.pollution_factor / SCALE
  -- ms.enemy_evolution.destroy_factor   = ms.enemy_evolution.destroy_factor / SCALE
  -- Disable expansion entirely
  ms.enemy_expansion.enabled = false
end

local function apply_difficulty_settings()
  -- Science cost ×100, research time unchanged
  game.difficulty_settings.technology_price_multiplier = 100
  -- Spoilage 10× slower (multiply spoil time)
  local old = game.difficulty_settings.spoil_time_modifier or 1
  game.difficulty_settings.spoil_time_modifier = math.min(100, old * SPOIL_SLOW)
  -- note: rocket_lift_weight is a prototype (utility-constants) and is set in data stage
end

-- Make existing & future finite ore fields ~100× richer
local processed_chunks = {} -- set of "surface#x:y"

local function key(si, cx, cy) return si .. "#" .. cx .. ":" .. cy end

local function scale_resource_entity(e)
  -- Scale both finite and infinite resource entity amounts (initial richness), clamp to engine max
  if e.amount and e.amount > 0 then
    local threshold = math.floor(MAX_RESOURCE_AMOUNT / SCALE)
    if e.amount > threshold then
      e.amount = MAX_RESOURCE_AMOUNT
    else
      e.amount = math.floor(e.amount * SCALE)
      if e.amount < 1 then e.amount = 1 end
    end
  end
end

local function scale_chunk(surface, c)
  local k = key(surface.index, c.x, c.y)
  if processed_chunks[k] then return end
  local area = {left_top = {x = c.x * 32, y = c.y * 32}, right_bottom = {x = (c.x+1) * 32, y = (c.y+1) * 32}}
  for _, e in ipairs(surface.find_entities_filtered{area = area, type = "resource"}) do
    scale_resource_entity(e)
  end
  processed_chunks[k] = true
end

local function scale_all_existing()
  for _, s in pairs(game.surfaces) do
    for c in s.get_chunks() do scale_chunk(s, c) end
  end
end

script.on_init(function()
  storage.idlex100_applied = true
  apply_map_settings()
  apply_difficulty_settings()
  scale_all_existing()
end)

script.on_configuration_changed(function()
  if not storage.idlex100_applied then
    apply_map_settings()
    apply_difficulty_settings()
    scale_all_existing()
    storage.idlex100_applied = true
  end
end)

script.on_event(defines.events.on_chunk_generated, function(ev)
  scale_chunk(ev.surface, ev.position)
end)

-- Optional: remote command to re-run richening if needed
remote.add_interface("IdleX100", {
  rerich = function()
    processed_chunks = {}
    scale_all_existing()
  end
})