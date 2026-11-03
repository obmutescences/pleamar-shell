--  Forward the window picker's keys to the parent scene.  The helper is the
--  only surface in its process, so niri gives it the keyboard; the picker
--  itself asks for none.
local parent = "island"
local ready = false
local last = ""

local function send(cmd)
    local ok, err = pcall(sys.call, "say", parent, cmd)
    if not ok then log("window key helper: " .. tostring(err)) end
end

run("sh", { "-c", 'printf %s "${PLEAMAR_WINDOW_PARENT:-island}"' }, function(out)
    local p = tostring(out or ""):gsub("%s+$", "")
    if p ~= "" then parent = p end
    after(250, function()
        ready = true
        fact.ready = true
    end)
end)

--  The input owns the text; forward only the new characters, then empty the
--  helper buffer so the next batch starts clean.
on("text:buffer", function()
    if not ready then return end
    local value = tostring(text.buffer or "")
    if value == last then return end
    local added = value:sub(#last + 1)
    last = value
    for ch in added:gmatch("[A-Za-z]") do
        send("emit winpicker_key " .. ch)
    end
    if value ~= "" then
        text.buffer = ""
        last = ""
    end
end)

on("key_down", function(name)
    name = tostring(name or "")
    if name == "Escape" or name == "Return" then
        send("emit winpicker_close")
    elseif name == "XF86AudioRaiseVolume" then
        run("sh", { "-c", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ 2>/dev/null || true" })
    elseif name == "XF86AudioLowerVolume" then
        run("sh", { "-c", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- 2>/dev/null || true" })
    elseif name == "XF86AudioMute" then
        run("sh", { "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle 2>/dev/null || true" })
    end
end)

--  The parent pings while the picker is open; otherwise release the keyboard.
local missed = 0
on("key_ping", function() missed = 0 end)
every(900, function()
    missed = missed + 1
    if missed >= 3 then
        run("sh", { "-c", "pkill -f 'scenes/windowkeys.plm' 2>/dev/null || true" })
    end
end)
