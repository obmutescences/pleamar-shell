--  Forward the settings panel's typed text to the main scene.  The helper has
--  the keyboard; the visible input in settings follows the text fact because
--  it is bound to the same name.  Escape closes the settings panel.
local parent = "island"
local field = "weather_city"
local initial = ""
local ready = false
local last = ""

local function send(cmd)
    local ok, err = pcall(sys.call, "say", parent, cmd)
    if not ok then log("settings key helper: " .. tostring(err)) end
end

run("sh", { "-c", 'printf "%s\\n%s\\n%s" "${PLEAMAR_SETTINGS_PARENT:-island}" "${PLEAMAR_SETTINGS_FIELD:-weather_city}" "${PLEAMAR_SETTINGS_TEXT:-}"' }, function(out)
    local lines = {}
    for line in tostring(out or ""):gmatch("([^\n]*)\n?") do lines[#lines + 1] = line end
    if lines[1] and lines[1] ~= "" then parent = lines[1] end
    if lines[2] and lines[2] ~= "" then field = lines[2] end
    initial = lines[3] or ""
    text.buffer = initial
    last = initial
    after(250, function()
        ready = true
        fact.ready = true
    end)
end)

on("text:buffer", function()
    if not ready then return end
    local value = tostring(text.buffer or "")
    if value == last then return end
    last = value
    --  The text command takes the rest of the line, so spaces are fine.
    send("text " .. field .. " " .. value)
end)

on("key_down", function(name)
    name = tostring(name or "")
    if name == "Escape" then
        send("emit settings_close")
    elseif name == "XF86AudioRaiseVolume" then
        run("sh", { "-c", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ 2>/dev/null || true" })
    elseif name == "XF86AudioLowerVolume" then
        run("sh", { "-c", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- 2>/dev/null || true" })
    elseif name == "XF86AudioMute" then
        run("sh", { "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle 2>/dev/null || true" })
    end
end)

local missed = 0
on("key_ping", function() missed = 0 end)
every(900, function()
    missed = missed + 1
    if missed >= 3 then
        run("sh", { "-c", "pkill -f 'scenes/settingskeys.plm' 2>/dev/null || true" })
    end
end)
