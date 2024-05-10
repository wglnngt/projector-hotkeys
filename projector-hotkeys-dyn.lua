-- Add hotkeys to open fullscreen projectors
-- David Magnus <davidkmagnus@gmail.com>
-- https://github.com/DavidKMagnus
obs = obslua
ffi = require("ffi")
user32 = ffi.load("user32")


PROJECTOR_TYPE_SCENE = "Scene"
PROJECTOR_TYPE_SOURCE = "Source"
PROJECTOR_TYPE_PROGRAM = "StudioProgram"
PROJECTOR_TYPE_MULTIVIEW = "Multiview"

DEFAULT_MONITOR = 1

PROGRAM = "Program Output"
MULTIVIEW = "Multiview Output"
SOURCE = "CaptureSource"
GROUP = "gp"
STARTUP = "su"

monitors = {}
arr_monitors = {}
startup_projectors = {}
hotkey_ids = {}

ffi.cdef[[
	typedef struct {
		long left;
		long top;
		long right;
		long bottom;
	} RECT;

	typedef struct {
		unsigned long cbSize;
		RECT rcMonitor;
		RECT rcWork;
		unsigned long dwFlags;
	} MONITORINFO;

	typedef struct {
		long x;
		long y;
	} POINT;

	void* MonitorFromPoint(POINT pt, unsigned long dwFlags);
	bool GetMonitorInfoA(void* hMonitor, MONITORINFO* lpmi);

	typedef int (__stdcall *MONITORENUMPROC)(void*, void*, RECT*, long);

	int EnumDisplayMonitors(void* hdc, const RECT* lprcClip, MONITORENUMPROC lpfnEnum, long dwData);
]]

function MonitorEnumProc(hMonitor, hdcMonitor, lprcMonitor, dwData)
    local info = ffi.new("MONITORINFO")
    info.cbSize = ffi.sizeof(info)
    if user32.GetMonitorInfoA(hMonitor, info) then
        table.insert(arr_monitors, {
            left = info.rcMonitor.left,
            top = info.rcMonitor.top,
            right = info.rcMonitor.right,
            bottom = info.rcMonitor.bottom,
            width = info.rcMonitor.right - info.rcMonitor.left,
            height = info.rcMonitor.bottom - info.rcMonitor.top,
        })
		--print("Detected monitor")
    end
    return 1
end

function enumerate_monitors()
    arr_monitors = {}
    local proc = ffi.cast("MONITORENUMPROC", MonitorEnumProc)
    user32.EnumDisplayMonitors(nil, nil, proc, 0)
    proc:free()
end

-- Get real monitor number by coordinate
function get_real_number(monitor_index)
	print("Current input monitor number is: " .. monitor_index + 1)

	-- Coordinate mapping[KOUKON 2024/05/10]
	if monitor_index == 0 then
		-- For number 1 choice, projecting to main monitor
		for _, omonitor in ipairs(arr_monitors) do
			if omonitor.left == 0 then
				monitor_index = _ - 1 -- Based on 1
				break
			end
		end
	elseif monitor_index == 1 then
		-- For number 2 choice, projecting to right monitor
		for _, omonitor in ipairs(arr_monitors) do
			if omonitor.left >= arr_monitors[1].width then
				monitor_index = _ - 1 -- Based on 1
				break
			end
		end
	elseif monitor_index == 2 then
		-- For number 3 choice, projecting to left monitor
		for _, omonitor in ipairs(arr_monitors) do
			if omonitor.left < 0 then
				monitor_index = _ - 1 -- Based on 1
				break
			end
		end
	end

	return monitor_index
end

function script_description()
	enumerate_monitors()

    local description = [[
        <center><h2>Fullscreen Projector Hotkeys</h2></center>
        <p>Hotkeys will be added for the Program output, Multiview, and each currently existing scene.
        Choose the monitor to which each output will be projected when the hotkey is pressed.</p>
        <p>You can also choose to open a projector to a specific monitor on startup. If you use
        this option, you may need to disable the "Save projectors on exit" preference or there
        will be duplicate projectors.</p>
        <p><b>If new scenes are added, or if scene names change, this script will need to be
        reloaded.</b></p>]]
	
	description = description .. "<p><b>Current monitors: </b></p>"
	for _, omonitor in ipairs(arr_monitors) do
		description = description .. "<p>Index " .. _ .. ": (" .. omonitor.left .. "," .. omonitor.top .. ")	" .. omonitor.width .. "x" .. omonitor.height .. "</p>"
	end
	--print(description)

    return description
end

function script_properties()
    local p = obs.obs_properties_create()

    -- loop through each scene and create a property group and control for choosing the monitor and startup settings
    local scenes = obs.obs_frontend_get_scene_names()
    if scenes ~= nil then
        for _, scene in ipairs(scenes) do
            local gp = obs.obs_properties_create()
            obs.obs_properties_add_group(p, scene .. GROUP, scene, obs.OBS_GROUP_NORMAL, gp)
            obs.obs_properties_add_int(gp, scene, "Project to monitor:", 1, 10, 1)
            obs.obs_properties_add_bool(gp, scene .. STARTUP, "Open on Startup")
        end
        obs.bfree(scene)
    end

    -- set up the controls for the Source
	local gp = obs.obs_properties_create()
	obs.obs_properties_add_group(p, SOURCE .. GROUP, SOURCE, obs.OBS_GROUP_NORMAL, gp)
	obs.obs_properties_add_int(gp, SOURCE, "Project to monitor:", 1, 10, 1)
	obs.obs_properties_add_bool(gp, SOURCE .. STARTUP, "Open on Startup")

    -- set up the controls for the Program Output
    local gp = obs.obs_properties_create()
    obs.obs_properties_add_group(p, PROGRAM .. GROUP, "Program Output", obs.OBS_GROUP_NORMAL, gp)
    obs.obs_properties_add_int(gp, PROGRAM, "Project to monitor:", 1, 10, 1)
    obs.obs_properties_add_bool(gp, PROGRAM .. STARTUP, "Open on Startup")

    -- set up the controls for the Multiview
    local gp = obs.obs_properties_create()
    obs.obs_properties_add_group(p, MULTIVIEW .. GROUP, "Multiview", obs.OBS_GROUP_NORMAL, gp)
    obs.obs_properties_add_int(gp, MULTIVIEW, "Project to monitor:", 1, 10, 1)
    obs.obs_properties_add_bool(gp, MULTIVIEW .. STARTUP, "Open on Startup")

    return p
end

function script_update(settings)
    update_monitor_preferences(settings)
end

function script_load(settings)   
	enumerate_monitors()
	print("Total monitor count is: " .. #arr_monitors)

    local scenes = obs.obs_frontend_get_scene_names()
    if scenes == nil or #scenes == 0 then
        -- on obs startup, scripts are loaded before scenes are finished loading
        -- register a callback to register the hotkeys and open startup projectors after scenes are available
        obs.obs_frontend_add_event_callback(
            function(e)
                if e == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then
                    update_monitor_preferences(settings)
                    register_hotkeys(settings)
                    open_startup_projectors()
                    obs.remove_current_callback()
                end
            end
        )
    else
        -- this runs when the script is loaded or reloaded from the settings window
        update_monitor_preferences(settings)
        register_hotkeys(settings)
    end    
end

function script_save(settings)
    for output, hotkey_id in pairs(hotkey_ids) do
        local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
        obs.obs_data_set_array(settings, output_to_function_name(output), hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end
end

-- find the monitor preferences for each projector and store them
function update_monitor_preferences(settings)
    local outputs = obs.obs_frontend_get_scene_names()

    table.insert(outputs, SOURCE)
    table.insert(outputs, MULTIVIEW)
    table.insert(outputs, PROGRAM)

    for _, output in ipairs(outputs) do
        local monitor = obs.obs_data_get_int(settings, output)
        if monitor == nil or monitor == 0 then
            monitor = DEFAULT_MONITOR
        end

        -- monitors are 0 indexed here, but 1-indexed in the OBS menus
        monitors[output] = monitor-1

        -- set which projectors should open on start up
        startup_projectors[output] = obs.obs_data_get_bool(settings, output .. STARTUP)
    end
    obs.bfree(output)
end

-- register a hotkey to open a projector for each output
function register_hotkeys(settings)
    local outputs = obs.obs_frontend_get_scene_names()
    table.insert(outputs, SOURCE)
    table.insert(outputs, MULTIVIEW)
    table.insert(outputs, PROGRAM)

    for _, output in ipairs(outputs) do
        hotkey_ids[output] = obs.obs_hotkey_register_frontend(
            output_to_function_name(output),
            "Open Fullscreen Projector for '" .. output .. "'",
            function(pressed)
                if not pressed then
                    return
                end
                open_fullscreen_projector(output)
            end
        )

		--print(output_to_function_name(output))
        local hotkey_save_array = obs.obs_data_get_array(settings, output_to_function_name(output))
        obs.obs_hotkey_load(hotkey_ids[output], hotkey_save_array)
        obs.obs_data_array_release(hotkey_save_array)
    end
    obs.bfree(output)
end

-- open a full screen projector
function open_fullscreen_projector(output)
    -- set the default monitor if one was never set
    if monitors[output] == nil then
        monitors[output] = DEFAULT_MONITOR
    end

	nMonitorIndex = get_real_number(monitors[output])

    -- set the projector type if this is not a normal scene
    local projector_type = PROJECTOR_TYPE_SCENE
    if output == PROGRAM then
        projector_type = PROJECTOR_TYPE_PROGRAM
    elseif output == MULTIVIEW then
        projector_type = PROJECTOR_TYPE_MULTIVIEW
    else
        projector_type = PROJECTOR_TYPE_SOURCE
    end

	print("Current monitor for key : " .. output .. "\n\t\t " .. output .. "'s true index is : " .. nMonitorIndex)

    -- call the front end API to open the projector
    obs.obs_frontend_open_projector(projector_type, nMonitorIndex, "", output)
end

-- open startup projectors
function open_startup_projectors()
    for output, open_on_startup in pairs(startup_projectors) do
        if open_on_startup then
            open_fullscreen_projector(output)
        end
    end
end

-- remove special characters from scene names to make them usable as function names
function output_to_function_name(name)
    return "ofsp_" .. name:gsub('[%p%c%s]', '_')
end

