--  Centre panel state and samplers.  Kept beside the scene logic so the
--  panel's facts, models and key handling have one owner.
local M = {}

local N_HIST = 60
local hist = {}
local proc = nil
local root_of = nil
local on_open = nil
local cal_off = 0
local last_iface = nil
local audio_out_ids = {}
local key_helper = nil
local tray_keys = {}
local tray_menu_key = nil
local tray_menu_ids = {}
local tray_menu_children = {}
local tray_submenu_ids = {}

local function truthy(v) return v == true or v == 1 end
local function number(v, fallback)
    local n = tonumber(v)
    if n == nil then return fallback end
    return n
end
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function size(b)
    b = b or 0
    local units = { "B", "KB", "MB", "GB", "TB", "PB" }
    local i = 1
    while b >= 1024 and i < #units do b = b / 1024; i = i + 1 end
    if i == 1 then return string.format("%d B", b) end
    if b >= 100 then return string.format("%.0f %s", b, units[i]) end
    if b >= 10 then return string.format("%.1f %s", b, units[i]) end
    return string.format("%.2f %s", b, units[i])
end
local function rate(b) return size(b) .. "/s" end
local function disk_rate(b)
    --  The disk card always speaks KB/s or MB/s; unlike network rates,
    --  a sub-kilobyte write is not interesting enough for its own unit.
    local k = (b or 0) / 1024
    if k >= 1024 then
        local m = k / 1024
        if m >= 100 then return string.format("%.0f MB/s", m) end
        if m >= 10 then return string.format("%.1f MB/s", m) end
        return string.format("%.2f MB/s", m)
    end
    if k >= 100 then return string.format("%.0f KB/s", k) end
    if k >= 10 then return string.format("%.1f KB/s", k) end
    return string.format("%.2f KB/s", k)
end
local function kb(v) return size((v or 0) * 1024) end
local function uptime(s)
    s = s or 0
    local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end
local function clock_len(s)
    s = math.max(0, math.floor(number(s, 0)))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local function sparkline(field, n, bucket)
    --  Text, not the scene model: the model is unreliable once it is exactly
    --  full, while text updates every sample.  Overview uses 30 two-second
    --  columns; the System network chart uses all 60 one-second samples.
    n, bucket = n or 30, bucket or 2
    local vals, mx = {}, 0
    local hn = #hist
    for b = 1, n do
        local start = hn - (n - b + 1) * bucket + 1
        local v = 0
        for k = 0, bucket - 1 do
            local idx = start + k
            if idx >= 1 and idx <= hn then
                v = math.max(v, hist[idx][field] or 0)
            end
        end
        vals[b] = v
        mx = math.max(mx, v)
    end
    if mx <= 0 then mx = 1 end
    local out = {}
    for b = 1, n do
        local ratio = math.sqrt(math.min(1, vals[b] / mx))
        local level = math.max(1, math.min(8, math.ceil(ratio * 8)))
        out[b] = SPARK[level]
    end
    return table.concat(out)
end

local function interval_refresh()
    --  The IP address is asked once per interface change; nmcli is used only
    --  for this, and a missing nmcli just leaves the address empty.
    if last_iface and last_iface ~= "" then
        run("sh", { "-c", "nmcli -t -f IP4.ADDRESS device show " .. shq(last_iface)
            .. " 2>/dev/null | sed -n 's/^IP4.ADDRESS[^:]*://p' | cut -d/ -f1 | head -n1" }, function(out)
            text.sys_ip = (out or ""):gsub("%s+$", "")
        end)
    else
        text.sys_ip = ""
    end
end

local function on_sys_line(line)
    local ok, d = pcall(json.decode, line)
    if not ok or type(d) ~= "table" or not d.cpu then return end
    fact.sys_ready = true

    if d.info then
        text.sys_host = d.info.host or "This machine"
        text.sys_cpu_name = d.info.cpu or ""
        text.sys_kernel = d.info.kernel or ""
        text.sys_threads = string.format("%d threads", d.info.threads or 0)
    end

    local c = d.cpu
    local total = c.total or 0
    fact.sys_cpu = clamp(total / 100, 0, 1)
    text.sys_cpu_txt = string.format("%d%%", math.floor(total + 0.5))
    local sum, n = 0, 0
    for _, f in ipairs(c.mhz or {}) do if f > 0 then sum = sum + f; n = n + 1 end end
    local meta = n > 0 and string.format("%.1f GHz", sum / n / 1000) or ""
    for _, t in ipairs(d.temps or {}) do
        if t.l == "CPU package" then
            meta = (meta ~= "" and (meta .. " · ") or "") .. string.format("%d°C", math.floor(t.c + 0.5))
            break
        end
    end
    text.sys_cpu_meta = meta
    if c.load then text.sys_load = string.format("%.2f  %.2f  %.2f", c.load[1] or 0, c.load[2] or 0, c.load[3] or 0) end
    text.sys_uptime = uptime(d.up)
    local cores = {}
    for i, p in ipairs(c.cores or {}) do cores[i] = { pct = clamp(p / 100, 0, 1) } end
    model.sys_cores = cores

    local m = d.mem or {}
    local mt = math.max(m.total or 1, 1)
    fact.sys_mem = clamp((m.used or 0) / mt, 0, 1)
    fact.sys_cache = clamp((m.cache or 0) / mt, 0, 1)
    fact.sys_swap = (m.swap_total or 0) > 0 and clamp((m.swap_used or 0) / m.swap_total, 0, 1) or 0
    text.sys_mem_pct = string.format("%d%%", math.floor(fact.sys_mem * 100 + 0.5))
    text.sys_mem_total = kb(m.total) .. " installed"
    text.sys_mem_used = kb(m.used)
    text.sys_mem_cache = kb(m.cache)
    text.sys_mem_free = kb(m.free)
    text.sys_swap_txt = (m.swap_total or 0) > 0 and (kb(m.swap_used) .. " of " .. kb(m.swap_total)) or "none"

    local g = d.gpu
    fact.sys_gpu_on = g ~= nil
    if g then
        fact.sys_gpu = clamp((g.util or 0) / 100, 0, 1)
        fact.sys_vram = (g.mem_total or 0) > 0 and clamp((g.mem_used or 0) / g.mem_total, 0, 1) or 0
        fact.sys_pw = (g.power_max or 0) > 0 and clamp((g.power or 0) / g.power_max, 0, 1) or 0
        text.sys_gpu_name = g.name or ""
        text.sys_gpu_txt = string.format("%d%%", math.floor((g.util or 0) + 0.5))
        text.sys_gpu_vram = (g.mem_total or 0) > 0 and string.format("%.1f / %.1f GB", (g.mem_used or 0) / 1024, g.mem_total / 1024) or ""
        text.sys_gpu_power = (g.power_max or 0) > 0 and string.format("%.0f / %.0f W", g.power or 0, g.power_max) or "—"
        text.sys_gpu_temp = g.temp and string.format("%d°C", math.floor(g.temp + 0.5)) or "—"
        text.sys_gpu_fan = g.fan_rpm ~= nil and string.format("%d RPM", math.floor(g.fan_rpm + 0.5))
            or (g.fan and string.format("%d%%", math.floor(g.fan + 0.5)) or "—")
        text.sys_gpu_clock = g.clock and string.format("%d MHz", math.floor(g.clock + 0.5)) or "—"
    end

    local nt = d.net or {}
    text.sys_iface = nt.iface or ""
    fact.sys_net_up = (nt.iface or "") ~= ""
    if nt.iface ~= last_iface then
        last_iface = nt.iface
        interval_refresh()
    end
    text.sys_rx_txt = rate(nt.rx)
    text.sys_tx_txt = rate(nt.tx)
    text.sys_rx_total = size(nt.rx_total) .. " received"
    text.sys_tx_total = size(nt.tx_total) .. " sent"
    local dk = d.disk or {}
    text.sys_dr_txt = rate(dk.read)
    text.sys_dw_speed = disk_rate(dk.write)
    local mts = {}
    for i, mo in ipairs(dk.mounts or {}) do
        mts[i] = { name = mo.m, info = size(mo.used) .. " of " .. size(mo.total), pct = clamp(mo.total > 0 and mo.used / mo.total or 0, 0, 1) }
    end
    if #mts > 0 then model.sys_mounts = mts end

    local tmps = {}
    for i, t in ipairs(d.temps or {}) do
        tmps[i] = { label = t.l, txt = string.format("%d°C", math.floor(t.c + 0.5)),
            f = clamp((t.c - 25) / 70, 0, 1), heat = clamp((t.c - 70) / 25, 0, 1) }
    end
    model.sys_temps = tmps
    local fans = {}
    for _, f in ipairs(d.fans or {}) do fans[#fans + 1] = string.format("%s %d rpm", f.l or "Fan", f.rpm or 0) end
    text.sys_fans = #fans > 0 and table.concat(fans, "   ·   ") or ""

    local prs = {}
    for i, p in ipairs(d.procs or {}) do
        prs[i] = { name = p.n, cpu = clamp((p.cpu or 0) / 100, 0, 1),
            cpu_txt = string.format("%.1f%%", p.cpu or 0),
            mem = clamp((p.mem or 0) / 100, 0, 1),
            mem_txt = string.format("%.1f%%", p.mem or 0) }
    end
    model.sys_procs = prs

    hist[#hist + 1] = { cpu = clamp(total / 100, 0, 1), mem = fact.sys_mem,
        gpu = g and clamp((g.util or 0) / 100, 0, 1) or 0,
        rx = nt.rx or 0, tx = nt.tx or 0, dr = dk.read or 0, dw = dk.write or 0 }
    if #hist > N_HIST then table.remove(hist, 1) end
    local mx_net, mx_dk = 50 * 1024, 1024 * 1024
    for _, h in ipairs(hist) do
        mx_net = math.max(mx_net, h.rx, h.tx)
        mx_dk = math.max(mx_dk, h.dr, h.dw)
    end
    local rows = {}
    for i, h in ipairs(hist) do
        rows[i] = { cpu = h.cpu, mem = h.mem, gpu = h.gpu, rx = h.rx / mx_net, tx = h.tx / mx_net,
            dr = h.dr / mx_dk, dw = h.dw / mx_dk }
    end
    model.sys_hist = rows
    fact.sys_hist_count = #rows
    text.sys_rx_spark = sparkline("rx", 30, 2)
    text.sys_tx_spark = sparkline("tx", 30, 2)
    text.sys_rx_hist = sparkline("rx", 60, 1)
    text.sys_tx_hist = sparkline("tx", 60, 1)
    text.sys_gpu_hist = sparkline("gpu", 60, 1)
    text.sys_cpu_hist = sparkline("cpu", 60, 1)
end

local function stop_sys()
    if proc then
        kill(proc, "term")
        proc = nil
    end
    fact.sys_ready = false
end

local function refresh_sys()
    if not truthy(fact.center_open) then
        stop_sys()
        return
    end
    if proc then return end
    local root = root_of and root_of() or ""
    local path = root ~= "" and (root .. "/bin/pleamar-sysmon") or "pleamar-sysmon"
    local mine
    local ok, id = pcall(spawn, "sh", { "-c", shq(path) }, function(line)
        if proc == mine then on_sys_line(line) end
    end, function()
        if proc == mine then
            proc = nil
            fact.sys_ready = false
        end
    end)
    if not ok then
        log("pleamar-sysmon could not start: " .. tostring(id))
        fact.sys_ready = false
    else
        proc = id
        mine = id
    end
end

local WEEKDAYS = { [1] = "星期日", [2] = "星期一", [3] = "星期二", [4] = "星期三",
    [5] = "星期四", [6] = "星期五", [7] = "星期六" }

--  Luau's os.date does not implement %V.  ISO week from the Thursday of
--  this week: that is the week-year's first Thursday rule.
local function iso_week(ts)
    local t = os.date("*t", ts)
    local day = (t.wday + 6) % 7
    local thursday = ts + (3 - day) * 86400
    local year = os.date("*t", thursday).year
    local jan4 = os.time({ year = year, month = 1, day = 4 })
    local jan4_day = (os.date("*t", jan4).wday + 5) % 7
    local week1 = jan4 - jan4_day * 86400
    return math.floor((thursday - week1) / 86400 / 7) + 1
end

local function calendar_fallback(ft, today)
    local first = os.time({ year = ft.year, month = ft.month, day = 1 })
    local lead = (ft.wday + 5) % 7 -- Monday is the first column
    local days = os.date("*t", os.time({ year = ft.year, month = ft.month + 1, day = 0 })).day
    local prev_days = os.date("*t", os.time({ year = ft.year, month = ft.month, day = 0 })).day
    local cells = {}
    for i = 1, 42 do
        local day, cur
        if i <= lead then
            day, cur = prev_days - lead + i, false
        elseif i <= lead + days then
            day, cur = i - lead, true
        else
            day, cur = i - lead - days, false
        end
        local is_today = cur and today.year == ft.year and today.month == ft.month and today.day == day
        local hover = cur and string.format("%d月%d日", ft.month, day) or ""
        cells[i] = { day = day, cur = cur, today = is_today, label = "", lunar = "",
            hover = hover, term = "", festival = "", holiday = "",
            off = false, work = false, anniv = "", anniv_count = 0 }
    end
    model.ct_days = cells
    model.ct_countdown = {}
    text.ct_countdown_title = (ft.year == today.year and ft.month == today.month)
        and "本月倒计时" or string.format("%d月倒计时", ft.month)
    text.ct_header_date = string.format("%d年%d月%d日 · %s", today.year, today.month, today.day, WEEKDAYS[today.wday])
    text.ct_month = string.format("%d年 %d月", ft.year, ft.month)
    text.ct_month_sub = string.format("第 %d 周", iso_week(first))
    text.ct_weekday = WEEKDAYS[today.wday]
    text.ct_today_day = string.format("%02d", today.day)
    text.ct_today_month = string.format("%d月", today.month)
    text.ct_today_year = tostring(today.year)
    text.ct_weeknum = string.format("第 %d 周", iso_week(os.time()))
end

local function apply_calendar(d)
    if type(d) ~= "table" or type(d.days) ~= "table" then return false end
    local cells = {}
    for i, c in ipairs(d.days) do
        if i > 42 then break end
        cells[i] = {
            day = math.floor(number(c.day, 0)),
            cur = truthy(c.cur),
            today = truthy(c.today),
            label = tostring(c.label or ""),
            lunar = tostring(c.lunar or ""),
            hover = tostring(c.hover or ""),
            term = tostring(c.term or ""),
            festival = tostring(c.festival or ""),
            holiday = tostring(c.holiday or ""),
            off = truthy(c.off),
            work = truthy(c.work),
            anniv = tostring(c.anniv or ""),
            anniv_count = math.floor(number(c.anniv_count, 0)),
        }
    end
    if #cells ~= 42 then return false end
    model.ct_days = cells
    local cds = {}
    for i, c in ipairs(d.countdowns or {}) do
        if i > 2 then break end
        cds[i] = {
            title = tostring(c.title or ""),
            date = tostring(c.date or ""),
            when = tostring(c.when or ""),
            days = math.floor(number(c.days, 0)),
        }
    end
    model.ct_countdown = cds
    text.ct_countdown_title = tostring(d.countdown_title or "本月倒计时")
    text.ct_header_date = tostring(d.header or "")
    local mo = d.month or {}
    text.ct_month = tostring(mo.title or "")
    text.ct_month_sub = tostring(mo.sub or "")
    local td = d.today or {}
    text.ct_today_day = tostring(td.day or "")
    text.ct_today_month = tostring(td.month or "")
    text.ct_today_year = tostring(td.year or "")
    text.ct_weekday = tostring(td.weekday or "")
    text.ct_weeknum = tostring(td.week or "")
    return true
end

local calendar_seq = 0
local function calendar()
    local off = math.floor(clamp(number(fact.center_cal_off, 0), -120, 120))
    cal_off = off
    fact.center_cal_hover = -1
    local today = os.date("*t")
    local first = os.time({ year = today.year, month = today.month + off, day = 1 })
    local ft = os.date("*t", first)
    calendar_seq = calendar_seq + 1
    local seq = calendar_seq
    local root = root_of and root_of() or ""
    local path = root ~= "" and (root .. "/bin/pleamar-calendar") or "pleamar-calendar"
    local cmd = shq(path) .. " --year " .. tostring(ft.year) .. " --month " .. tostring(ft.month)
    run("sh", { "-c", cmd }, function(out, code)
        if seq ~= calendar_seq then return end
        local ok, d = pcall(json.decode, out or "")
        if code == 0 and ok and apply_calendar(d) then return end
        calendar_fallback(ft, today)
    end)
end


local weather_seq = 0
local function refresh_weather()
    weather_seq = weather_seq + 1
    local seq = weather_seq
    local root = root_of and root_of() or ""
    local path = root ~= "" and (root .. "/bin/pleamar-weather") or "pleamar-weather"
    local city = tostring(text.weather_city or "")
    local cmd = shq(path) .. " --city " .. shq(city)
    run("sh", { "-c", cmd }, function(out, code)
        if seq ~= weather_seq then return end
        local ok, d = pcall(json.decode, out or "")
        if code ~= 0 or not ok or type(d) ~= "table" then
            text.wx_status = "天气暂时不可用"
            if not truthy(fact.wx_ready) then
                fact.wx_ready = false
                fact.wx_configured = city ~= ""
            end
            return
        end
        fact.wx_configured = truthy(d.configured)
        if not fact.wx_configured then
            fact.wx_ready = false
            text.wx_city = ""
            text.wx_status = "在设置中填写城市"
            model.wx_hourly = {}
            model.wx_daily = {}
            return
        end
        fact.wx_ready = truthy(d.ready)
        text.wx_city = tostring(d.city or city or "")
        text.wx_desc = tostring(d.desc or "")
        text.wx_icon = tostring(d.icon or "·")
        text.wx_temp = tostring(d.temp or "--")
        text.wx_feels = "体感 " .. tostring(d.feels or "--") .. "°"
        text.wx_hi = "H " .. tostring(d.hi or "--") .. "°"
        text.wx_lo = "L " .. tostring(d.lo or "--") .. "°"
        text.wx_humidity = tostring(d.humidity or "--")
        text.wx_wind = tostring(d.wind or "--")
        text.wx_updated = d.updated and ("更新 " .. tostring(d.updated)) or ""
        text.wx_status = tostring(d.error or "")
        local hours = {}
        for i, h in ipairs(d.hourly or {}) do
            if i > 6 then break end
            hours[i] = {
                label = tostring(h.label or ""),
                temp = tostring(h.temp or ""),
                icon = tostring(h.icon or "·"),
                night = truthy(h.night),
            }
        end
        model.wx_hourly = hours
        local days = {}
        for i, w in ipairs(d.daily or {}) do
            if i > 4 then break end
            days[i] = {
                day = tostring(w.day or ""),
                icon = tostring(w.icon or "·"),
                hi = tostring(w.hi or ""),
                lo = tostring(w.lo or ""),
            }
        end
        model.wx_daily = days
    end)
end

local function refresh_audio_outputs()
    --  Pleamar's audio watch in this version does not carry the sink list, so
    --  read wpctl's status: the starred sink is the default, and its numeric
    --  id is what `wpctl set-default` wants.
    run("sh", { "-c", "wpctl status 2>/dev/null" }, function(out)
        if not out or out == "" then return end
        local section, rows, ids, current = "", {}, {}, "Default sink"
        for line in out:gmatch("[^\n]+") do
            if line:find("Sinks:", 1, true) then
                section = "sink"
            elseif line:find("Sources:", 1, true) then
                section = "source"
            elseif section == "sink" then
                local t = line:gsub("^[%s│|]+", "")
                local star, id, name = t:match("^([* ]?)%s*(%d+)%.%s+(.+)$")
                if id then
                    name = name:gsub("%s+%[vol:[^%]]*%]$", "")
                    rows[#rows + 1] = { name = name, current = star == "*" }
                    ids[#ids + 1] = tonumber(id)
                    if star == "*" then current = name end
                end
            end
        end
        if #rows > 0 then
            audio_out_ids = ids
            model.audio_outputs = rows
            text.audio_out_name = current
        end
    end)
end

local function stop_keys()
    if key_helper then
        kill(key_helper, "term")
        key_helper = nil
    end
end

local function start_keys()
    if key_helper or not truthy(fact.center_open) then return end
    local root = root_of and root_of() or ""
    if root == "" then return end
    local parent = string.lower(tostring(text.layout or "island"))
    local cmd = "PLEAMAR_CENTER_PARENT=" .. shq(parent) .. " exec " .. shq(root .. "/bin/pleamar-centerkeys")
    local mine
    local ok, id = pcall(spawn, "sh", { "-c", cmd }, function() end, function()
        if key_helper == mine then key_helper = nil end
    end)
    if ok then
        key_helper = id
        mine = id
    else
        log("centre key helper could not start: " .. tostring(id))
    end
end

local function close()
    fact.center_open = false
    fact.center_power_confirm = -1
    stop_keys()
    fact.tray_menu_open = false
    fact.tray_submenu_open = false
    stop_sys()
end

local function open(tab)
    local n = tab ~= nil and math.floor(number(tab, 0)) or math.floor(number(fact.center_tab, 0))
    if n < 0 or n > 6 then n = 0 end
    fact.panel_open = false
    fact.launch_open = false
    fact.nt_center = false
    fact.center_tab = n
    fact.center_sys_scroll = 0
    fact.center_open = true
    fact.tray_menu_open = false
    fact.tray_submenu_open = false
    fact.audio_pick_open = false
    calendar()
    refresh_weather()
    refresh_audio_outputs()
    start_keys()
    if on_open then on_open() end
    refresh_sys()
end

function M.start(root_getter, fx)
    root_of = root_getter
    on_open = fx

    on("fact:center_open", function(v)
        if truthy(v) then
            refresh_sys()
        else
            --  The cross and Escape used to clear the fact directly.  Releasing
            --  the exclusive keyboard here avoids waiting for the helper's
            --  watchdog (about two seconds) before the focused window gets keys.
            stop_keys()
            fact.tray_menu_open = false
            stop_sys()
        end
    end)
    on("center_toggle", function()
        if truthy(fact.center_open) then close() else open() end
    end)
    on("center_close", close)
    on("ipc_open_center", function(tab) open(tab) end)
    on("weather_apply", function()
        after(80, refresh_weather)
    end)
    on("center_power_ask", function(k)
        local v = math.floor(number(k, -1))
        if v >= 0 and v <= 2 then fact.center_power_confirm = v end
    end)
    on("center_power_cancel", function()
        fact.center_power_confirm = -1
    end)
    on("center_power_do", function()
        local v = math.floor(number(fact.center_power_confirm, -1))
        fact.center_power_confirm = -1
        if v < 0 or v > 2 then return end
        close()
        local cmd = v == 0 and "niri msg action quit --skip-confirmation"
            or v == 1 and "systemctl reboot --no-block"
            or "systemctl poweroff --no-block"
        run("sh", { "-c", cmd }, function(_, code)
            if code ~= 0 then log("power action failed: " .. cmd) end
        end)
    end)

    on("center_key_digit", function(n)
        if not truthy(fact.center_open) then return end
        local v = math.floor(number(n, 0))
        if v >= 1 and v <= 7 then
            fact.center_tab = v - 1
            fact.center_sys_scroll = 0
            fact.tray_menu_open = false
            fact.audio_pick_open = false
        end
    end)
    on("center_key_tab", function(d)
        if not truthy(fact.center_open) then return end
        local dir = number(d, 1) < 0 and -1 or 1
        fact.center_tab = (math.floor(number(fact.center_tab, 0)) + dir + 7) % 7
        fact.center_sys_scroll = 0
        fact.tray_menu_open = false
        fact.audio_pick_open = false
    end)
    on("center_key_escape", function()
        if truthy(fact.center_open) then close() end
    end)
    on("center_key_blur", function()
        if truthy(fact.center_open) then close() end
    end)

    on("key_down", function(name)
        if not truthy(fact.center_open) then return end
        name = tostring(name or "")
        if name == "Escape" then
            close()
            return
        end
        if name == "Tab" or name == "ISO_Left_Tab" or name == "Backtab" then
            local d = (held("Shift") or held("ISO_Left_Tab")) and -1 or 1
            fact.center_tab = (math.floor(number(fact.center_tab, 0)) + d + 7) % 7
            fact.center_sys_scroll = 0
            fact.tray_menu_open = false
            return
        end
        local n = tonumber(name)
        if n and n >= 1 and n <= 7 then
            fact.center_tab = n - 1
            fact.center_sys_scroll = 0
            fact.tray_menu_open = false
        end
    end)

    on("center_scroll", function(d)
        fact.center_sys_scroll = clamp(number(fact.center_sys_scroll, 0) - number(d, 0), 0, 500)
    end)
    on("center_cal_step", function(d)
        fact.center_cal_off = clamp(number(fact.center_cal_off, 0) + number(d, 0), -120, 120)
        calendar()
    end)
    on("center_cal_today", function()
        fact.center_cal_off = 0
        calendar()
    end)

    local function wpcall(cmd)
        run("sh", { "-c", "wpctl " .. cmd .. " >/dev/null 2>&1" }, function(_, code)
            if code ~= 0 then log("wpctl " .. cmd .. " failed") end
        end)
    end
    on("center_audio_set", function(v)
        wpcall(string.format("set-volume @DEFAULT_AUDIO_SINK@ %.0f%%", clamp(number(v, 0), 0, 1) * 100 + 0.5))
    end)
    on("center_audio_mute", function()
        wpcall("set-mute @DEFAULT_AUDIO_SINK@ toggle")
    end)
    on("center_input_set", function(v)
        wpcall(string.format("set-volume @DEFAULT_AUDIO_SOURCE@ %.0f%%", clamp(number(v, 0), 0, 1) * 100 + 0.5))
    end)
    on("center_input_mute", function()
        wpcall("set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
    end)
    on("center_media", function(action)
        local call = ({ [0] = "media.previous", [1] = "media.toggle", [2] = "media.next" })[math.floor(number(action, 1))]
        if call then pcall(sys.call, call) end
    end)
    on("center_quick", function(k)
        local i = math.floor(number(k, -1))
        if i == 0 then fact.wave_on = not truthy(fact.wave_on)
        elseif i == 1 then fact.glass_on = not truthy(fact.glass_on)
        elseif i == 2 then
            if truthy(fact.bt_present) then
                local want = not truthy(fact.bt_on)
                if want then
                    --  A soft rfkill block survives a BlueZ power request;
                    --  the switch is an explicit "on", so lift it first.
                    run("sh", { "-c", "rfkill unblock bluetooth 2>/dev/null || true" }, function()
                        after(250, function() pcall(sys.call, "bluetooth.power", true) end)
                    end)
                else
                    pcall(sys.call, "bluetooth.power", false)
                end
            end
        elseif i == 3 then fact.wall_auto = not truthy(fact.wall_auto) end
    end)

    on("center_audio_default", function(i)
        local id = audio_out_ids[math.floor(number(i, 0)) + 1]
        if id ~= nil then
            run("sh", { "-c", "wpctl set-default " .. tostring(id) }, function(_, code)
                if code ~= 0 then log("wpctl set-default failed") end
            end)
        end
        fact.audio_pick_open = false
        after(350, refresh_audio_outputs)
    end)

    sys.watch("media", function(m)
        if m then
            if m.length then text.ct_media_len = clock_len(m.length) end
            fact.ct_has_track = (tostring(m.title or "") ~= "")
        end
    end)

    sys.watch("bluetooth", function(b)
        if not b or b.present == false then
            fact.bt_present, fact.bt_on, fact.bt_count = false, false, 0
            text.bt_sub = "No adapter"
            return
        end
        fact.bt_present = true
        fact.bt_on = truthy(b.powered)
        local n = 0
        for _, d in ipairs(b.devices or {}) do if truthy(d.connected) then n = n + 1 end end
        fact.bt_count = n
        text.bt_sub = fact.bt_on and (n > 0 and (n .. " connected") or "On · nothing connected") or "Radio off"
    end)

    sys.watch("tray", function(items)
        local rows = {}
        tray_keys = {}
        for i, it in ipairs(items or {}) do
            if i > 8 then break end
            local name = tostring(it.title or "")
            if name == "" then name = tostring(it.id or "Tray item") end
            local sub = tostring(it.tooltip_body or it.tooltip or it.id or "")
            rows[i] = { name = name, sub = sub, status = tostring(it.status or "") }
            tray_keys[i] = it.key
        end
        model.tray_items = rows
        fact.tray_count = #rows
    end)

    on("center_tray_activate", function(i)
        local key = tray_keys[math.floor(number(i, 0)) + 1]
        if key then pcall(sys.call, "tray.activate", key) end
    end)

    local function menu_row(it)
        local kids = it.children
        return {
            label = tostring(it.label or ""),
            enabled = it.enabled ~= false,
            separator = it.separator == true,
            checked = it.checked == true,
            sub = type(kids) == "table" and #kids > 0,
        }
    end

    local function clear_submenu()
        model.tray_submenu = {}
        tray_submenu_ids = {}
        fact.tray_submenu_count = 0
        fact.tray_submenu_open = false
    end

    local function show_submenu(m)
        local kids = tray_menu_children[m + 1]
        if type(kids) ~= "table" or #kids == 0 then
            clear_submenu()
            return
        end
        local rows = {}
        tray_submenu_ids = {}
        for n, it in ipairs(kids) do
            if n > 12 then break end
            tray_submenu_ids[n] = it.id
            rows[n] = menu_row(it)
        end
        model.tray_submenu = rows
        fact.tray_submenu_count = #rows
        fact.tray_submenu_open = #rows > 0
    end

    on("center_tray_menu", function(i)
        local row = math.floor(number(i, 0)) + 1
        local key = tray_keys[row]
        if not key then return end
        local menu = sys.ask("tray.menu", key)
        if type(menu) ~= "table" or #menu == 0 then
            --  Some old items only have the app's own menu.
            pcall(sys.call, "tray.context", key)
            return
        end
        tray_menu_key, tray_menu_ids, tray_menu_children = key, {}, {}
        local rows = {}
        for j, it in ipairs(menu) do
            if j > 12 then break end
            tray_menu_ids[j] = it.id
            tray_menu_children[j] = type(it.children) == "table" and it.children or {}
            rows[j] = menu_row(it)
        end
        model.tray_menu = rows
        fact.tray_menu_count = #rows
        fact.tray_menu_row = row - 1
        fact.tray_menu_sel = -1
        clear_submenu()
        fact.tray_menu_open = true
    end)
    on("center_tray_menu_hover", function(j)
        if not truthy(fact.tray_menu_open) then return end
        local m = math.floor(number(j, -1))
        if m < 0 or m >= math.floor(number(fact.tray_menu_count, 0)) then return end
        fact.tray_menu_sel = m
        show_submenu(m)
    end)
    on("center_tray_menu_click", function(j)
        local m = math.floor(number(j, 0))
        local kids = tray_menu_children[m + 1]
        if type(kids) == "table" and #kids > 0 then
            fact.tray_menu_sel = m
            show_submenu(m)
            return
        end
        local id = tray_menu_ids[m + 1]
        if tray_menu_key and id then pcall(sys.call, "tray.menu_click", tray_menu_key, id) end
        fact.tray_menu_open = false
        clear_submenu()
    end)
    on("center_tray_submenu_click", function(j)
        local id = tray_submenu_ids[math.floor(number(j, 0)) + 1]
        if tray_menu_key and id then pcall(sys.call, "tray.menu_click", tray_menu_key, id) end
        fact.tray_menu_open = false
        clear_submenu()
    end)
    on("center_tray_menu_close", function()
        fact.tray_menu_open = false
        clear_submenu()
    end)

    every(700, function()
        if truthy(fact.center_open) and key_helper then
            pcall(sys.call, "say", "centerkeys", "emit key_ping")
        end
    end)
    every(900000, function()
        if truthy(fact.center_open) then refresh_weather() end
    end)
    calendar()
    refresh_audio_outputs()
    refresh_sys()
    start_keys()
end

function M.refresh_root()
    --  The first calendar() runs before PLEAMAR_SHELL_ROOT is known, so it
    --  falls back to a lunar-less grid.  Reload it once the root arrives.
    calendar()
    if truthy(fact.center_open) then
        refresh_sys()
        start_keys()
    end
end

function M.close() close() end
function M.open(tab) open(tab) end

return M
