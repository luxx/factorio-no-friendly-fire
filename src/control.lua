-- luacheck: globals game script defines global

-- config loading
global.dtms = global.dtms or {}
global.dtms.config = global.dtms.config or {}

require("config")

-- global state
if not global.dtms.locked_entity_ids then global.dtms.locked_entity_ids = {} end -- the player's locked entities

local function log(str)
    if global.dtms.config and global.dtms.config.debug_logging then
	    game.players[1].print( "[" .. game.tick .. "] " .. tostring(str))
    end
end

-- Return a string representing the unique entity id.
-- https://forums.factorio.com/viewtopic.php?f=25&t=32860&sid=a116fe079b1b058b91d496056a1b4fbe
local function entity_id(entity)
    -- note: we return 'ignore' if not able to supply decent entity id
    -- this avoids calling code breaking if using the id as table key
    -- might lead to some minor cruft, but nothing worth worrying about
    if not entity or not entity.valid or not entity.unit_number then return 'ignore' end
    return entity.unit_number
end

local function lock_entity(entity)
    -- TODO: check entity isn't already locked
    --       when locking record current state, so that it can be restored properly later

    -- log("Entity Locked: " .. entity_id(entity) .. " (" .. entity.name .. ")")
    global.dtms.locked_entity_ids[entity_id(entity)] = true

    if global.dtms.config then
        if not global.dtms.config.allow_rotate then entity.minable = false end
        if not global.dtms.config.allow_mining then entity.rotatable = false end
        if not global.dtms.config.allow_shooting then entity.destructible = false end
    end
end

local function unlock_entity(entity)
    -- TODO: check entity isn't already unlocked
    --       when unlocking, restore to previous state rather than hard-coded values

    if(global.dtms.locked_entity_ids[entity_id(entity)]) then
        log("Entity Unlocked: " .. entity_id(entity) .. " (" .. entity.name .. ")")
        if global.dtms.config and not global.dtms.config.allow_rotate then entity.minable = true end
        if global.dtms.config and not global.dtms.config.allow_mining then entity.rotatable = true end
        if global.dtms.config and not global.dtms.config.allow_shooting then entity.destructible = true end
        global.dtms.locked_entity_ids[entity_id(entity)] = nil
    end
end

local function evaluate_callbacks()
    if game.tick % 30 > 0 then return false end
    global.dtms.Timeout.evaluateCallbacks()
end

-- unlock the entity
local function attempt_unlock(player, locked_entity)
    local selected = player.selected
    if selected then
        local locked_entity_id = entity_id(locked_entity)
        if(entity_id(locked_entity) == entity_id(selected)) then
            -- still selecting the entity, enque again
            global.dtms.Timeout.setTimeout(attempt_unlock, {player, locked_entity}, 5, locked_entity_id)
            return false
        end
    end

    -- player is no longer selecting the locked entity, unlock it
    unlock_entity(locked_entity)
end

local function player_is_entity_owner(player, entity)
    return player.index == ( entity.last_user or player.index )
end

local function mine_check(player)
    local selected = player.selected
    if selected then
        if player_is_entity_owner(player, selected) then
            -- unlock the entity when selected by the owner
            unlock_entity(selected)
        else
            -- lock the entity when selected by a non-owner
            lock_entity(selected)

            -- attempt to unlock the entity in the future (when the entity is no longer selected)
            local locked_entity_id = entity_id(selected)
            global.dtms.Timeout.setTimeout(attempt_unlock, {player, selected}, 5, locked_entity_id)
        end
    end
end

script.on_event(defines.events.on_trigger_created_entity, function(event)
    log(event.entity.name)
--    if event.entity.name == 'extinguisher-remnants' then
        -- you at least know where shots landed
--    end
end)

script.on_event(defines.events.on_tick, function ()
	for _, player in pairs(game.players) do
		mine_check(player);
		evaluate_callbacks();
	end
end)

-- TODO: figoure out how to get the modules below in a seperate file, while retaining access to globals like game.tick

--
-- Timeout module
--

local Timeout = {}
if not global.dtms.Timeout then global.dtms.Timeout = Timeout end

Timeout.callbacks = {} -- pending callback timers

--[[
-- Execute the given function fn, with arguments args, in the future after duration_ticks.
-- Returns the given timeout id. Only one timeout per id will be enqueued at a time.
--
-- Example Usage:
--
--     function hit(a,b,c) print(a + b + c) end
--     Timeout.setTimeout(hit, {2,4,6}, 100, "id-123") -- tick 1
--     Timeout.setTimeout(hit, {2,4,6}, 100, "id-123") -- tick 2
--     > 12 -- output after tick 100
--]]
Timeout.setTimeout = function (fn, args, duration_ticks, id)
    if Timeout.callbacks and not(Timeout.callbacks[id]) then
        local execute_after = game.tick + duration_ticks
        Timeout.callbacks[id] = {
            id=id,
            args=args,
            execute_after=execute_after,
            callback= fn,
        }
        return id
    end
end

-- return all timeouts
Timeout.getTimeouts = function ()
    if Timeout.callbacks then
        return Timeout.callbacks
    end
end

-- remove the given timeout id
Timeout.clearTimeout = function (id)
    if Timeout.callbacks then
        Timeout.callbacks[id] = nil
    end
end

-- evaluate the timers in callbacks, execute them if past their execute_after time
Timeout.evaluateCallbacks = function ()
    local callbacks = Timeout.getTimeouts()
    if callbacks then
        for id, callback in pairs(callbacks) do
            if callback and game.tick > callback.execute_after then
                Timeout.clearTimeout(id)
                if callback.args then callback.callback(unpack(callback.args)) else callback.callback() end
            end
        end
    end
end

--
-- Timeout module END
--
