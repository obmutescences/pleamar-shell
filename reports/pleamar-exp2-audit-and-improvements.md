# pleamar-shell 深度评估与改进路线图（结合 Pleamar `exp2` 最新能力）

> 评估日期：2026-11-23  
> 当前项目分支：`feat/pleamar-0.8-exp`  
> 当前 `flake.lock` 锁定引擎：`k4ditano/pleamar/exp2` @ `338ffd7a`（`pleamar 0.8.0-exp.3`，`language 0.9`，但场景头部仍声明 `language 0.4`）  
> 上游 `exp2` 最新版本：`13302388`（`pleamar 0.8.0-exp.39`，`language 0.10`，领先当前锁定版本 **142 个提交**）

---

## 0. 执行摘要

`pleamar-shell` 在“四边连续液态玻璃框架 + 音乐可视化 + 液态颈部抽屉”的视觉创意上非常有辨识度，但随着功能从旧版双布局演进到单一 `Notches` 布局、同时上游 `pleamar/exp2` 快速迭代到 `0.8.0-exp.39`，当前仓库积累了四类突出问题：

1. **多个肉眼可见的功能/布局 Bug**：例如 `PanelBackdrop` 被 `not notch_mode` 隐藏导致整套主题渐变与面板着色设置失效、内存历史柱状图因 `pick()` 误用只画第 1 根、圆环角度偏移、多处文字与进度条/卡片重叠、音频选择器弹窗写死绝对坐标导致多分辨率错位等。
2. **明显的场景膨胀与外部进程开销**：4 套已废弃的 `not notch_mode` surface 仍被编译实例化，使整个场景的指令/属性/Zone 数量翻倍；同时大量本可由 Pleamar 原生服务完成的工作（音频输出、音量控制、剪贴板、会话关机、配置读写、环境变量）仍在高频 `spawn`/`run` 外部 shell。
3. **尚未享受到 `exp2` 近 142 个提交的核心红利**：包括 `include … while` 按需懒加载、合成器模糊覆盖融合颈部（`pleamar#170`）、`systemd` 独立 scope 启动应用、列表惯性滚动 `inertia:`、独立字形图集与按盒解码大图、`--layout` 自动化 UI 质检、`--film` 帧级动画回归测试等。
4. **交互、动画与桌面能力仍有很大成长空间**：多处仍停留在手算坐标、硬切换和单像素外挂键盘进程的妥协阶段；而 `exp2` 已原生提供 `audio.apps`、`media.art/position/players`、`network.networks`、`bluetooth.pairing`、`polkit`、`brightness`、`workspaces`、`thumbnails`、`popup` 嵌套子菜单、`particles`、`pages`、`pleamar:ui` 等能力，足以把 `pleamar-shell` 升级为一个更完整、更省电、更顺滑的桌面壳。

---

## 1. 引擎升级与依赖差异（`0.8.0-exp.3` → `0.8.0-exp.39`）

### 1.1 升级 `flake.lock` 可直接获得的底层修复与收益
执行 `nix flake update pleamar` 升至最新 `exp2` 后，无需大改业务即可获得以下重要改进：

| 上游提交 | 能力 / 修复 | 对 `pleamar-shell` 的直接价值 |
| --- | --- | --- |
| `13302388` (`pleamar#170`) | 合成器模糊覆盖同一 `body` 内两个 `blend` 融合形状之间的液态颈部 | **极高**：当前用户配置中 `glass_bend: false`（走合成器模糊），此前抽屉展开时的液态颈部缺少模糊覆盖，升级后直接修复 |
| `f22c15f3` | 通过 shell 启动的应用放入独立 `systemd` scope | 解决 `systemctl --user restart pleamar-shell` 时把从 Launcher 启动的 GUI 应用一起杀掉的痛点 |
| `83c39287` | 释放 backdrop capture `wl_shm_pool` 且拒绝连接后保持监听 | **注意**：该修复已覆盖本项目本地补丁 `nix/pleamar-shm-pool.patch`，升级 `flake.lock` 时需移除该补丁避免 patch 冲突 |
| `c345974a` (`pleamar#153`) | 新增 `include … while <cond>` 按需加载/休眠页面 | 可让 Settings、Center、Launcher、NotificationCenter 在关闭时不驻留内存和表达式求值 |
| `cf38c2a5` / `5c47a467` / `b27e68ed` | 空闲自动归还显存/图层/模糊纹理，指令体积从 1440B 缩减到数百字节 | 显著降低 24/7 常驻 shell 的内存和显存占用 |
| `1a5fc0e5` / `a2d7c98f` (`pleamar#158`) | 修复 `dome:` 玻璃上的暗色重影，并按需只填充 dome 周围区域 | 消除开启 `glass_dome` 时的残影与全屏填充开销 |
| `15d0f56a` / `a8954fa9` / `3b50746e` | 字形独立 1-byte 图集；`image 0, 0` + `fit: cover/contain` 按盒大小解码；缩小采样防摩尔纹 | 彻底解决 `lockscreen.luau` 注释里提到的 2048×2048 图集塞爆导致时钟数字消失的问题，缩略图与壁纸更锐利、内存减半 |
| `b981d1c9` / `2d25b6f1` (`pleamar#157`) | 列表拖拽惯性滚动 `inertia:`；滚出 `view:` 视口的行不再响应点击 | 改善 Font/Tray/System 列表手感并修复视口外误触 |
| `3fc7ad0c` / `8ba8900a` | 新增 `--layout SCENE` 静态 UI 布局/对比度/重叠/对齐/边距 JSON 体检工具 | 可直接接入 `tests/check.sh`，自动抓出文字遮挡、对比度不足和对齐误差 |
| `cc648b3c` (`pleamar#164`) | 修复 `audio.level` 录音线程永久阻塞 | 为低开销音频响度/静默检测铺路 |
| `3911c5ed` / `9bd75bca` / `fcccba04` | `screens: each` 锁屏多屏支持与按显示器独立路由键盘焦点 | 改善多显示器场景下的锁屏与键盘焦点问题 |
| `4cb06a51` | 每个 surface 同时只挂一个 frame callback | 防止隐藏 surface 堆积帧回调导致唤醒抖动 |

### 1.2 升级前注意事项
- 移除已上游合并的 `nix/pleamar-shm-pool.patch`，并复核 `nix/pleamar-layer-names.patch` 在最新 `src/platform/wayland.rs` 上的上下文行号。
- 将 `scenes/notches.plm`、`scenes/centerkeys.plm`、`scenes/settingskeys.plm` 与 `lockscreen/lockscreen.plm` 的 `language` 版本声明统一提升至 `0.9` / `0.10`，避免继续隐式依赖高版本特性。

---

## 2. 已确认的问题点与 Bug 清单（按严重度排序）

### P0 — 功能失效 / 明显渲染错误

1. **主题渐变、顶部柔光与面板着色控制在 Notches 模式下完全无效**
   - **位置**：`modules/common/common.plm:90-115`、`modules/notches/frame.plm:82-87`、`modules/settings/panel.plm:642-672, 1165-1187`
   - **原因**：`PanelBackdrop` 内所有 3 个 `body` 都写了 `show: not notch_mode and ...`，而 `notch_mode` 在 `common.plm:342` 和 `shell.luau:25` 恒为 `true`。同时 `frame.plm` 直接使用 `nf.smoke_bg` 而非 `bar_bg`/`panel_bg`。
   - **后果**：用户在 **Settings › Bar** 调节 `Panel colour`、`Tint depth`，或在 **Settings › Theme** 开启 `Gradient`、切换 `Linear/Radial`、拖动 `Strength` 滑块，画面不会有任何变化。

2. **System 页「内存 1 分钟历史柱状图」永远只显示第 1 根柱子**
   - **位置**：`modules/center/panel.plm:640-643`
   - **原因**：第 641 行写了 `let hv = clamp(pick(i, sys_hist.$i.mem, 0), 0, 1)`。`pick(index, v0, v1)` 仅在 `i == 0` 时返回 `sys_hist.0.mem`，`i >= 1` 时全部返回第 2 个参数 `0`！
   - **修复**：改为直接使用 `clamp(sys_hist.$i.mem, 0, 1)`，或与 CPU/GPU/Network 统一采用更可靠的 `sparkline("mem", 60, 1)`（也避免 `model` 满 60 行后的更新问题）。

3. **Settings › Frame music 页 `Coverage` 卡片的按钮溢出并压住下方 `Sensitivity` 卡片**
   - **位置**：`modules/settings/panel.plm:432-445`
   - **原因**：`Coverage` 卡片区域是 `y = 242..304`（高 62px），但内部的 `Top edge` / `Four sides` 按钮被画在 `y = 286..316`，点击热区更是 `y = 280..318`，直接越过卡片底边并覆盖 `Sensitivity` 卡片顶部（`y = 308`）。
   - **修复**：将 `Top edge` / `Four sides` 按钮垂直居中放入卡片右侧（`y = 258, h = 30`，与 `Panel colour` 卡片对齐）。

4. **音频输出选择器弹窗写死屏幕绝对坐标，多分辨率下错位或溢出屏幕**
   - **位置**：`modules/center/panel.plm:1285-1288`
   - **原因**：`popup audio_picker { at: 1070, 140; size: 420, 500; ... }` 硬编码了 `x = 1070`。在 1366/1440 宽屏幕下 `1070 + 420 = 1490` 直接超出屏幕右边界；在 2560/3840 宽屏幕下又偏离中心面板左侧的 Output 卡片。
   - **修复**：改为相对 `screen.width` / `ct.px` 动态计算（例如 `at: ct.px + 36, notch_clock_h + 152`），紧贴左侧 Audio Output 卡片展开。

5. **Memory 与 Audio 页面的进度圆环起始方向错误**
   - **位置**：`modules/center/panel.plm:624, 789`
   - **原因**：Pleamar 的 `arc` 是以正上方为对称轴向两侧张开的（见 `pleamar --docs recipes`），从 12 点钟顺时针增长必须设置 `rotate: span / 2`（如 CPU 的 `180 * sys_cpu * 1deg`）。Memory（line 624）和 Audio（line 789）写成了 `rotate: -90deg`，导致圆弧从 9 点钟位置向**上下双向对称扩张**，而非顺时针填充。

6. **System 页「温度」与「存储挂载点」卡片存在文字与进度条重叠**
   - **位置**：`modules/center/panel.plm:652-655, 725-728`
   - **原因**：
     - Temperatures：标签文本在 `x = 52, width = 170`（覆盖 `52..222`），而进度条从 `x = 126` 就开始绘制，较长的传感器名称（如 `CPU package`、`Hottest core`、`NVMe drive`）直接压在进度条上。
     - Storage：挂载点路径在 `x = 572, width = 180`（覆盖 `572..752`），进度条却从 `x = 610` 开始，只要挂载路径不是单字符 `/`（如 `/home`、`/boot`）就会与进度条重叠。

---

### P1 — 架构冗余、性能浪费与潜在稳定性问题

7. **4 套废弃的 `not notch_mode` Surface 仍被编译，场景体积直接翻倍**
   - **位置**：`modules/settings/panel.plm:1214`、`modules/center/panel.plm:1217`、`modules/launcher/launcher.plm:109`、`modules/notifications/notifications.plm:261`
   - **影响**：每个页面组件（`ConfigPanelContent`、`CenterPanelContent`、`LauncherContent`、`NotificationCenterContent`）都在 `NotchFrame` 里实例化一遍，又在各自废弃 surface 里完整实例化第二遍，导致当前 `scenes/notches.plm` 膨胀到 **1807 properties / 12959 instructions / 1106 rules / 783 zones**。清理后可立即砍掉近一半内存与冷启动编译耗时。

8. **Center Panel 黑胶唱片与 `ct_time` 计时器在暂停/非媒体页时仍空转**
   - **位置**：`modules/center/panel.plm:263-264, 399-402, 852-855`
   - **问题**：注释写着 *"the record turns only while the player plays"*，实际代码是 `spin ct_time by if(center_open, 1, 0)`，只要中心面板打开（哪怕在 System/Calendar/Actions 页或根本没放歌），就会强制 60fps 持续重绘。
   - **修复**：改为仅在 `center_open and med.playing and (center_tab == 0 or center_tab == 3)` 时旋转（频率柱的空闲呼吸波仅在 `center_tab == 3 or center_tab == 4` 且 `music_on` 时驱动）。

9. **全屏 `notch_frame` 每秒因秒针动画触发整屏重绘**
   - **位置**：`modules/notches/frame.plm:12, 1260-1277`
   - **问题**：`notch_frame` 是 `size: full, full` 的全屏玻璃 surface。虽然静默时 `rate` 降到了 15fps，但 `on change tick.second` 每秒触发 200ms 的 `nf_sec_ones` 弹性动画，导致桌面完全静止时每秒仍要渲染多帧全屏合成。
   - **优化**：提供“Bar 显示秒数 / 秒数动画”开关，或将纯时钟文本拆分到独立的小尺寸 surface（通过 `import scene` 同进程运行），避免秒针跳动牵连全屏四边玻璃重绘。

10. **`modules/notches/frame.plm` 存在 ~850 行高度重复的四份 `body` 模板**
    - **位置**：`modules/notches/frame.plm:367-1211`
    - **问题**：仅为切换 `music_frame_cols`（6 / 12 / 24 / 48），将 Ring、Clock notch、4 个 Drawer 形状、bell 椭圆、抽屉边缘音乐柱和四周音乐柱完整复制了 4 份。后续每次修改抽屉几何或时钟槽形状都要改 4 处，极易遗漏不同步。
    - **优化**：合并为一个统一 `body`（最多 48 根柱子，按 `i < nf.nuse` 与动态位置表达式 `nf.w * (i + 0.5) / nf.nuse` 统一排布，多余柱子 `show: false` 并移出视口），可直接删减 ~700 行冗余代码并大幅减少场景指令数。

11. **高频 `sh` 子进程轮询与外部命令依赖过重**
    - **位置**：
      - `scenes/lib/shell.luau:2128`：每 2 秒 spawn `sh` → `pleamar-lock alive` → `pleamar --say`（一天产生 >43,000 次进程创建！且 `pleamar-lock-keeper` systemd 服务已在外部守护锁屏）。
      - `scenes/lib/shell.luau:846`：每 5 秒 spawn `sh` → `pleamar-wall ensure`。
      - `lockscreen/lockscreen.luau:406-423`：每 2 秒 `ls /sys/class/drm` + 逐个 `cat dpms`。
      - `scenes/lib/center.luau:479, 680, 723`：用 `wpctl status` / `wpctl set-volume` / `wpctl set-default` 代替原生 `audio` 服务。
      - `scenes/lib/shell.luau:80, 188, 467, 1430, 1515`：用 `sh -c 'printf ...'` 读写配置、用 `wl-copy` 写剪贴板，而非原生 `files` / `clipboard` 服务。
      - `scenes/lib/center.luau:611-616`：用 `systemctl` / `niri` 代替原生 `session.*` 服务。

12. **单像素外挂键盘辅助进程脆弱且存在竞争条件**
    - **位置**：`scenes/centerkeys.plm`、`scenes/settingskeys.plm`、`scenes/lib/shell.luau:551-627, 2148-2160`
    - **问题**：为了绕开旧版多层 surface 键盘焦点问题，单独拉起 `centerkeys` 和 `settingskeys` 进程并靠每 700ms 一次 `emit key_ping` 保活、超时靠 `pkill -f` 自杀。这带来了显著启动延迟（`after(250)` 丢首字风险）、无法使用真实光标选区/中文 IME 候选框紧贴输入框（候选框弹在屏幕左上角 `(0, 0)` 的 8×8 透明块处！）。
    - **改进**：在 `exp2` 中，`keyboard: exclusive while <cond>`（`fcccba04`）和 `popup { keyboard: true }` 均已成熟，应验证将 `notch_frame` 的 `keyboard:` 改为 `exclusive while launch_open or center_open or (panel_open and (settings_page == 3 or settings_page == 9))` 或将搜索/输入面板做成原生 `popup`，从而彻底移除这两个外挂进程，顺带原生获得 **中文 IME 跟随光标** 和 **撤销/重做/框选**！

---

### P2 — 细节缺陷与一致性问题

13. **Settings › Theme 页存在 82px 空洞，且 `glass_light` 失去界面入口**
    - **位置**：`modules/settings/panel.plm:1142-1172`（原行号）
    - **问题**：`Gradient` 卡片结束于 `y = 390`，下一张 `Inner border` 卡片从 `y = 472` 开始，中间白白空出 82px。`common.plm:70` 和 `config.json` 中的 `glass_light`（当前值 `0.547`）没有对应的滑块可以调节。

14. **Settings › Wallpaper 页卡片顶部按钮压线、控件代码顺序混乱**
    - **位置**：`modules/settings/panel.plm:688-762`
    - **问题**：`Random` 和 `Refresh` 两个 pill 放在 `y = 176`，紧贴 `Current` 卡片上边框且与下方 `wall_count` 拥挤；`Transition` 卡片（`y = 740`）写在 `Prev/Next`（`y = 618`）之前，底部提示在 `y = 800` 贴近 820 面板底边。

15. **Notification Toast 的顶部 `margin: 56` 未跟随 `notch_clock_h`**
    - **位置**：`modules/notifications/notifications.plm:53`
    - **问题**：用户调高 `notch_clock_h`（最大 96px）时，Top center 模式的通知卡片会被顶部时钟槽遮挡；调低到 30px 时又留出多余空白。

16. **System 页 CPU 核心网格上限 16，截断高线程 CPU**
    - **位置**：`modules/center/panel.plm:84, 607-616`
    - **问题**：`model sys_cores max 24`，但 UI 循环写死 `repeat c in 0..16`，超过 16 核/线程的处理器（如 24/32 线程）会被静默截断；且整个 System 页滚动高度写死 `clamp(..., 0, 500)`（`center.luau:668`），与实际内容高度解耦。

17. **Tray 菜单颜色硬编码与长度截断**
    - **位置**：`modules/center/panel.plm:1054-1102`
    - **问题**：菜单文字写死 `#ffffff`（未用 `ink`），且主菜单和子菜单均用 `repeat 0..12` 固定上限，超过 12 项的系统托盘菜单（如 Clash、Steam、OBS 等）无法滚动查看。

18. **Launcher 内置命令与 README 文档过时**
    - **位置**：`scenes/lib/shell.luau:1478-1493`、`README.md:73-75`
    - **问题**：Launcher `>` 命令缺少 Theme(10)、Weather(9)、Motion(6)、Notifications(5) 设置页入口；`README.md` 仍写着不存在的 `pleamar-ipc windows` 与 `settings 0..11`。

---

## 3. UI 设计优化建议

### 3.1 统一视觉语言与双语体系
- **问题**：当前界面中英文混杂严重——Settings 主体是英文，新增 Bar 日期说明与 Weather 提示是中文，Center Panel 顶部日期/日历/天气是中文，其余 5 个 Tab 和标题全是英文。
- **建议**：利用 Pleamar 原生 `translations` 机制（参考 `pleamar --docs reference` §11.1）建立 `zh` / `en` 两套词表，并在 **Settings › Shell** 增加语言切换（默认跟随系统或中文），彻底统一排版质感。

### 3.2 响应系统明暗主题（`color.scheme`）与动态对比度
- **问题**：目前配色完全假设深色壁纸/暗色玻璃，且多处硬编码了 `#ffffff` 或低透明度 `ink`。
- **建议**：
  - 接入 Pleamar 内置 `color.scheme`（`0` 默认 / `1` 暗色 / `2` 亮色），配合 `bin/pleamar-colors` 在浅色模式下生成亮色玻璃基底与深色 `ink`，并确保所有文本遵循 WCAG 对比度。
  - 将 `exp2` 新增的 `pleamar --layout scenes/notches.plm` 纳入 `tests/check.sh`，自动检查文字重叠、出界、对比度过低、左对齐偏差（`misaligned`）与间距不均（`uneven_spacing`）。

### 3.3 布局现代化（从绝对像素转向响应式布局组件）
- **Settings 面板**：
  - 当前左侧导航栏高度固定 520px，下方 200px 空荡荡，可以在底部增加当前壁纸小缩略图 + 当前主题色点预览 + 快捷重置/重启按钮。
  - 右侧页面全部改用 `column { view: 570, 620; gap: 6; inertia: true }` 滚动容器，再也不用为了塞进 820px 面板而死抠每张卡片的 `y` 坐标（Bar、Glass、Theme、Motion 等页面都可自然扩展）。
  - 对选项组（如 `Top edge / Four sides`、`Primary / Secondary`、`Linear / Radial`）改用或参考 `pleamar:ui` 的 `Segmented` 滑块胶囊，选中背景随弹簧滑动而非生硬切色。
- **Center Panel**：
  - System 页改用原生 `column { view: 1040, 518; inertia: true }`，自动计算 `content` 高度和滚动条比例，解决硬编码 `500px` 滚不到底或滚过头的问题；同时用 `grid { columns: 2; gap: 12 }` 规范两栏卡片。
  - Tray 页的中栏 Actions 与右栏 Submenu 改用可滚动 `column { view: ...; inertia: true }`，或者升级为 `exp2` 的原生嵌套 `popup { parent: ...; keyboard: true }`，彻底解除 12 项截断并支持键盘上下选择。
  - Overview 的 4 个资源水箱卡片建议增加 `GPU` 未检测到时的优雅降级（隐藏或替换为网络/磁盘温度，避免长期显示 `0%` 空水箱）。
- **Bar 顶部时钟槽**：
  - 当日期、农历、星期同时开启且 `notch_clock_h` 较小时，可以在单行与双行之外提供明确的布局模式选择（自动 / 紧凑单行 / 上下双行），同时允许用户微调字号。

---

## 4. 动画与动效优化建议

### 4.1 充分利用 `exp2` 原生动画原语
1. **Tab / 设置页丝滑切换（`pages` + `blur` 过渡）**
   - 目前 Center Panel 切换 Tab 仅做 `ct_page` 10ms 淡出再 260ms 上移淡入，Settings 切页完全是瞬间硬切（`show: settings_page == k`）。
   - 建议使用 Pleamar 原生 `pages` 或方向感知的滑动过渡（向左/右平滑滑入 + 轻微 `blur: 4 * (1 - p)` 失焦入焦），与顶部的移动 Tab 胶囊形成连贯空间感。
2. **玻璃按压/状态切换涟漪（`ripple <zone>`）**
   - `exp2` 支持规则内直接触发 `ripple <zone>`（无需点击，例如键盘按 `1–7` 切换 Center Tab、快捷键切换静音/勿扰、或点击 Quick Controls 时在对应卡片玻璃上荡开一圈真实折射涟漪）。
3. **Quick Controls 开关与弹窗动画补全**
   - 目前 Center › Actions 的 4 个 Quick Controls 开关球（`modules/center/panel.plm:1168`）是 `if(q_on, 1, 0)` 瞬间跳变，应统一复用带弹簧形变的 `CpSwitch` 或为每个开关加 `~quick` 弹簧。
   - `CenterDialogs`（关机确认弹窗）和 `popup audio_picker` 目前是直接显隐，应加微缩放 + 淡入弹簧（`0.94 -> 1.0`, `~180ms`）配合背后的 `blur: 3 * p` 渐进虚化，而不是瞬间跳到 `blur: 3`。
   - Calendar 月份翻页时为 42 格日历添加轻微水平位移 + 透明度过渡，让翻月有物理方向感。
4. **微粒子与发光点缀（`particles` + `group { glow / mode: add }`）**
   - Pleamar 的 `particles` 全程在 GPU 端无状态计算（CPU 零开销）：可在音乐高潮节拍（低频峰值触发 `burst`）或在锁屏解锁成功 (`fact.right`) 时于密码栏释放极克制的主题色微光粒子；在 `CtGlowArc` 中也可评估用 `group { glow: ... }` 替换手写三层叠加 `arc`，光晕更自然且可消除锯齿。
5. **列表惯性滚动（`inertia:`）**
   - 为 Font 列表、Tray 列表、System 页面及未来的通知历史/Wi-Fi 列表开启 `exp2` 新增的 `inertia:`，拖拽松手后具备自然减速滑行。
6. **完善减弱动态（`motion.reduced`）兼容**
   - 目前仅 `impulse ct_sag/cp_sag` 和 `nt_fly` 检查了 `motion.reduced`。应同步让 `card.wgsl` 水面波动、`netfx.wgsl` 扫描光束、`frame_wave.wgsl` 边缘水波、通知铃铛晃动与黑胶旋转在 `motion.reduced == 1` 时进入静态模式。
7. **动画帧级自动化回归（`--film` & `--record`）**
   - 使用 `pleamar --film` 与 `--record` 为关键交互（打开 Settings、展开 Center、切换 Bar 日期开关、弹出 Toast）建立脚本化录制与时序验收测试（检查 1%→99% 到达时间与过冲幅度）。

---

## 5. 新功能建议（基于 Pleamar `exp2` 原生服务与能力）

### 5.1 媒体中心升级（零外部依赖，直接用 `media` 服务）
- **专辑封面展示**：`media` 服务已提供 `art` 字段，可将 Overview 与 Media 页的纯几何黑胶中心替换为真实圆形专辑封面（`clip ellipse` + `image`），无封面时回退到当前唱片图案。
- **播放进度与拖拽快进**：利用 `media.position`、`media.length`、`media.can_seek` 与 `sys.call("media.seek", ...)`，在黑胶外圈或标题下方绘制可拖拽进度条。
- **多播放器切换**：利用 `media.players` 与 `sys.call("media.choose", id)`，同时开着浏览器视频和音乐播放器时可一键指定控制目标。
- **Bar 迷你音乐胶囊（可选开关）**：在 Bar 左侧或时钟旁提供可选的迷你波形 + 歌名胶囊，悬停展开控制浮窗（`popup`），点击跳转 Media 页。

### 5.2 音频混音器升级（替换 `wpctl`，直接用 `audio` 服务）
- **单应用音量控制（Per-App Mixer）**：`audio` 服务已原生提供 `apps` 列表（`{ id, name, icon, title, volume, muted, playing }`），可在 Audio 页增加各应用独立音量滑块与静音按钮。
- **输入设备（麦克风）切换**：利用 `audio.inputs` 与 `audio.default`（输入/输出），同步支持切换默认麦克风，而不只是输出设备。

### 5.3 网络（Wi-Fi）与蓝牙完整管理（原生 `network` / `bluetooth` 服务）
- 当前 `network` 只读了 `online/name`，`bluetooth` 只做了开关和连接数统计。
- 利用 `network.networks`（SSID、信号强度、加密状态、已保存/当前连接）与 `bluetooth.devices` + `bluetooth.pairing`（原生配对 PIN/确认码弹窗），在 Center Panel 中提供一键切换 Wi-Fi 和连接/配对蓝牙耳机设备的能力，减少打开外部网络/蓝牙管理器的频率。

### 5.4 原生 Polkit 认证弹窗（`polkit` 服务）
- `exp2` 原生提供 `polkit` 服务（`ready`, `pending`, `asking`, `message`, `action`, `icon`, `user`, `prompt`, `secret`, `info`, `error`）。
- 可直接做一个与 Notches 液态玻璃风格完全统一的权限认证弹窗（带密码输入框与震动错误反馈），替代 GTK/KDE 突兀的系统 polkit agent。

### 5.5 笔记本与顶部状态胶囊（`battery` / `brightness` / 勿扰与未读角标）
- **亮度控制**：利用 `brightness` 服务在 Quick Controls 或 Overview 中加入背光亮度滑块（台式机 `present == false` 时自动隐藏）。
- **Bar 轻量状态徽章（可单独开关）**：在 Bar 上为有电池的设备显示电量环、为有未读通知时显示小呼吸点、开启勿扰模式时显示静音图标，让顶栏信息密度按需可配。

### 5.6 Niri 工作区与窗口概览（`workspaces` / `window` / `thumbnails`）
- `exp2` 原生提供 `workspaces`、`window` 与 `thumbnails` 服务。
- 可在 Bar 左侧（或 Center Panel 新增/整合视图）增加轻量工作区圆点指示器，点击/滚轮切换工作区；并在 Launcher 的 `@` 窗口模式中直接接入原生 `window.list`（比每次敲字都 `sh -c 'niri msg --json windows'` 响应快得多），甚至在悬停窗口项时显示实时 `thumbnails` 缩略图预览。

### 5.7 Launcher 与通知中心体验增强
- **Launcher**：
  - 利用 `apps` 服务的 `actions` 字段，支持展开应用二级动作（如浏览器“新建无痕窗口”）。
  - 利用原生 `clipboard.image` 在 `^` 剪贴板模式中直接显示截图缩略图，而不是千篇一律的 `"Copied image"` 文字。
  - 利用原生 `terminal` 元素（`language 0.7`）或 `markdown` + `code_block` 在 `>` 命令模式中支持快捷内嵌输出/一键复制。
- **通知中心**：
  - 接入原生 `notification_history`（跨重启保留历史）并支持展示通知附带的 `image`（如聊天图片、专辑截图）与 `markdown: true` 富文本。
  - 在通知历史中支持单条删除、按应用折叠，以及通过 `popup` 交互。

### 5.8 锁屏增强（`lockscreen/`）
- 利用 `exp2` 的 `image 0, 0` + `fit: cover` 与独立字形图集，简化 `lockscreen.luau` 的两次 `magick` 预缩放流程，降低切换壁纸时的 CPU 峰值。
- 在锁屏支持中文日期/农历格式选项（与 Bar 和 Center Panel 保持一致），并在 `screens: each` 模式下完善多显示器表现。

---

## 6. 建议实施路线图

| 阶段 | 优先级 | 核心工作 | 预期收益 |
| --- | --- | --- | --- |
| **Phase 1：止血与清理** | **P0** | 1. 修复 6 个已确认 P0 Bug（`PanelBackdrop` 失效、内存历史 `pick` 错、Frame Music 按钮重叠、Audio Popup 写死坐标、Memory/Audio 圆环旋转、System 文字/进度条重叠）<br>2. 删除 4 套 `not notch_mode` 废弃 surface<br>3. 修复 `ct_time` 空转、Theme 页 82px 空洞与 Toast `margin` | 立即消除明显视觉/功能 Bug，场景指令与内存直接减半 |
| **Phase 2：引擎升级与架构瘦身** | **P1** | 1. `nix flake update pleamar` 升至 `0.8.0-exp.39` 并移除 `pleamar-shm-pool.patch`<br>2. 合并 `frame.plm` 4 套重复 `body`<br>3. 对 Settings/Center/Launcher 引入 `include … while` 懒加载<br>4. 用原生 `audio`/`clipboard`/`session`/`files` 服务替换外部 `sh`/`wpctl`/`wl-copy`，清理 2s 轮询<br>5. 评估以原生 `keyboard: … while` / `popup` 替代 `centerkeys`/`settingskeys` 辅助进程 | 大幅降低常驻内存与 CPU 唤醒；解决合成器模糊颈部断层和重启杀 App 问题；获得真实中文 IME 跟随 |
| **Phase 3：UI 与动画精修** | **P2** | 1. 接入 `--layout` 到 `tests/check.sh`，修复全部对比度/对齐告警<br>2. Settings/System/Tray 全面转向 `column`/`grid` + `inertia:` 滚动布局<br>3. 补齐 `pages` 切换动画、`ripple` 反馈、`motion.reduced` 与 `color.scheme` 支持<br>4. 统一中英文（`translations`） | 手感、动效与视觉完成度显著跃升，具备自动化 UI 回归防线 |
| **Phase 4：桌面能力扩展** | **P3** | 1. Media 专辑封面 + 进度条 + 多播放器<br>2. Audio 单应用混音 + 麦克风切换<br>3. Wi-Fi / 蓝牙配对 / Polkit 原生弹窗 / 工作区指示与剪贴板图片预览 | 成为真正自洽、不依赖杂散外部工具的完整 Wayland Shell |
