if reframework:get_game_name() ~= "re4" then
    return
end

local scene_manager = nil
local scene = nil
local PlayerInventoryObserver = nil
local InventoryObserver = nil
local Observer = nil


local iframe_duration = 0.3 -- Duration in seconds for iframes after actions
local iframe_cooldown_start = nil
local iframes_should_be_active = false
local cooldown_finished = false
local user_input_iframe_duration = iframe_duration

local hit_point = nil 

local damage_type = nil
local state = nil
local invincible = false

-- Initialize condition variables
local current_is_fatal_kick = false
local current_is_fatal_round_kick = false
local current_is_combating = false
local current_is_jumping = false
local current_is_terrain_action = false
local current_is_ladder = false
local current_is_landing = false
local current_is_parry = false
local current_is_dodging = false
local current_is_falling = false
local current_is_hookshot = false
local current_is_grapple = false

local action_ended_flags = {
    is_fatal_kick = false,
    is_fatal_round_kick = false,
    is_combating = false,
    is_jumping = false,
    is_terrain_action = false,
    is_ladder = false,
    is_landing = false,
}

local action_end_time = {}

local iframe_presets = {
    Default = { duration = 0.3 },
    Short = { duration = 0.2 },
    Shorter = { duration = 0.1 },
    Long = { duration = 0.4 },
    Longer = { duration = 0.5 },
    -- Add more presets as needed
}

-- Available options for iframes
local iframe_options = { "Limited", "Full" }
-- Variable to store the current selection (default to 'Full')
local selected_iframe_option = 1
local include_grapple_damage_iframes = false  -- Default is unchecked


local preset_order = { "Shorter", "Short", "Default", "Long", "Longer" } -- Order of presets as they should appear

local save_file_path = "Mr. Boobie\\iFrames.json"  -- Update this path

local function save_configuration()
    local data = {
        iframe_duration = iframe_duration, 
        selected_iframe_option = selected_iframe_option,
        include_grapple_damage_iframes = include_grapple_damage_iframes
    }
    local success, err = pcall(json.dump_file, save_file_path, data)
    if not success then

    end
end

local function load_configuration()
    local file = io.open(save_file_path, "r")
    if file then
        file:close()
        local status, data = pcall(json.load_file, save_file_path)
        if status and data then
            -- Load iframe duration
            if data.iframe_duration then
                iframe_duration = data.iframe_duration
            end

            -- Load selected iframe mode option
            if data.selected_iframe_option then
                selected_iframe_option = data.selected_iframe_option
            end

            -- Load the state for include grapple damage iframes
            if data.include_grapple_damage_iframes ~= nil then  -- Explicit check for nil to allow false value
                include_grapple_damage_iframes = data.include_grapple_damage_iframes
            end
        else
            save_configuration()  -- Save default if the file is corrupt or has invalid data
        end
    else
        save_configuration()  -- Save default if the file doesn't exist
    end
end


-- Reset function to turn off iframes and reset variables
    local function reset_variables()
        if hit_point then
            hit_point:set_Invincible(false)
        end
        iframe_cooldown_start = nil
        iframes_should_be_active = false
        for action, _ in pairs(action_ended_flags) do
            action_ended_flags[action] = false
        end
        for action, _ in pairs(action_end_time) do
            action_end_time[action] = nil
        end
        cooldown_finished = false
        scene_manager = nil
        scene = nil
        PlayerInventoryObserver = nil
        InventoryObserver = nil
        Observer = nil
        load_configuration()
    end
    re.on_script_reset(function()

        reset_variables()
    end)

    load_configuration()  -- Load the configuration from the save file

-- Main frame update function
    re.on_frame(function()
        -- Attempt to retrieve the current scene, character context, and other necessary components
        local scene_manager = sdk.get_native_singleton("via.SceneManager")
        if not scene_manager then
            reset_variables()
            log.error("Failed to get scene manager.")
            return
        end

        local scene = sdk.call_native_func(scene_manager, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
        if not scene then
            reset_variables()
            log.error("Failed to get current scene.")
            return
        end

        local PlayerInventoryObserver = scene:call("findGameObject(System.String)", "PlayerInventoryObserver")
        if not PlayerInventoryObserver then
            reset_variables()
            return
        end

        local InventoryObserver = PlayerInventoryObserver:call("getComponent(System.Type)", sdk.typeof("chainsaw.PlayerInventoryObserver"))
        if not InventoryObserver then
            reset_variables()
            return
        end

        local Observer = InventoryObserver:get_field("_Observer")
        if not Observer then
            reset_variables()
            return
        end

        local self_context = Observer:get_field("_SelfCharacterContext")
        if not self_context then
            reset_variables()
            return
        end

        hit_point = self_context:get_field("<HitPoint>k__BackingField")
        if not hit_point then
            reset_variables()
            return
        end
        invincible = hit_point:get_Invincible()

      -- Retrieve the current state of the conditions
      current_is_fatal_kick = self_context:get_IsFatalKick() or false
      current_is_fatal_round_kick = self_context:get_IsFatalRoundKick() or false
      current_is_combating = self_context:get_IsCombating() or false
      current_is_jumping = self_context:get_IsJumping() or false
      current_is_terrain_action = self_context:get_IsTerrainAction() or false
      current_is_ladder = self_context:get_IsLadder() or false
      current_is_landing = self_context:get_IsLanding() or false
      current_is_parry = self_context:get_IsParry() or false
      current_is_dodging = self_context:get_IsDodging() or false
      current_is_hookshot = self_context:get_IsHookShot() or false
      current_is_grapple = self_context:get_IsInGrappleDamage() or false

      local include_combating = iframe_options[selected_iframe_option] == "Full"

      -- Check if any actions are currently active
      local any_actions_active = current_is_fatal_kick or current_is_fatal_round_kick or current_is_jumping or
                                 current_is_terrain_action or current_is_ladder or current_is_hookshot or
                                 current_is_landing or current_is_parry or current_is_dodging or (include_combating and current_is_combating) or (include_grapple_damage_iframes and current_is_grapple)

      -- Determine if any actions have just ended this frame
      local any_actions_ended = (iframes_should_be_active and not any_actions_active and not iframe_cooldown_start)

      -- If any action is currently active, enable iframes
      if any_actions_active then
          iframes_should_be_active = true
          hit_point:set_Invincible(true)
      elseif any_actions_ended then
          -- Actions have just ended, start the cooldown
          iframe_cooldown_start = os.clock()
          hit_point:set_Invincible(true) -- Maintain invincibility as cooldown starts
      end

      -- Manage the cooldown period after actions have ended
      if iframe_cooldown_start then
          local time_since_cooldown_started = os.clock() - iframe_cooldown_start
          if time_since_cooldown_started <= iframe_duration then
              -- During the cooldown, maintain invincibility
              hit_point:set_Invincible(true)
          else
              -- After the cooldown, disable invincibility
              iframes_should_be_active = false
              hit_point:set_Invincible(false)
              iframe_cooldown_start = nil -- Reset the cooldown
          end
      end
  end)

re.on_draw_ui(function()
    if imgui.tree_node("iFrames") then

        imgui.checkbox("iFrames Active", invincible)

            -- Combo box for selecting iframe mode
            local changed_mode = false
            changed_mode, selected_iframe_option = imgui.combo("iFrame Mode", selected_iframe_option, iframe_options)
            if changed_mode then
                save_configuration()  -- Save the new configuration if there's a change
            end

            -- Find the current index of the selected preset
            local selected_preset_index = 1
            for i, key in ipairs(preset_order) do
                if iframe_duration == iframe_presets[key].duration then
                    selected_preset_index = i
                    break
                end
            end

            -- imgui combo to select preset
            local changed = false
            changed, selected_preset_index = imgui.combo("iFrame Duration Presets", selected_preset_index, preset_order)
            if changed then
                iframe_duration = iframe_presets[preset_order[selected_preset_index]].duration
                save_configuration()  -- Save the new configuration
            end

            -- Checkbox for 'IsInGrappleDamage' iframes
            local changed_grapple = false
            changed_grapple, include_grapple_damage_iframes = imgui.checkbox("Include Grapple Damage iFrames", include_grapple_damage_iframes)
            if changed_grapple then
                save_configuration()  -- Save the new configuration if there's a change
            end

        imgui.tree_pop()
    end

end)
