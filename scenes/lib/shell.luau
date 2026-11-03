-- Pleamar's shared logic: cava -> six spectrum bands, the config file, and the
-- launcher's filtered app list.  The scene decides what is drawn; this file
-- only reports facts and models.
local M = {}
local center = require("lib/center")

local function truthy(v)
    return v == true or v == 1
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function number(v, fallback)
    local n = tonumber(v)
    if n == nil then return fallback end
    return n
end

function M.start(layout)
    text.layout = layout

    --  ── config ──────────────────────────────────────────────────────────
    --  One shared file for both layouts: ~/.config/pleamar-shell/config.json.
    --  The file service is sandboxed to the scene's data folder, so the config
    --  uses `sh` (declared in the scene's permissions) to read and write HOME.
    local READ = 'mkdir -p "$HOME/.config/pleamar-shell" 2>/dev/null; cat "$HOME/.config/pleamar-shell/config.json" 2>/dev/null'

    local cfg = {
        font_family = "Space Grotesk",
        wallpaper = "",
        wallpaper_dir = "",
        wallpaper_auto = false,
        wallpaper_minutes = 5,
        snd_on = true,
        nt_pos = 1,
        nt_snd_on = true,
        nt_sound = 1,
        nt_dnd = false,
        nt_secs = 6,
        palette = {
            ink = "#eaf7f5", faint = "#9fb8b6", aqua = "#8ff5df",
            azure = "#58c8ff", tint = "#0c1a1e", panel = "#0a171b",
            deep = "#050c0f",
        },
        bar_height = 44,
        glass_on = true,
        glass_bend = true,
        glass_refr = 1,
        glass_disp = 1,
        glass_dome = 0,
        glass_milk = 0,
        glass_tint = 58,
        glass_frost = 100,
        glass_edge = 34,
        wave_on = true,
        wave_depth = 100,
        wave_blend = 0.55,
        wave_gain = 1.4,
        wave_amp = 1.4,
        wave_ripples = 1,
        wave_height = 1.6,
        lock_blur = 36,
        lock_12h = true,
        lock_ampm = true,
        lock_media = true,
        lock_secs = false,
        lock_power = true,
        lock_px = 200,
        lock_date = 0,
        lock_mask = 0,
        lock_pal = 1,
        idle_lock_seconds = 0,
        idle_off_seconds = 0,
        anim_search = 0,
        anim_panel = 0,
        anim_toast = 0,
        anim_center = 0,
        anim_center_panel = 0,
        weather_city = "",
    }

    local function sq(v)
        return "'" .. tostring(v):gsub("'", "'\\''") .. "'"
    end

    local PALETTE_KEYS = { "ink", "faint", "aqua", "azure", "primary", "secondary", "tint", "panel", "deep" }
    local function hex_to_rgb(h)
        return tonumber(h:sub(2, 3), 16) / 255,
               tonumber(h:sub(4, 5), 16) / 255,
               tonumber(h:sub(6, 7), 16) / 255
    end
    --  One palette colour is three facts; rgb() in the scene turns them back
    --  into a colour without rewriting a file or reloading the scene.
    local function set_palette(pal)
        if type(pal) ~= "table" then return end
        for _, k in ipairs(PALETTE_KEYS) do
            local h = pal[k]
            if type(h) == "string" and h:match("^#%x%x%x%x%x%x$") then
                local r, g, b = hex_to_rgb(h)
                fact["pal_" .. k .. "_r"] = r
                fact["pal_" .. k .. "_g"] = g
                fact["pal_" .. k .. "_b"] = b
                cfg.palette[k] = h
            end
        end
        --  Keep the whole answer too: primary, secondary, tertiary and the
        --  Material-style roles are for scripts that come later.
        cfg.palette = pal
    end
    local function write_palette(pal)
        if type(pal) ~= "table" then return end
        --  `run`'s input option was not reaching sh here; a quoted printf is
        --  plain and testable, and the palette is only a couple of kilobytes.
        local cmd = 'mkdir -p "$HOME/.config/pleamar-shell" 2>/dev/null; printf %s '
            .. sq(json.encode(pal)) .. ' > "$HOME/.config/pleamar-shell/palette.json"'
        local wrote, err = pcall(run, "sh", { "-c", cmd }, function(_, code)
            if code ~= 0 then log("palette.json write exited " .. tostring(code)) end
        end)
        if not wrote then log("palette.json could not be saved: " .. tostring(err)) end
    end

    --  Seconds, so the shortest timers are useful (0 is Never).
    local IDLE_STEPS = { 0, 5, 10, 30, 60, 120, 180, 300, 420, 600, 900, 1200, 1800, 2700, 3600, 5400, 7200 }
    local function idle_index(s)
        local at = 1
        for i, v in ipairs(IDLE_STEPS) do if v <= s then at = i end end
        return at - 1
    end
    local function idle_words(s)
        s = math.floor(clamp(number(s, 0), 0, 7200))
        if s == 0 then return "Never" end
        if s < 60 then return s .. (s == 1 and " second" or " seconds") end
        local m, rem = s // 60, s % 60
        if rem > 0 then return m .. " min " .. rem .. " s" end
        if m < 60 then return m .. (m == 1 and " minute" or " minutes") end
        local h = m // 60
        return h .. (h == 1 and " hour" or " hours") .. (m % 60 > 0 and (" " .. (m % 60) .. " min") or "")
    end

    local function apply(saved)
        if type(saved.font_family) == "string" and saved.font_family ~= "" then
            cfg.font_family = saved.font_family
        end
        if type(saved.wallpaper) == "string" then cfg.wallpaper = saved.wallpaper end
        if type(saved.wallpaper_dir) == "string" then cfg.wallpaper_dir = saved.wallpaper_dir end
        if type(saved.wallpaper_auto) == "boolean" then cfg.wallpaper_auto = saved.wallpaper_auto end
        cfg.wallpaper_minutes = clamp(number(saved.wallpaper_minutes, cfg.wallpaper_minutes), 1, 60)
        if type(saved.snd_on) == "boolean" then cfg.snd_on = saved.snd_on end
        cfg.nt_pos = clamp(number(saved.nt_pos, cfg.nt_pos), 0, 1)
        if type(saved.nt_snd_on) == "boolean" then cfg.nt_snd_on = saved.nt_snd_on end
        cfg.nt_sound = clamp(number(saved.nt_sound, cfg.nt_sound), 1, 8)
        if type(saved.nt_dnd) == "boolean" then cfg.nt_dnd = saved.nt_dnd end
        cfg.nt_secs = math.floor(clamp(number(saved.nt_secs, cfg.nt_secs), 2, 60))
        if type(saved.palette) == "table" then
            set_palette(saved.palette)
            write_palette(saved.palette)
        end
        cfg.bar_height = clamp(number(saved.bar_height, cfg.bar_height), 32, 80)
        if type(saved.glass_on) == "boolean" then cfg.glass_on = saved.glass_on end
        if type(saved.glass_bend) == "boolean" then cfg.glass_bend = saved.glass_bend end
        cfg.glass_refr = clamp(number(saved.glass_refr, cfg.glass_refr), 0, 2)
        cfg.glass_disp = clamp(number(saved.glass_disp, cfg.glass_disp), 0, 2)
        cfg.glass_dome = clamp(number(saved.glass_dome, cfg.glass_dome), 0, 1.5)
        cfg.glass_milk = clamp(number(saved.glass_milk, cfg.glass_milk), 0, 1)
        cfg.glass_tint = clamp(number(saved.glass_tint, cfg.glass_tint), 20, 100)
        cfg.glass_frost = clamp(number(saved.glass_frost, cfg.glass_frost), 0, 100)
        cfg.glass_edge = clamp(number(saved.glass_edge, cfg.glass_edge), 0, 100)
        if type(saved.wave_on) == "boolean" then cfg.wave_on = saved.wave_on end
        cfg.wave_depth = clamp(number(saved.wave_depth, cfg.wave_depth), 40, 180)
        cfg.wave_blend = clamp(number(saved.wave_blend, cfg.wave_blend), 0, 1)
        cfg.wave_gain = clamp(number(saved.wave_gain, cfg.wave_gain), 0.8, 2.4)
        cfg.wave_amp = clamp(number(saved.wave_amp, cfg.wave_amp), 0.2, 2.2)
        cfg.wave_ripples = math.floor(clamp(number(saved.wave_ripples, cfg.wave_ripples), 1, 10))
        cfg.wave_height = clamp(number(saved.wave_height, cfg.wave_height), 0, 3)
        cfg.lock_blur = clamp(number(saved.lock_blur, cfg.lock_blur), 0, 120)
        if type(saved.lock_12h) == "boolean" then cfg.lock_12h = saved.lock_12h end
        if type(saved.lock_ampm) == "boolean" then cfg.lock_ampm = saved.lock_ampm end
        if type(saved.lock_media) == "boolean" then cfg.lock_media = saved.lock_media end
        if type(saved.lock_secs) == "boolean" then cfg.lock_secs = saved.lock_secs end
        if type(saved.lock_power) == "boolean" then cfg.lock_power = saved.lock_power end
        cfg.lock_px = math.floor(clamp(number(saved.lock_px, cfg.lock_px), 80, 240))
        cfg.lock_date = math.floor(clamp(number(saved.lock_date, cfg.lock_date), 0, 3))
        cfg.lock_mask = math.floor(clamp(number(saved.lock_mask, cfg.lock_mask), 0, 3))
        cfg.lock_pal = math.floor(clamp(number(saved.lock_pal, cfg.lock_pal), 0, 4))
        --  Existing configs stored whole minutes; keep those as a fallback
        --  for one load, then write seconds.
        local lock_s = tonumber(saved.idle_lock_seconds)
        if lock_s == nil then lock_s = (tonumber(saved.idle_lock_minutes) or 0) * 60 end
        local off_s = tonumber(saved.idle_off_seconds)
        if off_s == nil then off_s = (tonumber(saved.idle_off_minutes) or 0) * 60 end
        cfg.idle_lock_seconds = math.floor(clamp(lock_s, 0, 7200))
        cfg.idle_off_seconds = math.floor(clamp(off_s, 0, 7200))
        cfg.anim_search = math.floor(clamp(number(saved.anim_search, cfg.anim_search), 0, 5))
        cfg.anim_panel = math.floor(clamp(number(saved.anim_panel, cfg.anim_panel), 0, 5))
        cfg.anim_toast = math.floor(clamp(number(saved.anim_toast, cfg.anim_toast), 0, 5))
        cfg.anim_center = math.floor(clamp(number(saved.anim_center, cfg.anim_center), 0, 5))
        cfg.anim_center_panel = math.floor(clamp(number(saved.anim_center_panel, cfg.anim_center_panel), 0, 5))
        if type(saved.weather_city) == "string" then
            cfg.weather_city = saved.weather_city:gsub("^%s+", ""):gsub("%s+$", "")
        end

        text.weather_city = cfg.weather_city
        text.font_family = cfg.font_family
        text.font_choice = cfg.font_family
        text.wallpaper = cfg.wallpaper
        text.wallpaper_dir = cfg.wallpaper_dir
        text.wall_name = cfg.wallpaper:match("([^/]+)$") or ""
        fact.wall_auto = cfg.wallpaper_auto
        fact.wall_minutes = cfg.wallpaper_minutes
        fact.snd_on = cfg.snd_on
        fact.nt_pos = cfg.nt_pos
        fact.nt_snd_on = cfg.nt_snd_on
        fact.nt_sound = cfg.nt_sound
        fact.nt_dnd = cfg.nt_dnd
        fact.nt_secs = cfg.nt_secs
        fact.wall_remain = cfg.wallpaper_auto and cfg.wallpaper_minutes or 0
        text.wall_next = cfg.wallpaper_auto
            and string.format("Next in %d min", cfg.wallpaper_minutes)
            or "Auto rotation off"
        fact.bar_height = cfg.bar_height
        fact.glass_on = cfg.glass_on
        fact.glass_bend = cfg.glass_bend
        fact.glass_refr = cfg.glass_refr
        fact.glass_disp = cfg.glass_disp
        fact.glass_dome = cfg.glass_dome
        fact.glass_milk = cfg.glass_milk
        fact.glass_tint = cfg.glass_tint
        fact.glass_frost = cfg.glass_frost
        fact.glass_edge = cfg.glass_edge
        fact.wave_on = cfg.wave_on
        fact.wave_depth = cfg.wave_depth
        fact.wave_blend = cfg.wave_blend
        fact.wave_gain = cfg.wave_gain
        fact.wave_amp = cfg.wave_amp
        fact.wave_ripples = cfg.wave_ripples
        fact.wave_height = cfg.wave_height
        fact.lock_blur = cfg.lock_blur
        fact.lock_12h = cfg.lock_12h
        fact.lock_ampm = cfg.lock_ampm
        fact.lock_media = cfg.lock_media
        fact.lock_secs = cfg.lock_secs
        fact.lock_power = cfg.lock_power
        fact.lock_px = cfg.lock_px
        fact.lock_date = cfg.lock_date
        fact.lock_mask = cfg.lock_mask
        fact.lock_pal = cfg.lock_pal
        fact.idle_lock_seconds = cfg.idle_lock_seconds
        fact.idle_off_seconds = cfg.idle_off_seconds
        fact.idle_lock_i = idle_index(cfg.idle_lock_seconds)
        fact.idle_off_i = idle_index(cfg.idle_off_seconds)
        text.idle_lock_t = idle_words(cfg.idle_lock_seconds)
        text.idle_off_t = idle_words(cfg.idle_off_seconds)
        fact.anim_search = cfg.anim_search
        fact.anim_panel = cfg.anim_panel
        fact.anim_toast = cfg.anim_toast
        fact.anim_center = cfg.anim_center
        fact.anim_center_panel = cfg.anim_center_panel
    end

    local save_pending, save_running = nil, false
    local save_waiters = {}
    local flush_save
    local function save(done)
        local payload = {
            v = 6,
            weather_city = tostring(text.weather_city or cfg.weather_city or ""),
            font_family = tostring(text.font_family or "Space Grotesk"),
            wallpaper = tostring(text.wallpaper or ""),
            wallpaper_dir = tostring(text.wallpaper_dir or ""),
            wallpaper_auto = truthy(fact.wall_auto),
            wallpaper_minutes = number(fact.wall_minutes, 5),
            snd_on = truthy(fact.snd_on),
            nt_pos = number(fact.nt_pos, 1),
            nt_snd_on = truthy(fact.nt_snd_on),
            nt_sound = number(fact.nt_sound, 1),
            nt_dnd = truthy(fact.nt_dnd),
            nt_secs = number(fact.nt_secs, 6),
            palette = cfg.palette,
            bar_height = number(fact.bar_height, 44),
            glass_on = truthy(fact.glass_on),
            glass_bend = truthy(fact.glass_bend),
            glass_refr = number(fact.glass_refr, 1),
            glass_disp = number(fact.glass_disp, 1),
            glass_dome = number(fact.glass_dome, 0),
            glass_milk = number(fact.glass_milk, 0),
            glass_tint = number(fact.glass_tint, 58),
            glass_frost = number(fact.glass_frost, 100),
            glass_edge = number(fact.glass_edge, 34),
            wave_on = truthy(fact.wave_on),
            wave_depth = number(fact.wave_depth, 100),
            wave_blend = number(fact.wave_blend, 0.55),
            wave_gain = number(fact.wave_gain, 1.4),
            wave_amp = number(fact.wave_amp, 1.4),
            wave_ripples = number(fact.wave_ripples, 1),
            wave_height = number(fact.wave_height, 1.6),
            lock_blur = number(fact.lock_blur, 36),
            lock_12h = truthy(fact.lock_12h),
            lock_ampm = truthy(fact.lock_ampm),
            lock_media = truthy(fact.lock_media),
            lock_secs = truthy(fact.lock_secs),
            lock_power = truthy(fact.lock_power),
            lock_px = number(fact.lock_px, 200),
            lock_date = number(fact.lock_date, 0),
            lock_mask = number(fact.lock_mask, 0),
            lock_pal = number(fact.lock_pal, 1),
            idle_lock_seconds = number(fact.idle_lock_seconds, 0),
            idle_off_seconds = number(fact.idle_off_seconds, 0),
            anim_search = number(fact.anim_search, 0),
            anim_panel = number(fact.anim_panel, 0),
            anim_toast = number(fact.anim_toast, 0),
            anim_center = number(fact.anim_center, 0),
            anim_center_panel = number(fact.anim_center_panel, 0),
        }
        --  One writer at a time, latest snapshot wins.  A wallpaper apply and
        --  the colour read that follows it both save; without this queue a
        --  slower earlier write could put the old picture back in config.json.
        save_pending = payload
        if done then save_waiters[#save_waiters + 1] = done end
        flush_save()
    end

    flush_save = function()
        if save_running or not save_pending then return end
        local payload = save_pending
        save_pending = nil
        save_running = true
        local waiters = save_waiters
        save_waiters = {}
        local cmd = 'mkdir -p "$HOME/.config/pleamar-shell" 2>/dev/null; printf %s '
            .. sq(json.encode(payload)) .. ' > "$HOME/.config/pleamar-shell/config.json"'
        local wrote, err = pcall(run, "sh", { "-c", cmd }, function(_, code)
            save_running = false
            if save_pending then
                --  A newer snapshot arrived while this one was writing: it
                --  goes next, and the callbacks wait for the real last write.
                for _, cb in ipairs(save_waiters) do waiters[#waiters + 1] = cb end
                save_waiters = waiters
            else
                for _, cb in ipairs(waiters) do cb(code) end
            end
            flush_save()
        end)
        if not wrote then
            save_running = false
            log("config could not be saved: " .. tostring(err))
            for _, cb in ipairs(waiters) do cb(1) end
            flush_save()
        end
    end

    --  ── opening motion ─────────────────────────────────────────────────
    --  A panel chooses its pose once and keeps it for the whole move.  Six
    --  settings: 0 fade, 1 spin, 2 unfold, 3 drop, 4 aperture, 5 random.
    --  The pose is chosen when a panel opens and kept through its close.
    local ANIM_KINDS = { "search", "panel", "toast", "center", "center_panel" }
    local function current_fx(kind)
        return math.floor(clamp(number(fact[kind .. "_fx"], 0), 0, 4))
    end
    local function choose_fx(kind)
        local conf = math.floor(clamp(number(fact["anim_" .. kind], 0), 0, 5))
        if conf >= 5 then
            return (current_fx(kind) + 1 + math.floor(math.random() * 4)) % 5
        end
        return conf
    end
    local function set_fx(kind)
        fact[kind .. "_fx"] = choose_fx(kind)
    end
    local function sync_fx()
        for _, kind in ipairs(ANIM_KINDS) do set_fx(kind) end
    end
    local function open_value(kind)
        if kind == "search" then return fact.launch_open end
        if kind == "panel" then return fact.panel_open end
        if kind == "toast" then return fact.nt_has end
        if kind == "center_panel" then return fact.center_open end
        return fact.nt_center
    end
    local function config_changed(kind)
        --  Changing a fixed effect while its panel is open would jump the
        --  current pose; it takes effect on the next opening instead.
        if not truthy(open_value(kind)) then set_fx(kind) end
        save()
    end

    apply(cfg)
    sync_fx()
    run("sh", { "-c", READ }, function(out, code)
        if code == 0 and out and out ~= "" then
            local ok, saved = pcall(json.decode, out)
            if ok and type(saved) == "table" then
                apply(saved)
                sync_fx()
            else
                log("config.json could not be parsed; using defaults")
            end
        end
        save()
    end)

    --  Where this checkout lives, for the font Apply button's restart.  The
    --  launcher exports it; a scene started by hand simply saves without one.
    local shell_root = ""
    local start_settingskeys
    center.start(function() return shell_root end, function() set_fx("center_panel") end)
    run("sh", { "-c", 'printf %s "${PLEAMAR_SHELL_ROOT:-}"' }, function(out)
        if out then shell_root = tostring(out):gsub("%s+$", "") end
        center.refresh_root()
        start_settingskeys()
    end)

    --  Settings has two text fields (font search and weather city) but the
    --  main scene's layer surfaces do not receive layer keyboard focus.  A
    --  separate single-surface process owns the keyboard and relays the text.
    local settings_key_helper = nil
    local settings_key_field = nil
    local function stop_settingskeys()
        if settings_key_helper then
            kill(settings_key_helper, "term")
            settings_key_helper = nil
        end
        settings_key_field = nil
    end
    start_settingskeys = function()
        if not truthy(fact.panel_open) or shell_root == "" then
            stop_settingskeys()
            return
        end
        local page = math.floor(number(fact.settings_page, 0))
        local field, value
        if page == 9 then
            field, value = "weather_city", tostring(text.weather_city or "")
        elseif page == 3 then
            field, value = "font_query", tostring(text.font_query or "")
        else
            stop_settingskeys()
            return
        end
        if settings_key_helper and settings_key_field == field then return end
        stop_settingskeys()
        local parent = string.lower(tostring(text.layout or "island"))
        local cmd = "PLEAMAR_SETTINGS_PARENT=" .. sq(parent)
            .. " PLEAMAR_SETTINGS_FIELD=" .. sq(field)
            .. " PLEAMAR_SETTINGS_TEXT=" .. sq(value)
            .. " exec " .. sq(shell_root .. "/bin/pleamar-settingskeys")
        local mine
        local ok, id = pcall(spawn, "sh", { "-c", cmd }, function() end, function()
            if settings_key_helper == mine then
                settings_key_helper = nil
                settings_key_field = nil
            end
        end)
        if ok then
            settings_key_helper = id
            settings_key_field = field
            mine = id
        else
            log("settings key helper could not start: " .. tostring(id))
        end
    end

    --  The panel click is Vitreus's own `assets/panel.wav`; one at a time even
    --  when a click changes several things.
    local last_snd = 0
    local function play_panel_sound()
        if not truthy(fact.snd_on) or shell_root == "" then return end
        local now = os.clock()
        if now - last_snd < 0.25 then return end
        last_snd = now
        run("sh", { "-c", "pw-play --volume 0.25 " .. sq(shell_root .. "/assets/panel.wav") .. " >/dev/null 2>&1" }, function(_, code)
            if code ~= 0 then log("panel sound could not play") end
        end)
    end

    --  ── wallpaper ──────────────────────────────────────────────────────
    --  Vitreus drives awww and asks Iris for the palette.  This checkout
    --  drives swaybg (bin/pleamar-wall) and reads the palette with
    --  bin/pleamar-colors: set the picture, then recolour the bar, panels and
    --  launcher from its primary, exactly where the old aqua/azure lived.
    local function shq(v)
        return "'" .. tostring(v):gsub("'", "'\\''") .. "'"
    end

    --  ── idle ────────────────────────────────────────────────────────────
    --  swayidle owns the waiting; this only starts it with the two timers.
    --  There is no suspend timer: 0 is Never, and that is the whole contract.
    local idle_gen = 0
    local function apply_idle()
        if shell_root == "" then return end
        idle_gen = idle_gen + 1
        local mine = idle_gen
        after(250, function()
            if mine ~= idle_gen then return end
            local lock = math.floor(clamp(number(fact.idle_lock_seconds, 0), 0, 7200))
            local off = math.floor(clamp(number(fact.idle_off_seconds, 0), 0, 7200))
            local cmd = shq(shell_root .. "/bin/pleamar-idle") .. " " .. lock .. " " .. off
            run("sh", { "-c", cmd }, function(_, code)
                if code ~= 0 then log("idle timers could not be applied") end
            end)
        end)
    end
    after(1200, apply_idle)
    --  Keep the lock scene warm so its wallpaper is ready before the first
    --  lock; it draws nothing until `locked` is true.
    after(1500, function()
        if shell_root == "" then return end
        run("sh", { "-c", shq(shell_root .. "/bin/pleamar-lock") .. " ensure" }, function(_, code)
            if code ~= 0 then log("lock scene could not start") end
        end)
    end)
    local function basename(v)
        return tostring(v or ""):match("([^/]+)$") or ""
    end

    local wall_files = {}
    local wall_token, thumb_token, color_token = 0, 0, 0
    local show_wall_page, refresh_wallpapers, set_wallpaper, recolor
    local reset_wall_countdown, update_wall_next, start_wallpaper

    local THUMB_SCRIPT = table.concat({
        'cache="$HOME/.cache/pleamar-shell/wallpapers"',
        'mkdir -p "$cache" || exit 1',
        'for f in "$@"; do',
        '  h=$(printf %s "$f" | md5sum | cut -c1-16)',
        '  out="$cache/$h.jpg"',
        '  if [ ! -s "$out" ]; then',
        '    magick "$f[0]" -auto-orient -thumbnail 352x198^ -gravity center -extent 352x198 -quality 86 "$out" >/dev/null 2>&1 || true',
        '  fi',
        '  [ -s "$out" ] && printf "%s\\t%s\\n" "$out" "$f"',
        'done',
    }, "\n")

    local function recolor_now(path)
        color_token = color_token + 1
        local token = color_token
        if shell_root == "" then return end
        local cmd = shq(shell_root .. "/bin/pleamar-colors") .. " " .. shq(path) .. " 2>/dev/null"
        run("sh", { "-c", cmd }, function(out, code)
            if token ~= color_token or tostring(text.wallpaper or "") ~= path then return end
            if code ~= 0 or not out or out == "" then
                log("wallpaper colours could not be read: " .. tostring(path))
                return
            end
            local ok, pal = pcall(json.decode, out)
            if ok and type(pal) == "table" then
                set_palette(pal)
                write_palette(pal)
                save()
            else
                log("wallpaper colours were not JSON")
            end
        end)
    end
    recolor = recolor_now

    show_wall_page = function()
        local page = math.floor(clamp(number(fact.wp_page, 0), 0, 100000))
        local start = page * 9
        local picked = {}
        for i = start + 1, math.min(start + 9, #wall_files) do
            picked[#picked + 1] = wall_files[i]
        end
        if #picked == 0 then
            model.wp_rows = {}
            return
        end
        thumb_token = thumb_token + 1
        local token = thumb_token
        local args = { "-c", THUMB_SCRIPT, "pleamar-thumbs" }
        for _, p in ipairs(picked) do args[#args + 1] = p end
        run("sh", args, function(out, code)
            if token ~= thumb_token then return end
            if code ~= 0 or not out then
                log("wallpaper thumbnails could not be made")
                return
            end
            local thumbs = {}
            for line in string.gmatch(out, "[^\n]+") do
                local t, p = line:match("^([^\t]+)\t(.+)$")
                if t and p then thumbs[p] = t end
            end
            local rows = {}
            for _, p in ipairs(picked) do
                rows[#rows + 1] = {
                    thumb = thumbs[p] or "",
                    name = basename(p),
                    path = p,
                    cur = p == tostring(text.wallpaper or ""),
                }
            end
            model.wp_rows = rows
        end)
    end

    start_wallpaper = function(path)
        if shell_root == "" then
            log("started without PLEAMAR_SHELL_ROOT; external wallpaper is unavailable")
            return
        end
        local helper = shell_root .. "/bin/pleamar-wall"
        run("sh", { "-c", shq(helper) .. " " .. shq(path) }, function(_, code)
            if tostring(text.wallpaper or "") ~= path then return end
            if code ~= 0 then log("swaybg could not start; wallpaper unchanged") end
        end)
    end

    set_wallpaper = function(path, persist)
        path = tostring(path or "")
        if path == "" then return end
        text.wallpaper = path
        text.wall_name = basename(path)
        cfg.wallpaper = path
        if persist then save() end
        show_wall_page()
        recolor(path)
        if truthy(fact.wall_auto) and reset_wall_countdown then reset_wall_countdown() end
        start_wallpaper(path)
    end

    refresh_wallpapers = function()
        wall_token = wall_token + 1
        local token = wall_token
        local dir_arg = tostring(cfg.wallpaper_dir or "")
        local script = table.concat({
            'dir=' .. shq(dir_arg),
            '[ -n "$dir" ] || dir="$HOME/Pictures/Wallpapers"',
            'printf "__DIR__\\t%s\\n" "$dir"',
            'find "$dir" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.avif" \\) -print | sort',
        }, "\n")
        run("sh", { "-c", script }, function(out, code)
            if token ~= wall_token then return end
            if code ~= 0 or not out then
                log("wallpaper folder could not be read")
                return
            end
            local dir = ""
            local files = {}
            for line in string.gmatch(out, "[^\n]+") do
                local d = line:match("^__DIR__\t(.+)$")
                if d then
                    dir = d
                elseif line:match("^/") then
                    files[#files + 1] = line
                end
            end
            wall_files = files
            text.wallpaper_dir = dir
            fact.wp_pages = math.max(1, math.ceil(#files / 9))
            if fact.wp_page >= fact.wp_pages then fact.wp_page = fact.wp_pages - 1 end
            if fact.wp_page < 0 then fact.wp_page = 0 end
            text.wall_count = #files == 0 and "No wallpapers" or (#files .. " wallpapers")

            local current = tostring(text.wallpaper or "")
            local found, at = false, 0
            for i, p in ipairs(files) do
                if p == current then found, at = true, i break end
            end
            if found then
                --  Open the picker on the page the picture in use is on, as
                --  Vitreus's picker does.
                fact.wp_page = math.floor((at - 1) / 9)
            end
            if not found then current = files[1] or "" end
            if current ~= "" then
                --  A saved path that vanished (or a fresh install) falls back
                --  to the first picture, and the picker shows the selection.
                set_wallpaper(current, true)
            else
                text.wallpaper = ""
                text.wall_name = ""
                model.wp_rows = {}
            end
            if truthy(fact.wall_auto) then reset_wall_countdown() end
        end)
    end

    --  A slideshow counts whole minutes, in the folder's sorted order.  It
    --  only starts when the picker's Auto rotate switch is on.
    reset_wall_countdown = function()
        fact.wall_remain = math.floor(clamp(number(fact.wall_minutes, 5), 1, 60))
        if update_wall_next then update_wall_next() end
    end
    update_wall_next = function()
        if not truthy(fact.wall_auto) then
            text.wall_next = "Auto rotation off"
        else
            local remain = math.max(0, math.floor(number(fact.wall_remain, 0)))
            text.wall_next = remain > 0
                and string.format("Next in %d min", remain)
                or "Next in less than a minute"
        end
    end
    local function next_wallpaper()
        if #wall_files == 0 then return end
        local current = tostring(text.wallpaper or "")
        local at = 0
        for i, p in ipairs(wall_files) do
            if p == current then at = i break end
        end
        local next = wall_files[(at % #wall_files) + 1]
        if next then set_wallpaper(next, true) end
    end
    every(60000, function()
        if not truthy(fact.wall_auto) or #wall_files == 0 then return end
        local remain = math.floor(number(fact.wall_remain, 0))
        if remain > 1 then
            fact.wall_remain = remain - 1
            update_wall_next()
        else
            next_wallpaper()
        end
    end)

    after(200, function() refresh_wallpapers() end)

    --  ── notifications ──────────────────────────────────────────────────
    --  Pleamar is the org.freedesktop.Notifications server.  The logic keeps
    --  its own history and decides when a toast is shown; the service keeps
    --  the live record so actions can be invoked.
    local NT_SOUNDS = {
        { "message-new-instant", "Message" }, { "message", "Soft" }, { "bell", "Bell" },
        { "dialog-information", "Info" }, { "complete", "Done" }, { "device-added", "Device" },
        { "alarm-clock-elapsed", "Alarm" }, { "dialog-warning", "Warning" },
    }
    local nt_hist, nt_seen, nt_queue = {}, {}, {}
    local nt_now, nt_first = nil, true
    local nt_timer, nt_total, nt_left = nil, 6, 6
    local function nt_clean(v)
        return ((v or ""):gsub("<[^>]*>", ""):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"))
    end
    local function nt_clock(t)
        if type(t) == "number" and t > 0 then return os.date("%H:%M", t) end
        return os.date("%H:%M")
    end
    local function nt_save_hist()
        local rows = {}
        for i = 1, math.min(#nt_hist, 8) do
            local h = nt_hist[i]
            rows[i] = { app = h.app, title = h.title, body = h.body, when = h.when, urgent = h.urgent }
        end
        model.nt_history = rows
    end
    local function nt_add_hist(n)
        table.insert(nt_hist, 1, {
            id = n.id,
            app = nt_clean(n.app ~= "" and n.app or "System"),
            title = nt_clean(n.title ~= "" and n.title or "Notification"),
            body = nt_clean(n.body),
            when = nt_clock(n.time), urgent = tostring(n.urgency) == "critical" or tostring(n.urgency) == "2",
        })
        while #nt_hist > 30 do table.remove(nt_hist) end
        fact.nt_unread = number(fact.nt_unread, 0) + 1
        nt_save_hist()
    end
    local function nt_sound(idx)
        if not truthy(fact.nt_snd_on) or shell_root == "" then return end
        local s = NT_SOUNDS[math.floor(number(idx, 1))] or NT_SOUNDS[1]
        run("sh", { "-c", "pw-play --volume 0.7 " .. sq(shell_root .. "/assets/sounds/" .. s[1] .. ".oga") .. " >/dev/null 2>&1" }, function(_, code)
            if code ~= 0 then log("notification sound could not play") end
        end)
    end
    local function nt_cancel_timer()
        if nt_timer then
            cancel(nt_timer)
            nt_timer = nil
        end
    end
    local function nt_finish()
        local n = nt_now
        nt_cancel_timer()
        nt_now = nil
        if truthy(fact.nt_has) then fact.nt_has = false end
        fact.nt_timed = false
        fact.nt_left = 1
        text.nt_countdown = ""
        if n then pcall(sys.call, "notifications.dismiss", n.id) end
        --  The queue is pumped by the timer below; calling a timer API from
        --  the close event handler has been unreliable here.
    end
    local function nt_tick(id)
        nt_timer = nil
        if not nt_now or nt_now.id ~= id or not truthy(fact.nt_timed) then return end
        nt_left = nt_left - 0.05
        if nt_left <= 0 then
            fact.nt_left = 0
            text.nt_countdown = "0s"
            nt_finish()
            return
        end
        fact.nt_left = clamp(nt_left / nt_total, 0, 1)
        local label = tostring(math.max(1, math.ceil(nt_left))) .. "s"
        if text.nt_countdown ~= label then text.nt_countdown = label end
        nt_timer = after(50, function() nt_tick(id) end)
    end
    local function show_nt(n)
        if nt_now then table.insert(nt_queue, 1, n) return end
        nt_cancel_timer()
        nt_now = n
        set_fx("toast")
        fact.nt_has = true
        fact.nt_timed = false
        fact.nt_left = 1
        text.nt_countdown = ""
        fact.nt_urgent = tostring(n.urgency) == "critical" or tostring(n.urgency) == "2"
        text.nt_app = nt_clean(n.app ~= "" and n.app or "System"):upper()
        text.nt_title = nt_clean(n.title ~= "" and n.title or "Notification")
        text.nt_body = nt_clean(n.body)
        text.nt_time = nt_clock(n.time)
        text.nt_icon = tostring(n.icon or "")
        fact.nt_icon_on = text.nt_icon ~= ""
        fact.nt_new = number(fact.nt_new, 0) + 1
        local acts = {}
        for _, a in ipairs(n.actions or {}) do
            if a.key ~= "default" and a.label and a.label ~= "" and #acts < 3 then
                acts[#acts + 1] = { label = a.label }
            end
        end
        model.nt_actions = acts
        if truthy(fact.nt_dnd) then
            fact.nt_has = false
            nt_now = nil
            pcall(sys.call, "notifications.dismiss", n.id)
            return
        end
        nt_sound(fact.nt_sound)
        if not truthy(fact.nt_urgent) then
            nt_total = math.floor(clamp(number(fact.nt_secs, cfg.nt_secs), 2, 60))
            nt_left = nt_total
            fact.nt_timed = true
            text.nt_countdown = tostring(nt_total) .. "s"
            nt_timer = after(50, function() nt_tick(n.id) end)
        end
    end
    local function nt_pump()
        if nt_now or #nt_queue == 0 then return end
        show_nt(table.remove(nt_queue, 1))
    end
    every(100, function()
        if not nt_now and #nt_queue > 0 then nt_pump() end
    end)
    local nt_watch = sys.watch("notifications", function(list)
        if not list then return end
        local oldest = true
        for i = #list, 1, -1 do
            local n = list[i]
            if not nt_seen[n.id] then
                nt_seen[n.id] = true
                nt_add_hist(n)
                if nt_first then
                    pcall(sys.call, "notifications.dismiss", n.id)   -- backlog from before login
                elseif truthy(fact.nt_dnd) then
                    pcall(sys.call, "notifications.dismiss", n.id)
                else
                    nt_queue[#nt_queue + 1] = n
                end
                oldest = false
            end
        end
        nt_first = false
        nt_pump()
    end)
    if not nt_watch then log("the notifications service is not available") end
    pcall(sys.call, "notifications.keep", true)
    nt_save_hist()

    --  The toast anchor and the names shown by the settings page.
    local function nt_set_anchor()
        fact.nt_anchor = (number(fact.nt_pos, 1) == 0) and "top" or "top_right"
        text.nt_pos_name = (number(fact.nt_pos, 1) == 0) and "Top center" or "Top right"
    end
    local function nt_set_sound_name()
        local s = NT_SOUNDS[math.floor(number(fact.nt_sound, 1))] or NT_SOUNDS[1]
        text.nt_sound_name = s[2]
    end
    nt_set_anchor()
    nt_set_sound_name()
    after(500, function() nt_set_anchor(); nt_set_sound_name() end)

    --  ── quiet: the scene only runs hot while the water can move ─────────
    local function recompute_quiet()
        local playing = truthy(fact.wave_on) and truthy(fact.music_on)
        local open = truthy(fact.panel_open) or truthy(fact.launch_open)
        local q = (not playing) and (not open)
        if truthy(fact.quiet) ~= q then fact.quiet = q end
    end
    recompute_quiet()

    --  A bar that appears under the pointer can receive the tail of a click
    --  meant for the window beneath it.  The scene takes its own presses only
    --  once this is true.
    after(500, function() fact.ready = true end)

    --  ── cava ────────────────────────────────────────────────────────────
    --  One line per frame: 24 bars, 0..1000.  Six groups of four, peak of the
    --  group, square-rooted so quiet mids still move the water.
    local CAVA_CONF = table.concat({
        "[general]",
        "bars = 24",
        "framerate = 60",
        "[input]",
        "method = pipewire",
        "[smoothing]",
        "noise_reduction = 10",
        "[output]",
        "method = raw",
        "raw_target = /dev/stdout",
        "data_format = ascii",
        "ascii_max_range = 1000",
        "bar_delimiter = 59",
        "frame_delimiter = 10",
    }, "\n") .. "\n"

    local cava = nil
    local cava_conf = nil
    local last_bands = { 0, 0, 0, 0, 0, 0 }
    --  Per-band envelope followers.  Cava's raw values are relative to the
    --  whole recording, so loud tracks saturate 1.0 and the old gain could
    --  not alter them.  Normalising each bar against its recent peak makes
    --  the beats visible on quiet and loud tracks alike; wave_gain then
    --  shapes how much of the quieter part of that envelope survives.
    local peaks = { 0, 0, 0, 0, 0, 0 }
    local silence = 0

    local function set_band(k, v)
        if math.abs(v - last_bands[k]) > 0.008 then
            last_bands[k] = v
            fact["bands." .. (k - 1)] = v
        end
    end

    local function reset_bands()
        for k = 1, 6 do
            set_band(k, 0)
            peaks[k] = 0
        end
        if truthy(fact.music_on) then fact.music_on = false end
        silence = 0
        recompute_quiet()
    end

    local function stop_cava()
        if cava then
            kill(cava, "term")
            cava = nil
        end
        reset_bands()
    end

    local function start_cava()
        if cava or not cava_conf then return end
        for k = 1, 6 do peaks[k] = 0 end
        local mine
        mine = spawn("cava", { "-p", cava_conf }, function(line)
            if cava ~= mine then return end
            local raw = {}
            for v in string.gmatch(line, "(%d+);") do
                raw[#raw + 1] = number(v, 0) / 1000
            end
            if #raw < 6 then return end

            local peak = 0
            local gain = clamp(number(fact.wave_gain, 1.4), 0.8, 2.4)
            for k = 1, 6 do
                local m = 0
                for j = (k - 1) * 4 + 1, k * 4 do
                    m = m + (raw[j] or 0)
                end
                m = m / 4
                --  Fast attack, slower tail: the peak jumps to a beat and
                --  falls by ~8% per cava frame (60 fps), about half a second.
                if m > peaks[k] then
                    peaks[k] = m
                else
                    peaks[k] = peaks[k] * 0.92
                end
                local norm = clamp(m / math.max(peaks[k], 0.035), 0, 1)
                local v = math.min(1, (norm ^ (1 / gain)) * 0.9)
                set_band(k, v)
                if v > peak then peak = v end
            end

            if peak > 0.02 then
                silence = 0
                if not truthy(fact.music_on) then
                    fact.music_on = true
                    recompute_quiet()
                end
            else
                silence = silence + 1
                --  cava runs at 60 fps.  The old threshold of 30 held the
                --  last frame for half a second after the music stopped;
                --  three silent frames (~50 ms) are enough to avoid a
                --  one-frame dropout without a visible tail.
                if silence > 3 and truthy(fact.music_on) then
                    for k = 1, 6 do set_band(k, 0) end
                    fact.music_on = false
                    recompute_quiet()
                end
            end
        end, function()
            if cava == mine then cava = nil end
        end)
        cava = mine
    end

    local folder = sys.ask("files.folder")
    if folder and folder ~= "" then
        folder = tostring(folder):gsub("%s+$", "")
        cava_conf = folder .. "/cava.conf"
        local wrote, err = pcall(sys.call, "files.write", "cava.conf", CAVA_CONF)
        if not wrote then log("cava.conf could not be saved: " .. tostring(err)) end
    else
        log("no scene data folder; cava cannot start")
    end

    --  Start when the waves are on; stop when they are not.  The timer restarts
    --  cava if it ever leaves on its own.
    local function cava_want()
        if truthy(fact.wave_on) then
            start_cava()
        else
            stop_cava()
        end
    end
    cava_want()
    every(5000, function()
        if truthy(fact.wave_on) and not cava then start_cava() end
    end)

    --  ── launcher: one search for apps, files, commands, emoji, clipboard,
    --  wallpapers, windows, the web and arithmetic.  The prefixes are
    --  Vitreus's; the result rows carry an action closure and the scene only
    --  draws their fields.
    local all_apps = {}
    local results = {}
    local search_token = 0
    local emoji = nil
    local emoji_loading = false

    local MODE = { ["#"] = "files", [">"] = "commands", [":"] = "emoji", ["^"] = "clipboard",
                   ["~"] = "wallpapers", ["@"] = "windows", ["?"] = "web", ["!"] = "web", ["="] = "calc" }
    local MODE_LABEL = { apps = "APPS", files = "FILES", commands = "COMMANDS", emoji = "EMOJI",
                         clipboard = "CLIPBOARD", wallpapers = "WALLPAPERS", windows = "WINDOWS",
                         web = "WEB", calc = "CALC" }
    local HINT = "Apps · # files · > commands · : emoji · ^ clip · ~ walls · @ windows · ? web · = calc"

    local function clean_q(q)
        return (tostring(q or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end
    local function shell(cmd, cb)
        run("sh", { "-c", cmd }, cb or function() end)
    end
    local function open_url(url)
        shell("xdg-open " .. shq(url) .. " >/dev/null 2>&1")
    end
    local function urlenc(v)
        return (tostring(v):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
    end
    local function row(name, sub, kind, glyph, run_fn, icon, exec)
        return { name = name, sub = sub or "", kind = kind or "", glyph = glyph or "",
                 has_glyph = (glyph or "") ~= "", run = run_fn, icon = icon or "", exec = exec or "" }
    end
    local function set_rows(list, mode, msg)
        results = list or {}
        local rows = {}
        for i = 1, math.min(#results, 8) do
            local r = results[i]
            rows[i] = { name = r.name, sub = r.sub, exec = r.exec, icon = r.icon,
                        glyph = r.glyph, has_glyph = r.has_glyph, kind = r.kind }
        end
        model.la_apps = rows
        fact.la_sel = 0
        text.la_mode = MODE_LABEL[mode] or "SEARCH"
        text.la_hint = msg or HINT
    end
    local function run_result(i)
        local r = results[i]
        if not r or not r.run then return end
        r.run()
        if truthy(fact.launch_open) then fact.launch_open = false end
    end

    -- ── apps ──
    local function app_row(a)
        local name = tostring(a.name or a.local_name or a.id or "?")
        local desc = tostring(a.comment or a.generic_name or "")
        local icon = tostring(a.icon or "")
        local glyph = icon == "" and name:sub(1, 1):upper() or ""
        return row(name, desc, "APP", glyph, function()
            local exec = tostring(a.exec or "")
            if exec ~= "" then
                local ok, err = pcall(sys.call, "apps.launch", exec)
                if not ok then log("app launch failed: " .. tostring(err)) end
            end
        end, icon, a.exec)
    end
    local function search_apps(q)
        local ql = q:lower()
        local out = {}
        if ql == "" then
            for i, a in ipairs(all_apps) do
                out[#out + 1] = app_row(a)
                if #out >= 8 then break end
            end
            return out
        end
        local scored = {}
        for _, a in ipairs(all_apps) do
            local name = tostring(a.name or a.local_name or ""):lower()
            local fields = tostring(a.id or "") .. " " .. tostring(a.wmclass or "") .. " "
                .. tostring(a.comment or "") .. " " .. tostring(a.generic_name or "") .. " "
                .. tostring(a.keywords or "") .. " " .. tostring(a.categories or "")
            local sc = 0
            if name == ql then sc = 100
            elseif name:sub(1, #ql) == ql then sc = 80
            elseif name:find(ql, 1, true) then sc = 60
            elseif fields:lower():find(ql, 1, true) then sc = 30 end
            if sc > 0 then scored[#scored + 1] = { a = a, sc = sc } end
        end
        table.sort(scored, function(x, y)
            if x.sc ~= y.sc then return x.sc > y.sc end
            return tostring(x.a.name or ""):lower() < tostring(y.a.name or ""):lower()
        end)
        for i = 1, math.min(#scored, 8) do out[i] = app_row(scored[i].a) end
        return out
    end

    -- ── arithmetic and a few everyday conversions ──
    local function calc(src)
        local pos, s = 1, src:gsub("%s+", ""):lower()
        local function peek() return s:sub(pos, pos) end
        local expr
        local FUN = { sqrt = math.sqrt, sin = math.sin, cos = math.cos, tan = math.tan, abs = math.abs,
                      floor = math.floor, ceil = math.ceil, log = math.log10, ln = math.log,
                      round = function(v) return math.floor(v + 0.5) end }
        local function atom()
            local c = peek()
            if c == "(" then pos = pos + 1; local v = expr(); if peek() ~= ")" then error("paren") end; pos = pos + 1; return v
            elseif c == "-" then pos = pos + 1; return -atom()
            elseif c == "+" then pos = pos + 1; return atom() end
            local num = s:match("^%d*%.?%d+", pos)
            if num then pos = pos + #num; return tonumber(num) end
            local id = s:match("^%a+", pos)
            if id then
                pos = pos + #id
                if id == "pi" then return math.pi elseif id == "e" then return math.exp(1) end
                local f = FUN[id]
                if not f or peek() ~= "(" then error("name") end
                pos = pos + 1; local v = expr()
                if peek() ~= ")" then error("paren") end
                pos = pos + 1; return f(v)
            end
            error("token")
        end
        local function pow()
            local v = atom()
            if peek() == "^" then pos = pos + 1; return v ^ pow() end
            return v
        end
        local function term()
            local v = pow()
            while true do
                local c = peek()
                if c == "*" then pos = pos + 1; v = v * pow()
                elseif c == "/" then pos = pos + 1; v = v / pow()
                elseif c == "%" then pos = pos + 1; v = v % pow()
                else return v end
            end
        end
        expr = function()
            local v = term()
            while true do
                local c = peek()
                if c == "+" then pos = pos + 1; v = v + term()
                elseif c == "-" then pos = pos + 1; v = v - term()
                else return v end
            end
        end
        local v = expr()
        if pos <= #s then error("trailing") end
        return v
    end
    local function calc_row(q)
        if not q:find("%d") then return nil end
        if q:find("[^%d%a%s%.%+%-%*/%%%^%(%)]") then return nil end
        local ok, v = pcall(calc, q)
        if not ok or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
        local str = string.format("%.10g", v)
        return row("= " .. str, q .. "  ·  Enter copies", "CALC", "=", function()
            shell("printf %s " .. shq(str) .. " | wl-copy")
        end)
    end
    local U = {
        m = { "len", 1 }, km = { "len", 1000 }, cm = { "len", .01 }, mm = { "len", .001 },
        mi = { "len", 1609.344 }, ft = { "len", .3048 }, ["in"] = { "len", .0254 }, yd = { "len", .9144 },
        kg = { "mass", 1 }, g = { "mass", .001 }, mg = { "mass", .000001 }, lb = { "mass", .45359237 }, oz = { "mass", .028349523 },
        l = { "vol", 1 }, ml = { "vol", .001 }, gal = { "vol", 3.785411784 }, qt = { "vol", .946352946 },
        b = { "data", 1 }, kb = { "data", 1000 }, mb = { "data", 1000000 }, gb = { "data", 1000000000 },
        kib = { "data", 1024 }, mib = { "data", 1048576 }, gib = { "data", 1073741824 },
        s = { "time", 1 }, min = { "time", 60 }, h = { "time", 3600 }, d = { "time", 86400 },
        kmh = { "speed", 1 / 3.6 }, mph = { "speed", .44704 }, mps = { "speed", 1 },
    }
    local TEMP = { c = true, f = true, k = true }
    local function unit_row(q)
        local s = q:lower():gsub(",", ""):gsub("°", "")
        local p, of = s:match("^([%d%.]+)%%%s*of%s+([%d%.]+)$")
        if p and tonumber(p) and tonumber(of) then
            local str = string.format("%.6g", tonumber(p) * tonumber(of) / 100)
            return row("= " .. str, p .. "% of " .. of .. "  ·  Enter copies", "CALC", "%", function()
                shell("printf %s " .. shq(str) .. " | wl-copy")
            end)
        end
        local n, a, b = s:match("^(%-?[%d%.]+)%s*([%a/%d]+)%s+to%s+([%a/%d]+)$")
        if not n then n, a, b = s:match("^(%-?[%d%.]+)%s*([%a/%d]+)%s+in%s+([%a/%d]+)$") end
        if not n then n, a, b = s:match("^(%-?[%d%.]+)%s*([%a/%d]+)%s+as%s+([%a/%d]+)$") end
        if not n then return nil end
        local v = tonumber(n)
        if not v then return nil end
        local out
        if TEMP[a] and TEMP[b] then
            local k = a == "c" and v + 273.15 or (a == "f" and (v - 32) * 5 / 9 + 273.15 or v)
            out = b == "c" and k - 273.15 or (b == "f" and (k - 273.15) * 9 / 5 + 32 or k)
        else
            local ua, ub = U[a], U[b]
            if not ua or not ub or ua[1] ~= ub[1] then return nil end
            out = v * ua[2] / ub[2]
        end
        local str = string.format("%.6g", out)
        return row("= " .. str .. " " .. b, n .. " " .. a .. " → " .. b .. "  ·  Enter copies", "CALC", "=", function()
            shell("printf %s " .. shq(str) .. " | wl-copy")
        end)
    end

    -- ── commands ──
    local function open_page(page)
        return function() fact.settings_page = page; fact.panel_open = true; fact.launch_open = false end
    end
    local COMMANDS = {
        { "Settings: Wallpaper", "open", open_page(4), "background picture image colors palette" },
        { "Settings: Glass", "open", open_page(1), "blur transparency frosted glass look" },
        { "Settings: Bar", "open", open_page(2), "height sound panel" },
        { "Settings: Font", "open", open_page(3), "typeface text" },
        { "Settings: Frame music", "open", open_page(0), "wave water amplitude sensitivity" },
        { "Settings: Lock screen", "open", open_page(7), "lock password blur clock date mask" },
        { "Settings: Idle", "open", open_page(8), "idle lock screen off timeout seconds swayidle" },
        { "Panel sound: toggle", "action", function() fact.snd_on = not truthy(fact.snd_on) end, "click audio mute" },
        { "Frame music: toggle", "action", function() fact.wave_on = not truthy(fact.wave_on) end, "wave water audio" },
        { "Wallpaper: next", "action", function() next_wallpaper() end, "background picture next rotate" },
        { "Screenshot", "action", function() shell("niri msg action screenshot-screen") end, "capture image screen" },
        { "Home folder", "action", function() shell("xdg-open " .. shq("$HOME") .. " >/dev/null 2>&1") end, "files folder documents" },
        { "Terminal", "action", function() shell("setsid -f kitty >/dev/null 2>&1") end, "shell command term" },
        { "Notification test", "action", function() shell("notify-send -a pleamar-shell 'Notification test' 'This is how a notification looks and sounds.'") end, "notify test audio" },
    }
    local function search_commands(q)
        local out, ql = {}, q:lower()
        for _, c in ipairs(COMMANDS) do
            if ql == "" or c[1]:lower():find(ql, 1, true) or c[2]:lower():find(ql, 1, true) or c[4]:find(ql, 1, true) then
                out[#out + 1] = row(c[1], c[2], "COMMAND", ">", c[3])
            end
        end
        return out
    end

    -- ── emoji, clipboard, files, windows, wallpapers, web ──
    local function search_emoji(q, done)
        local function go()
            local out, ql = {}, q:lower()
            for i = 1, #emoji do
                local e = emoji[i]
                local name = tostring(e.n or e.name or "")
                local keys = tostring((e.k or "") .. " " .. tostring(e.g or ""))
                if ql == "" or name:lower():find(ql, 1, true) or keys:lower():find(ql, 1, true) or tostring(e.c or "") == q then
                    local char = tostring(e.c or "")
                    out[#out + 1] = row(char, name, "EMOJI", char, function()
                        shell("printf %s " .. shq(char) .. " | wl-copy")
                    end)
                    if #out >= 8 then break end
                end
            end
            done(out)
        end
        if emoji then return go() end
        done({}, "Reading emoji…")
        if not emoji_loading then
            emoji_loading = true
            shell('cat "${PLEAMAR_SHELL_ROOT:-.}/assets/emoji.json"', function(out)
                emoji_loading = false
                local ok, list = pcall(json.decode, out or "[]")
                if ok and type(list) == "table" then emoji = list; search_now() end
            end)
        end
    end
    local function search_clip(q, done)
        shell("cliphist list 2>/dev/null | head -80", function(out)
            local rows, ql = {}, q:lower()
            for line in (out or ""):gmatch("[^\n]+") do
                local id, textv = line:match("^(%d+)\t(.*)$")
                if id and (ql == "" or textv:lower():find(ql, 1, true)) then
                    local img = textv:find("^%[%[ binary data") ~= nil
                    rows[#rows + 1] = row(img and "Copied image" or textv, img and "image" or "text", "CLIP",
                        img and "▣" or "T", function()
                            shell("printf '%s\\t' " .. shq(id) .. " | cliphist decode | wl-copy")
                        end)
                    if #rows >= 8 then break end
                end
            end
            done(rows, #rows == 0 and "Clipboard history is empty" or nil)
        end)
    end
    local function search_files(q, done)
        if #q < 2 then return done({}, "Type two letters to search files") end
        shell('find "$HOME" -maxdepth 5 -type f -iname ' .. shq("*" .. q .. "*") .. ' -print 2>/dev/null | head -60', function(out)
            local rows = {}
            for path in (out or ""):gmatch("[^\n]+") do
                local name = path:match("([^/]+)$") or path
                local dir = path:match("^(.*)/[^/]*$") or ""
                rows[#rows + 1] = row(name, dir, "FILE", "F", function()
                    shell("xdg-open " .. shq(path) .. " >/dev/null 2>&1")
                end)
                if #rows >= 8 then break end
            end
            done(rows, #rows == 0 and "No file matches" or nil)
        end)
    end
    local function search_windows(q, done)
        shell("niri msg --json windows 2>/dev/null", function(out)
            local ok, list = pcall(json.decode, out or "[]")
            local rows, ql = {}, q:lower()
            if ok and type(list) == "table" then
                for _, w in ipairs(list) do
                    local title = tostring(w.title or "")
                    local app = tostring(w.app_id or "")
                    if ql == "" or (title .. " " .. app):lower():find(ql, 1, true) then
                        rows[#rows + 1] = row(title ~= "" and title or app, app, "WINDOW", "W", function()
                            shell("niri msg action focus-window --id " .. tostring(w.id))
                        end)
                        if #rows >= 8 then break end
                    end
                end
            end
            done(rows, "No window matches")
        end)
    end
    local function search_wallpapers(q)
        local rows, ql = {}, q:lower()
        for _, path in ipairs(wall_files) do
            local name = path:match("([^/]+)$") or path
            if ql == "" or name:lower():find(ql, 1, true) then
                rows[#rows + 1] = row(name, path, "WALLPAPER", "W", function() set_wallpaper(path, true) end)
                if #rows >= 8 then break end
            end
        end
        return rows
    end
    local BANGS = {
        { "ddg", "DuckDuckGo", "https://duckduckgo.com/?q=%s" },
        { "g", "Google", "https://www.google.com/search?q=%s" },
        { "yt", "YouTube", "https://www.youtube.com/results?search_query=%s" },
        { "gh", "GitHub", "https://github.com/search?q=%s" },
        { "w", "Wikipedia", "https://en.wikipedia.org/w/index.php?search=%s" },
        { "aw", "Arch Wiki", "https://wiki.archlinux.org/index.php?search=%s" },
        { "so", "Stack Overflow", "https://stackoverflow.com/search?q=%s" },
    }
    local BANG = {}
    for _, b in ipairs(BANGS) do BANG[b[1]] = b end
    local function search_web(raw, done)
        local q = clean_q(raw):gsub("^%?%s*", "")
        if q:sub(1, 1) == "!" then
            local name, rest = q:match("^!(%S+)%s*(.*)$")
            if name and BANG[name] then return search_web("!" .. name .. " " .. rest, done) end
            local site = BANG[name or "ddg"] or BANG.ddg
            q = clean_q(name and rest or q)
            local url = string.format(site[3], urlenc(q))
            done({ row("Search " .. site[2] .. " for “" .. q .. "”", "Enter opens the browser", "WEB", "?", function() open_url(url) end) })
            return
        end
        if q == "" then
            local rows = {}
            for _, b in ipairs(BANGS) do
                rows[#rows + 1] = row("!" .. b[1] .. "  " .. b[2], "Type !" .. b[1] .. " then what to look for", "WEB", "!", function()
                    text.query = "!" .. b[1] .. " "; fact.launch_open = true
                end)
            end
            return done(rows)
        end
        done({ row("Search the web for “" .. q .. "”", "Enter opens DuckDuckGo", "WEB", "?", function()
            open_url("https://duckduckgo.com/?q=" .. urlenc(q))
        end) })
    end

    local function search_now()
        search_token = search_token + 1
        local tok = search_token
        local raw = tostring(text.query or "")
        local first = raw:sub(1, 1)
        local mode = MODE[first] or "apps"
        local q = clean_q(MODE[first] and raw:sub(2) or raw)
        local function done(list, msg) if tok == search_token then set_rows(list, mode, msg) end end
        if mode == "apps" then
            local c = unit_row(q) or calc_row(q)
            local list = search_apps(q)
            local out = {}
            if c then out[1] = c end
            for _, r in ipairs(list) do out[#out + 1] = r end
            return done(out, HINT)
        elseif mode == "files" then return search_files(q, done)
        elseif mode == "commands" then return done(search_commands(q), HINT)
        elseif mode == "emoji" then return search_emoji(q, done)
        elseif mode == "clipboard" then return search_clip(q, done)
        elseif mode == "wallpapers" then return done(search_wallpapers(q), HINT)
        elseif mode == "windows" then return search_windows(q, done)
        elseif mode == "web" then return search_web(raw, done)
        elseif mode == "calc" then
            local c = unit_row(q) or calc_row(q)
            return done(c and { c } or {}, "Try: 2+2, 15% of 80, 5 km to mi")
        end
    end

    local watched = sys.watch("apps", function(list)
        all_apps = list or {}
        if truthy(fact.launch_open) then search_now() end
    end)
    if not watched then log("the apps service is not available") end
    after(400, function()
        shell('cat "${PLEAMAR_SHELL_ROOT:-.}/assets/emoji.json"', function(out)
            local ok, list = pcall(json.decode, out or "[]")
            if ok and type(list) == "table" then emoji = list end
        end)
    end)
    --  ── fonts ───────────────────────────────────────────────────────────
    --  The settings page shows ten matches at a time; the search field narrows
    --  the installed families.  Applying one saves it and restarts the shell,
    --  because pleamar resolves family names when a process starts.
    local all_fonts = {}

    local function refresh_fonts()
        local q = string.lower(tostring(text.font_query or ""))
        local out = {}
        for i = 1, #all_fonts do
            local name = all_fonts[i]
            if q == "" or string.find(string.lower(name), q, 1, true) then
                out[#out + 1] = { name = name }
                if #out >= 10 then break end
            end
        end
        model.font_rows = out
    end

    run("sh", { "-c", "fc-list -f '%{family}\\n' | cut -d, -f1 | sort -u" }, function(out, code)
        if code ~= 0 or not out then
            log("installed fonts could not be listed")
            return
        end
        local seen = {}
        for line in string.gmatch(out, "[^\n]+") do
            line = line:gsub("%s+$", "")
            if line ~= ""
                and not line:match("^Material Symbols")
                and not line:match("^Noto Color Emoji")
                and not seen[line] then
                seen[line] = true
                all_fonts[#all_fonts + 1] = line
            end
        end
        refresh_fonts()
    end)

    --  ── facts and events ────────────────────────────────────────────────
    on("fact:wave_on", function()
        save()
        cava_want()
        recompute_quiet()
    end)
    on("fact:bar_height", function() save() end)
    on("fact:glass_on", function() save() end)
    on("fact:glass_bend", function() save() end)
    on("fact:glass_refr", function() save() end)
    on("fact:glass_disp", function() save() end)
    on("fact:glass_dome", function() save() end)
    on("fact:glass_milk", function() save() end)
    on("fact:glass_tint", function() save() end)
    on("fact:glass_frost", function() save() end)
    on("fact:glass_edge", function() save() end)
    on("fact:wave_depth", function() save() end)
    on("fact:wave_blend", function() save() end)
    on("fact:wave_gain", function() save() end)
    on("fact:wave_amp", function() save() end)
    on("fact:wave_ripples", function() save() end)
    on("fact:wave_height", function() save() end)
    on("fact:lock_blur", function() save() end)
    on("fact:lock_12h", function() save() end)
    on("fact:lock_ampm", function() save() end)
    on("fact:lock_media", function() save() end)
    on("fact:lock_secs", function() save() end)
    on("fact:lock_power", function() save() end)
    on("fact:lock_px", function() save() end)
    on("fact:lock_date", function() save() end)
    on("fact:lock_mask", function() save() end)
    on("fact:lock_pal", function() save() end)
    on("fact:idle_lock_i", function(v)
        local i = math.floor(clamp(number(v, 0), 0, #IDLE_STEPS - 1))
        fact.idle_lock_seconds = IDLE_STEPS[i + 1]
        text.idle_lock_t = idle_words(IDLE_STEPS[i + 1])
        save()
        apply_idle()
    end)
    on("fact:idle_off_i", function(v)
        local i = math.floor(clamp(number(v, 0), 0, #IDLE_STEPS - 1))
        fact.idle_off_seconds = IDLE_STEPS[i + 1]
        text.idle_off_t = idle_words(IDLE_STEPS[i + 1])
        save()
        apply_idle()
    end)
    on("fact:panel_open", function()
        if truthy(fact.panel_open) then
            set_fx("panel")
            if truthy(fact.center_open) then center.close() end
            start_settingskeys()
        else
            stop_settingskeys()
        end
        recompute_quiet()
    end)
    on("fact:settings_page", function()
        if truthy(fact.panel_open) then start_settingskeys() end
    end)
    on("settings_close", function()
        fact.panel_open = false
        stop_settingskeys()
    end)
    on("fact:launch_open", function()
        if truthy(fact.launch_open) then
            stop_settingskeys()
            set_fx("search")
            text.query = ""
            search_now()
            if truthy(fact.center_open) then center.close() end
        end
        recompute_quiet()
    end)
    on("fact:anim_search", function() config_changed("search") end)
    on("fact:anim_panel", function() config_changed("panel") end)
    on("fact:anim_toast", function() config_changed("toast") end)
    on("fact:anim_center", function() config_changed("center") end)
    on("fact:anim_center_panel", function() config_changed("center_panel") end)
    on("anim_set", function(packed)
        local v = math.floor(number(packed, 0))
        local kind = ANIM_KINDS[math.floor(v / 6) + 1]
        if not kind then return end
        fact["anim_" .. kind] = v % 6
    end)

    on("text:font_query", function() refresh_fonts() end)
    on("weather_apply", function()
        local city = tostring(text.weather_city or ""):gsub("^%s+", ""):gsub("%s+$", "")
        text.weather_city = city
        cfg.weather_city = city
        save()
    end)
    on("ui_sound", function() play_panel_sound() end)
    on("fact:nt_pos", function()
        cfg.nt_pos = clamp(number(fact.nt_pos, 1), 0, 1)
        nt_set_anchor()
        save()
    end)
    on("fact:nt_sound", function()
        local v = math.floor(clamp(number(fact.nt_sound, 1), 1, #NT_SOUNDS))
        if fact.nt_sound ~= v then fact.nt_sound = v end
        cfg.nt_sound = v
        nt_set_sound_name()
        save()
    end)
    on("fact:nt_snd_on", function()
        cfg.nt_snd_on = truthy(fact.nt_snd_on)
        save()
        if cfg.nt_snd_on then nt_sound(fact.nt_sound) end
    end)
    on("fact:nt_dnd", function()
        cfg.nt_dnd = truthy(fact.nt_dnd)
        save()
        if not cfg.nt_dnd then nt_pump() end
    end)
    on("fact:nt_secs", function()
        local v = math.floor(clamp(number(fact.nt_secs, 6), 2, 60))
        if fact.nt_secs ~= v then fact.nt_secs = v end
        cfg.nt_secs = v
        save()
    end)
    on("nt_close", function() nt_finish() end)
    on("nt_act", function(i)
        if nt_now then
            local a = (nt_now.actions or {})[math.floor(number(i, 0)) + 1]
            if a then pcall(sys.call, "notifications.invoke", nt_now.id, a.key) end
        end
        nt_finish()
    end)
    on("nt_clear", function()
        pcall(sys.call, "notifications.clear")
        nt_hist = {}
        nt_save_hist()
        fact.nt_unread = 0
        nt_finish()
    end)
    on("fact:nt_center", function()
        if truthy(fact.nt_center) then
            set_fx("center")
            fact.nt_unread = 0
            nt_save_hist()
            fact.panel_open, fact.launch_open = false, false
            if truthy(fact.center_open) then center.close() end
        end
    end)
    on("nt_center_toggle", function()
        fact.nt_center = not truthy(fact.nt_center)
        if truthy(fact.nt_center) then
            fact.panel_open, fact.launch_open = false, false
            nt_save_hist()
            fact.nt_unread = 0
        end
    end)
    on("nt_center_close", function() fact.nt_center = false end)
    on("nt_history_act", function(i)
        local h = nt_hist[math.floor(number(i, 0)) + 1]
        if h and h.id then pcall(sys.call, "notifications.invoke", h.id, "default") end
        fact.nt_center = false
    end)
    on("nt_settings", function()
        fact.nt_center = false
        fact.settings_page = 5
        fact.panel_open = true
        fact.launch_open = false
    end)
    on("nt_dnd_toggle", function()
        fact.nt_dnd = not truthy(fact.nt_dnd)
        cfg.nt_dnd = truthy(fact.nt_dnd)
        save()
        if not cfg.nt_dnd then nt_pump() end
    end)
    on("nt_sound_toggle", function()
        fact.nt_snd_on = not truthy(fact.nt_snd_on)
        cfg.nt_snd_on = truthy(fact.nt_snd_on)
        save()
        if cfg.nt_snd_on then nt_sound(fact.nt_sound) end
    end)
    on("nt_sound_set", function(d)
        local v = math.floor(number(fact.nt_sound, 1)) + math.floor(number(d, 0))
        if v < 1 then v = #NT_SOUNDS elseif v > #NT_SOUNDS then v = 1 end
        fact.nt_sound = v
        cfg.nt_sound = v
        nt_set_sound_name()
        save()
        nt_sound(v)
    end)
    on("nt_pos_set", function(v)
        fact.nt_pos = clamp(number(v, 1), 0, 1)
    end)
    on("nt_test", function()
        run("sh", { "-c", "notify-send -a pleamar-shell 'Notification test' 'This is how a notification looks and sounds.'" }, function(_, code)
            if code ~= 0 then log("notify-send failed") end
        end)
    end)
    on("fact:snd_on", function()
        cfg.snd_on = truthy(fact.snd_on)
        save()
        if cfg.snd_on then play_panel_sound() end
    end)
    on("wall_refresh", function() refresh_wallpapers() end)
    on("fact:wall_auto", function()
        cfg.wallpaper_auto = truthy(fact.wall_auto)
        if cfg.wallpaper_auto then reset_wall_countdown()
        else fact.wall_remain = 0; update_wall_next() end
        save()
    end)
    on("fact:wall_minutes", function()
        local v = math.floor(clamp(number(fact.wall_minutes, 5), 1, 60))
        if fact.wall_minutes ~= v then fact.wall_minutes = v end
        cfg.wallpaper_minutes = v
        if truthy(fact.wall_auto) then reset_wall_countdown() end
        save()
    end)
    on("wall_apply", function()
        local chosen = tostring(text.wall_choice or "")
        if chosen ~= "" then set_wallpaper(chosen, true) end
    end)
    on("fact:wp_page", function() show_wall_page() end)
    on("font_apply", function()
        local chosen = tostring(text.font_choice or "Space Grotesk")
        text.font_family = chosen
        text.font_choice = chosen
        save(function(code)
            if code ~= 0 then
                log("font choice could not be saved; not restarting")
                return
            end
            if shell_root == "" then
                log("font saved; start pleamar-shell again to apply it")
                return
            end
            local mode = string.lower(tostring(text.layout or "island"))
            local helper = shell_root .. "/bin/pleamar-shell-restart"
            --  Give the config write a moment to reach the disk, and carry the
            --  chosen family into the new process even if it has not.
            after(400, function()
                local cmd = string.format(
                    "if command -v systemd-run >/dev/null 2>&1; then "
                        .. "systemd-run --user --collect --unit=pleamar-font-$$ %q %q %q; "
                        .. "else setsid -f %q %q %q >/tmp/pleamar-shell-restart.log 2>&1; fi",
                    helper, mode, chosen, helper, mode, chosen)
                local started, err = pcall(run, "sh", { "-c", cmd })
                if not started then log("font restart could not start: " .. tostring(err)) end
            end)
        end)
    end)
    on("text:query", function()
        after(60, function()
            if truthy(fact.launch_open) then search_now() end
        end)
    end)
    on("submit:query", function()
        if truthy(fact.launch_open) then run_result(math.floor(number(fact.la_sel, 0)) + 1) end
    end)
    on("launch", function(i)
        if not truthy(fact.launch_open) then return end
        run_result(math.floor(number(i, 0)) + 1)
    end)
    on("la_hint", function(i)
        local prefix = ({ "#", ">", ":", "^", "~", "@", "?", "!", "=", "?" })[math.floor(number(i, 0)) + 1]
        if prefix then text.query = prefix; search_now() end
    end)
    on("la_move", function(d)
        local n = #results
        if n == 0 then return end
        local at = math.floor(number(fact.la_sel, 0) + number(d, 0) + 0.5)
        if at < 0 then at = n - 1 elseif at >= n then at = 0 end
        fact.la_sel = at
    end)

    --  ── IPC: open the panels from a terminal ───────────────────────────
    --  Set the public fact first so the surface is opening, then focus the
    --  query after it has had one frame to appear.  Focusing a field also
    --  asks the compositor for the keyboard, so the search is usable at once.
    on("ipc_open_search", function()
        center.close()
        fact.panel_open = false
        stop_settingskeys()
        fact.nt_center = false
        if not truthy(fact.launch_open) then set_fx("search") end
        fact.launch_open = true
        text.query = ""
        search_now()
    end)
    on("ipc_open_settings", function(page)
        center.close()
        if page ~= nil and tostring(page) ~= "" then
            local p = math.floor(number(page, 0))
            if p >= 0 and p <= 9 then fact.settings_page = p end
        end
        fact.launch_open = false
        fact.nt_center = false
        if not truthy(fact.panel_open) then set_fx("panel") end
        fact.panel_open = true
        start_settingskeys()
    end)
    on("ipc_open_center", function()
        stop_settingskeys()
    end)
    on("center_toggle", function()
        stop_settingskeys()
    end)
    on("lock_now", function()
        center.close()
        fact.panel_open = false
        stop_settingskeys()
        fact.launch_open = false
        save(function(code)
            if code ~= 0 or shell_root == "" then return end
            after(180, function()
                run("sh", { "-c", shq(shell_root .. "/bin/pleamar-lock") .. " lock" }, function(_, c)
                    if c ~= 0 then log("lock could not start") end
                end)
            end)
        end)
    end)
    on("lock_test", function()
        center.close()
        fact.panel_open = false
        stop_settingskeys()
        fact.launch_open = false
        save(function(code)
            if code ~= 0 or shell_root == "" then return end
            after(180, function()
                run("sh", { "-c", shq(shell_root .. "/bin/pleamar-lock") .. " test" }, function(_, c)
                    if c ~= 0 then log("test lock could not start") end
                end)
            end)
        end)
    end)
    on("ipc_open_notifications", function()
        center.close()
        fact.panel_open = false
        stop_settingskeys()
        fact.launch_open = false
        if not truthy(fact.nt_center) then set_fx("center") end
        fact.nt_center = true
        fact.nt_unread = 0
    end)
    --  ── the lock scene, kept alive ─────────────────────────────────────
    --  Pleamar 0.4.x exits on an ext-session-lock protocol error when an output
    --  comes back while the screen is locked (DPMS off/on hotplugs the
    --  monitor).  niri then remains locked with no client and paints its red
    --  overlay.  The lock scene is a separate process, so watch its socket:
    --  `alive` costs one short-lived client and fails at once when the scene
    --  is gone.  Re-lock only if the session is still locked; give the startup
    --  `ensure` time to open the socket first.
    local lock_watch_busy, lock_watch_ready = false, false
    after(5000, function() lock_watch_ready = true end)
    every(2000, function()
        if shell_root == "" or not lock_watch_ready or lock_watch_busy then return end
        lock_watch_busy = true
        local helper = shq(shell_root .. "/bin/pleamar-lock")
        run("sh", { "-c", helper .. " alive" }, function(_, alive)
            if alive == 0 then
                lock_watch_busy = false
                return
            end
            local lock_hint = 'sid=${XDG_SESSION_ID:-$(loginctl list-sessions --no-legend 2>/dev/null | while read -r s uid user rest; do [ "$user" = "$USER" ] && { echo "$s"; break; }; done)}; loginctl show-session "$sid" -p LockedHint --value 2>/dev/null'
            run("sh", { "-c", lock_hint }, function(out)
                local locked = tostring(out or ""):lower():find("yes") ~= nil
                log("lock scene is gone; " .. (locked and "re-locking" or "starting it again"))
                run("sh", { "-c", helper .. (locked and " lock" or " ensure") }, function(_, code)
                    if code ~= 0 then log("lock scene could not be restarted") end
                    lock_watch_busy = false
                end)
            end)
        end)
    end)
    every(700, function()
        if truthy(fact.panel_open) and settings_key_helper then
            pcall(sys.call, "say", "settingskeys", "emit key_ping")
        end
    end)
end

return M
