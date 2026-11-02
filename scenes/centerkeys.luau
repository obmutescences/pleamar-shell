--  Forward the centre panel's keys to the shell scene.  The helper owns the
--  keyboard while the panel is open; the panel itself asks for none.
local parent = "island"

run("sh", { "-c", 'printf %s "${PLEAMAR_CENTER_PARENT:-island}"' }, function(out)
    local p = tostring(out or ""):gsub("%s+$", "")
    if p ~= "" then parent = p end
end)

local function send(cmd)
    local ok, err = pcall(sys.call, "say", parent, cmd)
    if not ok then log("centre key helper: " .. tostring(err)) end
end

--  If the centre panel stops pinging, release the keyboard.  The main logic
--  kills this process on a normal close; this covers a crash or a missed close.
local missed = 0
on("key_ping", function() missed = 0 end)
every(900, function()
    missed = missed + 1
    if missed >= 3 then
        run("sh", { "-c", "pkill -f 'scenes/centerkeys.plm' 2>/dev/null || true" })
    end
end)

local focused = false
local ready = false
after(600, function() ready = true end)
on("focus", function() focused = true end)
on("blur", function()
    if focused and ready then send("emit center_key_blur") end
    focused = false
end)

on("key_down", function(name)
    name = tostring(name or "")
    if name == "Escape" then
        send("emit center_key_escape")
    elseif name == "XF86AudioRaiseVolume" then
        run("sh", { "-c", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ 2>/dev/null || true" })
    elseif name == "XF86AudioLowerVolume" then
        run("sh", { "-c", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- 2>/dev/null || true" })
    elseif name == "XF86AudioMute" then
        run("sh", { "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle 2>/dev/null || true" })
    elseif name == "Tab" or name == "ISO_Left_Tab" or name == "Backtab" then
        local d = (held("Shift") or held("ISO_Left_Tab")) and -1 or 1
        send("emit center_key_tab " .. d)
    else
        local n = tonumber(name)
        if n and n >= 1 and n <= 7 then send("emit center_key_digit " .. n) end
    end
end)
