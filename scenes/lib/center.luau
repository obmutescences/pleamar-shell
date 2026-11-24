--  Centre panel state and samplers.  Kept beside the scene logic so the
--  panel's facts, models and key handling have one owner.
local M = {}

local N_HIST = 60
local hist = {}
local proc = nil
local proc_mode = nil
local proc_cmd = nil
local proc_gen = 0
local root_of = nil
local cal_off = 0
local last_tab = 0
local last_raw_procs = {}
local last_iface = nil
local audio_out_ids = {}
local audio_watched = false
local audio_app_ids = {}
local audio_app_rows = {}
local audio_app_busy = false
local app_vol_pending = {}
local app_vol_timer = false
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
local function compact_rate(b)
    b = math.max(0, number(b, 0))
    if b < 1024 then return "0K" end
    local k = b / 1024
    if k < 10 then return string.format("%.1fK", k) end
    if k < 1024 then return string.format("%.0fK", k) end
    local m = k / 1024
    if m < 10 then return string.format("%.1fM", m) end
    if m < 1024 then return string.format("%.0fM", m) end
    local g = m / 1024
    return string.format(g < 10 and "%.1fG" or "%.0fG", g)
end
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
    local is_lite = d.lite == true
    if not is_lite then
        fact.sys_ready = true
    end

    local c = d.cpu
    local total = c.total or 0
    fact.sys_cpu = clamp(total / 100, 0, 1)
    text.sys_cpu_txt = string.format("%d%%", math.floor(total + 0.5))

    local m = d.mem or {}
    local mt = math.max(m.total or 1, 1)
    fact.sys_mem = clamp((m.used or 0) / mt, 0, 1)
    fact.sys_cache = clamp((m.cache or 0) / mt, 0, 1)
    text.sys_mem_pct = string.format("%d%%", math.floor(fact.sys_mem * 100 + 0.5))

    local nt = d.net or {}
    local rx = number(nt.rx, 0)
    local tx = number(nt.tx, 0)
    text.bar_rx_txt = compact_rate(rx)
    text.bar_tx_txt = compact_rate(tx)
    fact.bar_rx_act = clamp(math.log(1 + rx / 1024) / math.log(1 + 4096), 0, 1)
    fact.bar_tx_act = clamp(math.log(1 + tx / 1024) / math.log(1 + 4096), 0, 1)
    fact.bar_mon_tick = (math.floor(number(fact.bar_mon_tick, 0)) + 1) % 1000

    if is_lite then return end

    if d.info then
        text.sys_host = d.info.host or "This machine"
        text.sys_cpu_name = d.info.cpu or ""
        text.sys_kernel = d.info.kernel or ""
        text.sys_threads = string.format("%d threads", d.info.threads or 0)
    end

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

    fact.sys_swap = (m.swap_total or 0) > 0 and clamp((m.swap_used or 0) / m.swap_total, 0, 1) or 0
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

    last_raw_procs = d.procs or {}
    local sort_mem = math.floor(number(fact.sys_proc_sort, 0)) == 1
    local sorted = {}
    for _, p in ipairs(last_raw_procs) do sorted[#sorted + 1] = p end
    table.sort(sorted, function(a, b)
        if sort_mem then
            local ma, mb = number(a.mem, 0), number(b.mem, 0)
            if ma ~= mb then return ma > mb end
            return number(a.cpu, 0) > number(b.cpu, 0)
        end
        local ca, cb = number(a.cpu, 0), number(b.cpu, 0)
        if ca ~= cb then return ca > cb end
        return number(a.mem, 0) > number(b.mem, 0)
    end)
    local prs = {}
    for i, p in ipairs(sorted) do
        if i > 6 then break end
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

    -- 30 two-second buckets spanning the last minute, left-padded so vector paths always have 30 x-coords.
    local rows30 = {}
    local hn = #hist
    for b = 1, 30 do
        local start = hn - (30 - b + 1) * 2 + 1
        local cmax, mmax, gmax, rmax, tmax = 0, 0, 0, 0, 0
        for k = 0, 1 do
            local idx = start + k
            if idx >= 1 and idx <= hn then
                local pt = hist[idx]
                cmax = math.max(cmax, pt.cpu or 0)
                mmax = math.max(mmax, pt.mem or 0)
                gmax = math.max(gmax, pt.gpu or 0)
                rmax = math.max(rmax, (pt.rx or 0) / mx_net)
                tmax = math.max(tmax, (pt.tx or 0) / mx_net)
            end
        end
        rows30[b] = { cpu = clamp(cmax, 0, 1), mem = clamp(mmax, 0, 1), gpu = clamp(gmax, 0, 1),
            rx = clamp(rmax, 0, 1), tx = clamp(tmax, 0, 1) }
    end
    model.sys_hist30 = rows30
    text.sys_rx_spark = sparkline("rx", 30, 2)
    text.sys_tx_spark = sparkline("tx", 30, 2)
    text.sys_rx_hist = sparkline("rx", 60, 1)
    text.sys_tx_hist = sparkline("tx", 60, 1)
    text.sys_gpu_hist = sparkline("gpu", 60, 1)
    text.sys_cpu_hist = sparkline("cpu", 60, 1)
    text.sys_mem_hist = sparkline("mem", 60, 1)
end

local function bar_mon_wanted()
    return truthy(fact.bar_show_cpu) or truthy(fact.bar_show_mem) or truthy(fact.bar_show_net)
end

local function stop_sys()
    proc_gen = proc_gen + 1
    if proc then
        kill(proc, "term")
        proc = nil
    end
    proc_mode = nil
    proc_cmd = nil
    if not truthy(fact.center_open) then
        fact.sys_ready = false
    end
end

local function refresh_sys()
    if not root_of then return end
    local want = truthy(fact.center_open) and "full" or (bar_mon_wanted() and "lite" or nil)
    if not want then
        stop_sys()
        fact.sys_ready = false
        return
    end
    local root = root_of() or ""
    local path = root ~= "" and (root .. "/bin/pleamar-sysmon") or "pleamar-sysmon"
    local cmd = want == "lite" and (shq(path) .. " --lite") or shq(path)
    if want == proc_mode and cmd == proc_cmd and proc then return end
    stop_sys()
    if want == "lite" then fact.sys_ready = false end
    proc_gen = proc_gen + 1
    local gen = proc_gen
    local ok, id = pcall(spawn, "sh", { "-c", cmd }, function(line)
        if gen == proc_gen then on_sys_line(line) end
    end, function()
        if gen == proc_gen then
            proc = nil
            proc_mode = nil
            proc_cmd = nil
            fact.sys_ready = false
            after(2000, function()
                if gen == proc_gen and not proc then refresh_sys() end
            end)
        end
    end)
    if not ok then
        log("pleamar-sysmon could not start: " .. tostring(id))
        fact.sys_ready = false
    else
        proc = id
        proc_mode = want
        proc_cmd = cmd
    end
end

local WEEKDAYS = { [1] = "星期日", [2] = "星期一", [3] = "星期二", [4] = "星期三",
    [5] = "星期四", [6] = "星期五", [7] = "星期六" }

local bar_today_date = ""
local bar_today_lunar = ""
local bar_today_weekday = ""
local bar_last_ymd = ""
local bar_cd_title = ""
local bar_cd_days_txt = ""
local bar_cd_days = 9999

local function refresh_bar_date()
    local today = os.date("*t")
    if bar_today_date == "" then
        bar_today_date = string.format("%02d-%02d", today.month, today.day)
    end
    if bar_today_weekday == "" then
        bar_today_weekday = WEEKDAYS[today.wday] or ""
    end
    local show_date = truthy(fact.bar_show_date)
    local show_lunar = truthy(fact.bar_show_lunar)
    local show_weekday = truthy(fact.bar_show_weekday)
    local show_cd = truthy(fact.bar_show_countdown) and bar_cd_title ~= ""

    local date_txt = (show_date and bar_today_date ~= "") and bar_today_date or ""
    local lunar_txt = (show_lunar and bar_today_lunar ~= "") and bar_today_lunar or ""
    local weekday_txt = ""
    if show_weekday and bar_today_weekday ~= "" then
        weekday_txt = "·" .. bar_today_weekday:gsub("^星期", "周")
    end
    local mo_n, dy_n = bar_today_date:match("^(%d+)%-(%d+)$")
    mo_n = tonumber(mo_n) or today.month
    dy_n = tonumber(dy_n) or today.day
    fact.bar_mon_d0 = math.floor(mo_n / 10)
    fact.bar_mon_d1 = mo_n % 10
    fact.bar_day_d0 = math.floor(dy_n / 10)
    fact.bar_day_d1 = dy_n % 10

    text.bar_date_txt = date_txt
    text.bar_lunar_txt = lunar_txt
    text.bar_weekday_txt = weekday_txt
    fact.bar_has_date = date_txt ~= ""
    fact.bar_has_lunar = lunar_txt ~= ""
    fact.bar_has_weekday = weekday_txt ~= ""
    fact.bar_date_any = date_txt ~= "" or lunar_txt ~= "" or weekday_txt ~= ""
    text.bar_cd_title = show_cd and bar_cd_title or ""
    text.bar_cd_days = show_cd and bar_cd_days_txt or ""
    fact.bar_cd_urgent = show_cd and bar_cd_days <= 7
    fact.bar_has_cd = show_cd
end

--  Fraction of the current month still ahead, today included.  The ring
--  around today's number uses this: full on the first, nearly gone at the
--  end of the month.
local function month_progress(year, month, day)
    local days = os.date("*t", os.time({ year = year, month = month + 1, day = 0 })).day
    if days < 1 then return 1 end
    return clamp((days - day + 1) / days, 0, 1)
end

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
    text.ct_header_date = string.format("%d年%d月%d日", today.year, today.month, today.day)
    text.ct_month = string.format("%d年 %d月", ft.year, ft.month)
    text.ct_month_sub = string.format("第 %d 周", iso_week(first))
    text.ct_weekday = WEEKDAYS[today.wday]
    fact.center_cal_progress = month_progress(today.year, today.month, today.day)
    text.ct_today_day = string.format("%02d", today.day)
    text.ct_today_month = string.format("%d月", today.month)
    text.ct_today_year = tostring(today.year)
    text.ct_weeknum = string.format("第 %d 周", iso_week(os.time()))
    local ymd = string.format("%04d-%02d-%02d", today.year, today.month, today.day)
    if ymd ~= bar_last_ymd then
        bar_last_ymd = ymd
        bar_today_lunar = ""
    end
    bar_today_date = string.format("%02d-%02d", today.month, today.day)
    bar_today_weekday = WEEKDAYS[today.wday] or ""
    refresh_bar_date()
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
    local now_t = os.date("*t")
    bar_last_ymd = string.format("%04d-%02d-%02d", now_t.year, now_t.month, now_t.day)
    bar_today_date = tostring(td.date or string.format("%02d-%02d", now_t.month, now_t.day))
    bar_today_lunar = tostring(td.lunar or "")
    bar_today_weekday = tostring(td.weekday or WEEKDAYS[now_t.wday] or "")
    local nc = type(d.next_countdown) == "table" and d.next_countdown or nil
    if nc and tostring(nc.title or "") ~= "" then
        bar_cd_title = tostring(nc.title)
        bar_cd_days = math.floor(number(nc.days, 0))
        bar_cd_days_txt = tostring(nc.days_txt or (bar_cd_days == 0 and "今天" or (tostring(bar_cd_days) .. "天")))
    else
        bar_cd_title, bar_cd_days_txt, bar_cd_days = "", "", 9999
    end
    refresh_bar_date()
    local progress = tonumber(td.month_progress)
    if progress == nil then
        local now = os.date("*t")
        local day = tonumber(td.day) or now.day
        local month = tonumber((tostring(td.month or "")):match("(%d+)")) or now.month
        local year = tonumber(td.year) or now.year
        progress = month_progress(year, month, day)
    end
    fact.center_cal_progress = clamp(progress, 0, 1)
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
local wx_sky_state = { rise = 360, set = 1140, off = 0, has_off = false }
local function update_wx_sky()
    local now_sec = os.time()
    local t = wx_sky_state.has_off and os.date("!*t", now_sec + wx_sky_state.off) or os.date("*t", now_sec)
    local now_m = t.hour * 60 + t.min + t.sec / 60
    local r, st = wx_sky_state.rise, wx_sky_state.set
    if r and st and st > r then
        fact.wx_sun = clamp((now_m - r) / (st - r), 0, 1)
        local edge = math.min(now_m - r, st - now_m)
        fact.wx_dl = clamp((edge + 35) / 70, 0, 1)
    else
        fact.wx_sun = 0.5
        fact.wx_dl = (t.hour >= 7 and t.hour < 18) and 1 or 0
    end
    -- Synodic month phase since known new moon 2000-01-06 18:14 UTC
    fact.wx_moon = ((now_sec - 947182440) / 86400 / 29.53058867) % 1
end

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
            model.wx_hrs = {}
            fact.wx_hrs_count = 0
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
        fact.wx_kind = math.floor(clamp(number(d.kind, 0), 0, 6))
        fact.wx_wind_n = clamp(number(d.wind_n, 5), 0, 50)
        fact.wx_wdir = number(d.wind_dir, 1) < 0 and -1 or 1
        wx_sky_state.rise = number(d.sunrise, 360)
        wx_sky_state.set = number(d.sunset, 1140)
        if d.utc_offset ~= nil then
            wx_sky_state.off = number(d.utc_offset, 0)
            wx_sky_state.has_off = true
        else
            wx_sky_state.has_off = false
        end
        update_wx_sky()

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

        local hrs24 = {}
        for i, h in ipairs(d.hourly24 or {}) do
            if i > 25 then break end
            hrs24[i] = {
                t = number(h.t, 0),
                deg = tostring(h.deg or ""),
                label = tostring(h.label or ""),
                icon = tostring(h.icon or "·"),
                kind = math.floor(clamp(number(h.kind, 0), 0, 6)),
            }
        end
        model.wx_hrs = hrs24
        fact.wx_hrs_count = #hrs24
        fact.wx_hlo = number(d.h_min, 0)
        fact.wx_hhi = number(d.h_max, 25)

        local days = {}
        for i, w in ipairs(d.daily or {}) do
            if i > 4 then break end
            days[i] = {
                day = tostring(w.day or ""),
                icon = tostring(w.icon or "·"),
                hi = tostring(w.hi or ""),
                lo = tostring(w.lo or ""),
                kind = math.floor(clamp(number(w.kind, 0), 0, 6)),
                desc = tostring(w.desc or ""),
                hi_n = number(w.hi_n, 20),
                lo_n = number(w.lo_n, 10),
            }
        end
        model.wx_daily = days
        fact.wx_wlo = number(d.w_min, 0)
        fact.wx_whi = number(d.w_max, 25)
    end)
end

local function refresh_audio_outputs()
    if audio_watched then return end
    --  Fallback when the native audio watch has not provided outputs.
    run("sh", { "-c", "wpctl status 2>/dev/null" }, function(out)
        if audio_watched or not out or out == "" then return end
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

local function flush_app_vols()
    app_vol_timer = false
    local cmds = {}
    for id, vol in pairs(app_vol_pending) do
        cmds[#cmds + 1] = string.format("wpctl set-volume %d %.3f >/dev/null 2>&1", id, vol)
    end
    app_vol_pending = {}
    if #cmds == 0 then return end
    run("sh", { "-c", table.concat(cmds, "; ") }, function() end)
end

local function refresh_audio_apps()
    if audio_app_busy or next(app_vol_pending) ~= nil then return end
    audio_app_busy = true
    local root = root_of and root_of() or ""
    local path = root ~= "" and (root .. "/bin/pleamar-audio-apps") or "pleamar-audio-apps"
    run("sh", { "-c", shq(path) .. " list" }, function(out, code)
        audio_app_busy = false
        if code ~= 0 then return end
        local ok, parsed = pcall(json.decode, out or "")
        if not ok or type(parsed) ~= "table" then return end
        if next(app_vol_pending) ~= nil then return end
        local ids, rows = {}, {}
        for i, item in ipairs(parsed) do
            if i > 8 then break end
            local oid = math.floor(number(item.id, 0))
            if oid > 0 then
                ids[#ids + 1] = oid
                rows[#rows + 1] = {
                    name = tostring(item.name or "Application"),
                    media = tostring(item.media or ""),
                    vol = clamp(number(item.vol, 1), 0, 1.5),
                    muted = truthy(item.muted),
                    active = truthy(item.active),
                }
            end
        end
        audio_app_ids = ids
        audio_app_rows = rows
        model.audio_apps = rows
        fact.audio_apps_count = #rows
    end)
end

local function close()
    fact.center_open = false
    fact.center_power_confirm = -1
    fact.audio_pick_open = false
    fact.tray_menu_open = false
    fact.tray_submenu_open = false
    refresh_sys()
end

local function dismiss_top()
    if number(fact.center_power_confirm, -1) >= 0 then
        fact.center_power_confirm = -1
    elseif truthy(fact.audio_pick_open) then
        fact.audio_pick_open = false
    else
        close()
    end
end

local function modal_open()
    return number(fact.center_power_confirm, -1) >= 0 or truthy(fact.audio_pick_open)
end

local function set_tab(n)
    n = math.floor(clamp(number(n, 0), 0, 6))
    if n ~= last_tab then
        fact.center_tab_dir = (n >= last_tab) and 1 or -1
        last_tab = n
    end
    fact.center_tab = n
    fact.wx_hv = -1
    fact.center_cal_hover = -1
    if n == 4 and truthy(fact.center_open) then
        refresh_audio_apps()
    end
end

local function open(tab)
    local n = tab ~= nil and math.floor(number(tab, 0)) or math.floor(number(fact.center_tab, 0))
    if n < 0 or n > 6 then n = 0 end
    fact.panel_open = false
    fact.launch_open = false
    fact.nt_center = false
    set_tab(n)
    fact.center_sys_scroll = 0
    fact.center_open = true
    fact.tray_menu_open = false
    fact.tray_submenu_open = false
    fact.audio_pick_open = false
    calendar()
    refresh_weather()
    refresh_audio_outputs()
    if n == 4 then refresh_audio_apps() end
    refresh_sys()
end

function M.start(root_getter)
    root_of = root_getter

    on("fact:center_open", function(v)
        if truthy(v) then
            refresh_sys()
            if math.floor(number(fact.center_tab, 0)) == 4 then
                refresh_audio_apps()
            end
        else
            fact.center_power_confirm = -1
            fact.audio_pick_open = false
            fact.tray_menu_open = false
            fact.tray_submenu_open = false
            fact.center_cal_hover = -1
            refresh_sys()
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
        local svc = v == 0 and "session.logout" or (v == 1 and "session.reboot" or "session.poweroff")
        local ok = pcall(sys.call, svc)
        if ok then return end
        local cmd = v == 0 and "niri msg action quit --skip-confirmation"
            or v == 1 and "systemctl reboot --no-block"
            or "systemctl poweroff --no-block"
        run("sh", { "-c", cmd }, function(_, code)
            if code ~= 0 then log("power action failed: " .. cmd) end
        end)
    end)

    on("center_key_digit", function(n)
        if not truthy(fact.center_open) or modal_open() then return end
        local v = math.floor(number(n, 0))
        if v >= 1 and v <= 7 then
            set_tab(v - 1)
            fact.center_sys_scroll = 0
            fact.tray_menu_open = false
            fact.audio_pick_open = false
        end
    end)
    on("center_key_tab", function(d)
        if not truthy(fact.center_open) or modal_open() then return end
        local dir = number(d, 1) < 0 and -1 or 1
        set_tab((math.floor(number(fact.center_tab, 0)) + dir + 7) % 7)
        fact.center_sys_scroll = 0
        fact.tray_menu_open = false
        fact.audio_pick_open = false
    end)
    on("center_key_escape", function()
        if truthy(fact.center_open) then dismiss_top() end
    end)
    on("center_key_blur", function()
        if truthy(fact.center_open) then close() end
    end)

    on("key_down", function(name)
        if not truthy(fact.center_open) then return end
        name = tostring(name or "")
        --  Escape is handled declaratively via `on key Escape` in CenterPanel
        --  so pressing Escape with a modal open never dismisses twice.
        if name == "Escape" or modal_open() then return end
        if name == "Tab" or name == "ISO_Left_Tab" or name == "Backtab" then
            local d = (held("Shift") or name == "ISO_Left_Tab" or name == "Backtab") and -1 or 1
            set_tab((math.floor(number(fact.center_tab, 0)) + d + 7) % 7)
            fact.center_sys_scroll = 0
            fact.tray_menu_open = false
            return
        end
        local n = tonumber(name)
        if n and n >= 1 and n <= 7 then
            set_tab(n - 1)
            fact.center_sys_scroll = 0
            fact.tray_menu_open = false
        end
    end)

    on("center_scroll", function(d)
        fact.center_sys_scroll = clamp(number(fact.center_sys_scroll, 0) - number(d, 0), 0, 500)
    end)
    on("fact:center_tab", function(v)
        local n = math.floor(clamp(number(v, 0), 0, 6))
        if n ~= last_tab then
            fact.center_tab_dir = (n >= last_tab) and 1 or -1
            last_tab = n
        end
        fact.wx_hv = -1
        fact.center_cal_hover = -1
        if n == 4 and truthy(fact.center_open) then
            refresh_audio_apps()
        end
    end)
    on("fact:sys_proc_sort", function()
        if #last_raw_procs == 0 then return end
        local sort_mem = math.floor(number(fact.sys_proc_sort, 0)) == 1
        local sorted = {}
        for _, p in ipairs(last_raw_procs) do sorted[#sorted + 1] = p end
        table.sort(sorted, function(a, b)
            if sort_mem then
                local ma, mb = number(a.mem, 0), number(b.mem, 0)
                if ma ~= mb then return ma > mb end
                return number(a.cpu, 0) > number(b.cpu, 0)
            end
            local ca, cb = number(a.cpu, 0), number(b.cpu, 0)
            if ca ~= cb then return ca > cb end
            return number(a.mem, 0) > number(b.mem, 0)
        end)
        local prs = {}
        for i, p in ipairs(sorted) do
            if i > 6 then break end
            prs[i] = { name = p.n, cpu = clamp((p.cpu or 0) / 100, 0, 1),
                cpu_txt = string.format("%.1f%%", p.cpu or 0),
                mem = clamp((p.mem or 0) / 100, 0, 1),
                mem_txt = string.format("%.1f%%", p.mem or 0) }
        end
        model.sys_procs = prs
    end)

    on("center_power_exec", function(k)
        local v = math.floor(number(k, -1))
        if v < 0 or v > 2 then return end
        after(220, function()
            close()
            local svc = v == 0 and "session.logout" or (v == 1 and "session.reboot" or "session.poweroff")
            local ok = pcall(sys.call, svc)
            if ok then return end
            local cmd = v == 0 and "niri msg action quit --skip-confirmation"
                or v == 1 and "systemctl reboot --no-block"
                or "systemctl poweroff --no-block"
            run("sh", { "-c", cmd }, function(_, code)
                if code ~= 0 then log("power action failed: " .. cmd) end
            end)
        end)
    end)

    on("center_cal_step", function(d)
        local step = number(d, 0)
        fact.center_cal_dir = step >= 0 and 1 or -1
        fact.center_cal_tick = number(fact.center_cal_tick, 0) + 1
        fact.center_cal_off = clamp(number(fact.center_cal_off, 0) + step, -120, 120)
        calendar()
    end)
    on("center_cal_today", function()
        fact.center_cal_dir = cal_off > 0 and -1 or 1
        fact.center_cal_tick = number(fact.center_cal_tick, 0) + 1
        fact.center_cal_off = 0
        calendar()
    end)

    local function wpcall(cmd)
        run("sh", { "-c", "wpctl " .. cmd .. " >/dev/null 2>&1" }, function(_, code)
            if code ~= 0 then log("wpctl " .. cmd .. " failed") end
        end)
    end
    on("center_audio_set", function(v)
        local vol = clamp(number(v, 0), 0, 1)
        if not pcall(sys.call, "audio.volume", vol) then
            wpcall(string.format("set-volume @DEFAULT_AUDIO_SINK@ %.0f%%", vol * 100 + 0.5))
        end
    end)
    on("center_audio_mute", function()
        if not pcall(sys.call, "audio.mute") then
            wpcall("set-mute @DEFAULT_AUDIO_SINK@ toggle")
        end
    end)
    on("center_input_set", function(v)
        local vol = clamp(number(v, 0), 0, 1)
        if not pcall(sys.call, "audio.input", vol) then
            wpcall(string.format("set-volume @DEFAULT_AUDIO_SOURCE@ %.0f%%", vol * 100 + 0.5))
        end
    end)
    on("center_input_mute", function()
        if not pcall(sys.call, "audio.input_mute") then
            wpcall("set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
        end
    end)
    on("center_app_vol", function(packed)
        local n = math.floor(number(packed, -1))
        if n < 0 then return end
        local idx = math.floor(n / 1000) + 1
        local vol = clamp((n % 1000) / 100, 0, 1.5)
        local id = audio_app_ids[idx]
        if not id or not audio_app_rows[idx] then return end
        audio_app_rows[idx].vol = vol
        model.audio_apps = audio_app_rows
        app_vol_pending[id] = vol
        if not app_vol_timer then
            app_vol_timer = true
            after(60, flush_app_vols)
        end
    end)
    on("center_app_mute", function(i)
        local idx = math.floor(number(i, -1)) + 1
        local id = audio_app_ids[idx]
        if not id or not audio_app_rows[idx] then return end
        audio_app_rows[idx].muted = not audio_app_rows[idx].muted
        model.audio_apps = audio_app_rows
        wpcall(string.format("set-mute %d toggle", id))
        after(180, refresh_audio_apps)
    end)
    on("center_media", function(action)
        local call = ({ [0] = "media.previous", [1] = "media.toggle", [2] = "media.next" })[math.floor(number(action, 1))]
        if call then pcall(sys.call, call) end
    end)
    on("center_quick", function(k)
        local i = math.floor(number(k, -1))
        if i == 0 then fact.music_frame_on = not truthy(fact.music_frame_on)
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
            if not pcall(sys.call, "audio.default", id) then
                run("sh", { "-c", "wpctl set-default " .. tostring(id) }, function(_, code)
                    if code ~= 0 then log("wpctl set-default failed") end
                end)
            end
        end
        fact.audio_pick_open = false
        if not audio_watched then after(350, refresh_audio_outputs) end
    end)

    sys.watch("audio", function(a)
        if type(a) ~= "table" or type(a.outputs) ~= "table" then return end
        local rows, ids, current = {}, {}, "Default sink"
        for i, o in ipairs(a.outputs) do
            if i > 8 then break end
            local name = tostring(o.name or "Output")
            local cur = truthy(o.default)
            rows[#rows + 1] = { name = name, current = cur }
            ids[#ids + 1] = o.id
            if cur then current = name end
        end
        if #rows > 0 then
            audio_watched = true
            audio_out_ids = ids
            model.audio_outputs = rows
            text.audio_out_name = current
        end
    end)

    do
        local art_seq = 0
        local last_song = ""
        local mp_player = ""
        local mp_playing = false
        local mp_quiet = 0

        local function mpris_bin()
            local root = root_of and root_of() or ""
            return root ~= "" and (root .. "/bin/pleamar-mpris") or "pleamar-mpris"
        end

        local function fetch_art(player, seq_expected)
            local cmd = shq(mpris_bin()) .. " art " .. shq(player or "")
            run("sh", { "-c", cmd }, function(out, code)
                if seq_expected ~= art_seq then return end
                local p = tostring(out or ""):gsub("%s+$", "")
                if code == 0 and p ~= "" then
                    text.ct_art_path = p
                    fact.ct_art_on = true
                end
            end)
        end

        local function read_pos()
            if not truthy(fact.ct_has_track) or mp_quiet > 0 then return end
            local cmd = shq(mpris_bin()) .. " pos " .. shq(mp_player)
            run("sh", { "-c", cmd }, function(out, code)
                if mp_quiet > 0 or code ~= 0 then return end
                local v = tonumber((tostring(out or "")):match("[%d%.]+"))
                if v then
                    fact.ct_media_pos = v
                    text.ct_media_pos_txt = clock_len(v)
                end
            end)
        end

        sys.watch("media", function(m)
            if not m then return end
            local player = tostring(m.player or "")
            local title = tostring(m.title or "")
            local artist = tostring(m.artist or "")
            mp_player = player
            mp_playing = truthy(m.playing)
            local len = number(m.length, 0)
            fact.ct_media_len_s = len
            text.ct_media_len = clock_len(len)
            local has = title ~= ""
            fact.ct_has_track = has
            if not has then
                art_seq = art_seq + 1
                last_song = ""
                text.ct_art_path = ""
                fact.ct_art_on = false
                fact.ct_media_pos = 0
                text.ct_media_pos_txt = "0:00"
                return
            end
            local key = player .. "|" .. title .. "|" .. artist
            if key ~= last_song then
                local first = last_song == ""
                last_song = key
                art_seq = art_seq + 1
                local seq = art_seq
                fact.ct_art_on = false
                text.ct_art_path = ""
                fact.ct_media_pos = 0
                text.ct_media_pos_txt = "0:00"
                if not first then
                    fact.ct_track_tick = number(fact.ct_track_tick, 0) + 1
                end
                fetch_art(player, seq)
                after(1200, function()
                    if seq == art_seq and not truthy(fact.ct_art_on) then
                        fetch_art(player, seq)
                    end
                end)
                after(200, read_pos)
            end
        end)

        on("center_media_seek", function(frac)
            local len = number(fact.ct_media_len_s, 0)
            if len <= 0 then return end
            local sec = clamp(number(frac, 0), 0, 1) * len
            fact.ct_media_pos = sec
            text.ct_media_pos_txt = clock_len(sec)
            mp_quiet = 2
            local cmd = shq(mpris_bin()) .. " seek " .. shq(mp_player) .. " " .. string.format("%.2f", sec)
            run("sh", { "-c", cmd }, function() end)
        end)

        on("fact:center_open", function(v)
            if truthy(v) then after(120, read_pos) end
        end)

        every(1000, function()
            if mp_quiet > 0 then mp_quiet = mp_quiet - 1 end
            if not truthy(fact.center_open) or not truthy(fact.ct_has_track) then return end
            local tab = math.floor(number(fact.center_tab, 0))
            if (tab == 0 or tab == 3) and mp_playing and number(fact.ct_media_len_s, 0) > 0 then
                read_pos()
            end
        end)
    end

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
            if i > 32 then break end
            local name = tostring(it.title or "")
            if name == "" then name = tostring(it.id or "Tray item") end
            local sub = tostring(it.tooltip_body or it.tooltip or it.id or "")
            local icon = tostring(it.icon or "")
            rows[i] = { icon = icon, has_icon = icon ~= "", name = name, sub = sub, status = tostring(it.status or ""), has_sub = sub ~= "" }
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
            if n > 32 then break end
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
            if j > 32 then break end
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

    every(1500, function()
        if truthy(fact.center_open) and math.floor(number(fact.center_tab, 0)) == 4 then
            refresh_audio_apps()
        end
    end)
    every(60000, function()
        if truthy(fact.center_open) then update_wx_sky() end
    end)
    every(900000, function()
        if truthy(fact.center_open) then refresh_weather() end
    end)
    every(30000, function()
        local ymd = os.date("%Y-%m-%d")
        if ymd ~= bar_last_ymd then
            bar_last_ymd = ymd
            bar_today_date = ""
            bar_today_lunar = ""
            bar_today_weekday = ""
            refresh_bar_date()
            calendar()
        end
    end)
    bar_last_ymd = os.date("%Y-%m-%d")
    refresh_bar_date()
    calendar()
    refresh_audio_outputs()
    refresh_sys()
end

function M.refresh_bar_date()
    refresh_bar_date()
end

function M.refresh_sys()
    refresh_sys()
end

function M.refresh_root()
    --  The first calendar() runs before PLEAMAR_SHELL_ROOT is known, so it
    --  falls back to a lunar-less grid.  Reload it once the root arrives.
    calendar()
    refresh_sys()
end

function M.close() close() end
function M.open(tab) open(tab) end

return M
