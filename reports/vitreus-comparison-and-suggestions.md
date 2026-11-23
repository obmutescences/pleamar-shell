# Vitreus 深度对标分析与 Pleamar-Shell 优化建议报告

> **对比基线**
> - 当前项目：`pleamar-shell`（分支 `feat/pleamar-0.8-exp`，提交 `835fcfc`，面向 **niri + NixOS + Notches 四边框**）
> - 参考项目：`/home/zerone/Downloads/Vitreus`（提交 `c0d04ad`，post-`v0.5.0`，面向 Hyprland/niri 的液态玻璃桌面套件）
> - 报告定位：只做全面分析与方案设计，**不修改代码**；所有建议均结合当前代码现状给出精确落点与优先级。

---

## 0. 总体定位差异与顺带发现的 4 处现存瑕疵

### 0.1 定位与取舍原则

`pleamar-shell` 的独特优势在于**克制、高内聚的 Notches 四边框形态**、**全套中文历法（农历/法定休班/倒计时）**、**独创水箱资源卡片（`modules/water/card.wgsl`）**以及已完整接入的 Pleamar `0.8.0-exp.41` 全量玻璃参数。

Vitreus 在最近多个版本的持续迭代中，已经从单纯的液态玻璃顶栏演进出一套极成熟的**视觉工艺体系（`pages/SETTINGS-STYLE.md`）**、**触觉级弹簧/着色器微动效**以及**高频系统实用能力**。借鉴应遵循以下原则：
1. **保特色**：保留四边框、水箱卡片、中文日历与 7-Tab 中心面板结构，不盲目照搬 Vitreus 的顶栏/独立抽屉拆分形态。
2. **吸工艺**：重点吸收 Vitreus 的 **Settings 设计规范、双边拉伸弹簧、WGSL 着色器工艺、控制中心/仪表盘交互密度与系统工具补齐**。
3. **做减法**：Hyprland 专属功能（hyprctl blur/gaps/SDDM）以及重型独立桌面应用（Files/View/Desk/Add-ons）明确列入不建议照搬清单，避免壳层膨胀。

### 0.2 审查期间顺带发现的 4 处现存瑕疵（建议优先顺手修复）

| # | 位置 | 现存问题 | 建议处理 |
|---|---|---|---|
| 1 | `modules/settings/panel.plm:796-799` | Wallpaper 页顶部 `"Random"` 按钮实则执行 `wall_transition = 1`（设置切图动画为随机），但文案仅写 `"Random"`，极易让用户误以为是“随机换一张壁纸”。 | 将该按钮改为**真正随机切换壁纸**（带骰子图标与旋转反馈），切图过渡方式另行放入过渡选择器。 |
| 2 | `modules/center/panel.plm:862-864, 894-896, 927-929` | System Tray 三个子卡硬编码 `glass: if(glass_on, 100%, 0%)`、`frost: glass_frost / 100`、`shine: pointer`，未接入新增的 `glass_mix`、`glass_frost_auto`、`glass_shine` 配置，且形成玻璃内嵌玻璃的重复采样。 | 改为与其他页面一致的 `veil + hairline` 半透明板，或统一绑定全量玻璃变量。 |
| 3 | `modules/center/panel.plm:278, 682, 735-737` | Overview / Audio / Media 的频谱柱均使用 `mod(b, 6)` 重复取 6 个粗频段（`band.s.0..5`），导致 28 根柱子呈周期性机械重复；而 `modules/notches/frame.plm` 已有完整 24 频段 `spec.s.0..23`。 | 中心面板直接改接真实 24 频段 `spec.s.0..23`（对称或全频展开），视觉观感立升一个档次。 |
| 4 | `modules/settings/panel.plm`（Glass/Bar 等页）& `modules/notches/frame_shapes.plm:8-18` | ① Glass/Bar 页在总开关关闭（如 `not glass_on`、`not glass_bend`、`glass_frost_auto`）时，从属滑块未置灰也未通过 `active:` 禁点。<br>② `frame_shapes.plm:8-18` 中 Settings/Centre/Search 抽屉与 6 个 bell 椭圆仅用 `show:` 隐藏而未移出屏外（对比第 20 行 Notification drawer 有 `+ if(..., 0, 30000)`）；Vitreus `bar_shapes.plm:23-25` 特别警示 `show:` **不会把 shape 从 `body` 的 SDF 评估循环中移除**。 | ① 给从属控件组统一套 `opacity: if(enabled, 100%, 35%)` 与 `active: enabled`。<br>② 对未激活的抽屉/bell 补齐移出屏外处理，并评估在 `frame_music == false` 时将四边 192 根音乐柱子隔离出主 `body` SDF 以降低集显空载开销。 |

---

## 一、功能添加建议（Feature Additions）

按“用户体感提升 / 实现成本 / 与 niri+NixOS 契合度”分为三档：

### 1.1 P0：高价值、高契合度的系统级刚需功能

#### 1) 每应用独立音量混音器（Per-App Audio Mixer）
- **参考**：`Vitreus/pages/controls_drawer.plm:115-127`（`MixRow`）
- **现状痛点**：我方 Audio 页（`modules/center/panel.plm`）只控制总输出音量与麦克风，调整浏览器/播放器/会议软件的单独音量仍需打开 `pavucontrol`。
- **落地方案**：在 Luau 侧复用 `pactl list sink-inputs` / `pactl subscribe` 事件流暴露 `audio_apps` 模型（应用名、图标、音量 `0..1`、静音态、节点 ID），支持滑块拖调与单击静音；直接嵌入中心面板 **05 Audio** 页右侧下方（详见第四节）。

#### 2) 轻量级玻璃 OSD 浮层（音量 / 亮度 / 锁定键 / 键盘布局 / 截图预览）
- **参考**：`Vitreus/pages/osd_drawer.plm`、`Vitreus/logic/lockkeys.luau`
- **现状痛点**：快捷键调节音量、屏幕亮度，或按下 CapsLock / NumLock / 切换输入法时，屏幕没有统一玻璃风格的即时视觉反馈。
- **落地方案**：
  - 新增一个独立轻窗或 Notch 下沿小药丸 OSD：音量/亮度采用水平液态进度条+百分比，CapsLock/NumLock/布局切换用短暂弹出的胶囊徽章（1.2s 自动收回）。
  - **高光加分项**：截图完成后弹出带缩略图的小型 OSD 卡片（`osd_drawer.plm:161-197`），提供“打开 / 复制 / **OCR 文字识别复制**（调用 `tesseract` + `wl-copy`）”按钮，并允许直接拖拽缩略图到应用窗口。

#### 3) Caffeine 防息屏定时器（与 `pleamar-idle` 深度联动）
- **参考**：`Vitreus/pages/controls_drawer.plm:371-446, 848-950`
- **现状痛点**：看长视频、演示或跑编译任务时，临时阻止自动锁屏/息屏只能去设置页改 Idle 时间为 Never，用完还容易忘改回来。
- **落地方案**：在中心面板 Overview / Actions 增加 Caffeine 开关与快速时长档位（`15m / 30m / 1h / 2h / 4h / ∞`），开启时调用 `systemd-inhibit --what=idle` 或与现有 `pleamar-idle` 守护进程同步抑制状态，并在顶栏 Clock Notch 边缘亮起一颗克制的暖色小图标/倒计时微环。

#### 4) 夜间护眼模式（Night Mode：色温 + 定时）
- **参考**：`Vitreus/pages/nightmode.plm`、`Vitreus/logic/nightmode.luau`
- **现状痛点**：缺少桌面原生的蓝光色温调节与日落定时切换。
- **落地方案**：niri 下对接 `wlsunset` 或 `gammastep`（NixOS 可直接封装进 flake 运行时依赖）；在设置页与 Actions 页提供 `6500K – 2500K` 带色温渐变轨道的滑块，以及“手动开关 / 日落日出或自定义时段自动开启”。

#### 5) 通知精细化控制（24h 静音时段轨道 + 全屏自动免打扰 + 分应用规则）
- **参考**：`Vitreus/pages/notifications.plm`
- **现状痛点**：当前通知系统只有全局 DND 开关、超时、最大条数与位置，缺乏场景感知能力。
- **落地方案**：
  - **24h 静音时段可视化拖拽轨道**：支持跨午夜（如 `23:00 → 07:30`）、实时当前时间红/主色竖线、两端手柄防重叠自动避让标签。
  - **全屏自动静音（Fullscreen Mute）**：监听 `niri msg -j event-stream` 的窗口全屏状态，游戏/视频/演示全屏时自动静默非关键通知（`critical` 紧急通知可放行）。
  - **分应用通知规则**：按 `app_name` 配置 `Mute（彻底屏蔽）/ Silent（只入中心不弹窗）/ Bypass DND（穿透免打扰）/ 自定义超时`。
  - **通知尺寸档位（S / M / L）**：适配高分屏与不同信息密度偏好。

---

### 1.2 P1：进阶实用功能（显著提升日常顺手度）

#### 6) 截图 / 录屏中心 + 最近截图缩略图原生拖拽（`carries:`）
- **参考**：`Vitreus/pages/controls_drawer.plm:954-1033`、`Vitreus/logic/capture_recent.luau`
- **落地方案**：在 Actions 页设置 Capture 卡片：区域/全屏截图（`grim` + `slurp`）、区域/全屏录屏（`wf-recorder` / `gpu-screen-recorder`，带系统音/麦克风开关与顶栏脉冲红点计时）；下方展示最近 4 张截图缩略图，**利用 Pleamar 原生 `carries:` 拖拽能力**，无需打开文件管理器即可直接把刚截的图拖进微信/浏览器/文档。

#### 7) 电源档位（Power Profiles）+ 电池健康与充电阈值卡片
- **参考**：`Vitreus/pages/controls_drawer.plm:1173-1201`、`Vitreus/pages/battery_card.plm`
- **落地方案**：
  - 3 档弹簧滑槽（`Saver / Balanced / Performance`，对接 `powerprofilesctl`）。
  - 若检测到笔记本电池：显示电池健康度（`energy_full / energy_full_design`）、循环次数、实时瓦数与预计剩余时间、充电上限阈值切换（如 80% 养护 / 100% 充满，通过 sysfs `charge_control_end_threshold`），以及通过 UPower 展示已连接蓝牙耳机/鼠标/键盘电量。

#### 8) 隐私状态指示灯（麦克风 / 摄像头 / 投屏共享）
- **参考**：`Vitreus/logic/privacy.luau`
- **亮点**：基于 `pactl subscribe` + PipeWire source-outputs + USB 摄像头 `power/runtime_status`，**事件驱动几乎零轮询开销**。
- **落地方案**：在顶栏 Clock Notch 左侧或右侧边缘用 3 颗微型呼吸圆点（红=录屏、橙=麦克风、绿=摄像头）提示，悬停浮出正在占用设备的应用名。

#### 9) Game Mode（niri 一键低延迟 / 游戏模式）
- **参考**：`Vitreus/logic/gamemode.luau`
- **落地方案**：针对 niri 定制一键开关：临时关闭 `frame_music` 与频谱采样、开启 DND、切至 `Performance` 电源档位、降低或关闭玻璃折射与动画；将原始状态持久化至状态文件，确保异常退出或重启后自动恢复原配置。

#### 10) 壁纸体验全面升级
- **参考**：`Vitreus/pages/wallpaper.plm`
- **落地方案**：
  - 修复真随机切换壁纸按钮 + 旋转骰子动效；
  - 缓存每张壁纸的主色调，提供 **12 色系色块筛选栏**，快速按心情找同色系壁纸；
  - 显示当前壁纸目录并支持快速切换目录、删除壁纸带 **10 秒 Undo 撤销条**；
  - （可选）接入 Wallhaven API 在线关键词搜索与一键下载应用。

#### 11) 快捷键可视化面板与录制器（Keybinds，适配 niri）
- **参考**：`Vitreus/pages/keybinds.plm`
- **落地方案**：解析 niri 配置文件（`config.kdl`）中的 `binds {}` 块，以物理键帽样式分组展示并支持实时搜索；进阶版支持在 UI 内“点击录制组合键”写回独立 include 文件并热重载 niri。

#### 12) Live Bend 性能分级与空闲休眠
- **参考**：`Vitreus/pages/glass.plm:151-196, 303-330`
- **落地方案**：在 Glass 设置页为“边缘折射”提供两档模式（**X-Bend 静态壁纸折射** vs **Live Bend 实时桌面抓屏折射**），并提供刷新间隔（ms）与无操作自动降频休眠开关，在笔记本离电或高刷屏下大幅省电。

---

### 1.3 明确不建议照搬的功能（保持项目精炼）

| Vitreus 模块 | 不建议照搬的原因 |
|---|---|
| Hyprland 模糊 / 窗口间隙 / 动画设置 | 我方运行在 niri，底层合成器机制完全不同，强行对齐徒增维护负担。 |
| 独立应用套件（Files 文件管理器 / View 看图器 / Desk 桌面挂件 / Add-ons 插件市场） | 此前已明确不做桌面扩展与重型独立应用；维持 Shell 的轻快高内聚定位更符合 NixOS + niri 使用哲学。 |
| SDDM 登录主题生成器 | NixOS 通常由 declaratively 配置 greeter（greetd/tuigreet/ly/gdm），在运行时由 shell 改写系统 SDDM 目录与 NixOS 只读 store 理念冲突。 |

---

## 二、UI 与动画改进优化（UI, Shaders & Motion）

### 2.1 双前导/滞后边“果冻拉伸”动效（Leading / Trailing Edge Stretch）
- **Vitreus 做法**：在 `SetPick`（`vitreus.plm:4369-4381`）、`PSlider`（`vitreus.plm:4198-4215`）及侧边栏高亮块（`settings_panel.plm:118-130`）中，**不用单个弹簧平推位置，而是用快慢两个弹簧分别驱动目标区间的前沿（`ld`，约 76ms）和后沿（`tl`，约 238ms）**：
  - 移动启动瞬间，前沿抢先出发、后沿尚在原地，滑块/药丸自动沿运动方向拉长并略微变细（体积守恒感）；
  - 抵达终点时，后沿快速追上并略微过冲收敛，带来真实的液态惯性与弹性。
- **我方现状**：`cp_nav`（设置侧边栏）、`ct_tab`（中心面板顶栏）、`CpSlider`/`CtSlider` 目前均为单弹簧平移（`~quick`），运动过程刚性较强。
- **改进**：优先将这套双边滞后算法封装为通用模式，应用于 **Settings 侧边栏指示块、Center Panel 7-Tab 胶囊、所有 `SetPick` 分段选择器、以及滑块旋钮**。

### 2.2 分段挤压轨道滑块（`PSlider` + `PPinchSeg`）+ GPU 着色器填充
- **Vitreus 做法**（`vitreus.plm:4192-4291`、`fillstyle.wgsl`）：
  - 滑块轨道在旋钮处**断开成左右两段独立的圆角胶囊**（左段为填充色、右段为暗轨道），中间留出呼吸间隙，旋钮是一根垂直圆角细条；拖动速度越快，旋钮横向拉长、纵向微压。
  - 手绘斜线（Pencil）/ 马克笔（Marker）/ 渐变（Gradient）/ 波点（Dots）等笔触纹理全部交由 **单个 WGSL 着色器 `fillstyle.wgsl`** 在 GPU 一次性绘制。
- **我方现状与性能收益**：
  - `CpSlider`（`modules/settings/panel.plm:37-44`）与 `CtSlider`（`modules/center/panel.plm:45-52`）每个滑块都用 `repeat i in 0..40` + `0..20`（共 **60~66 条独立 CPU 矢量线段**）模拟铅笔阴影。Glass 页单页近 10 个滑块就生成了 **600+ 条线段图元**！
  - 升级为 **分段挤压轨道 + `fillstyle.wgsl` 单矩形着色器** 后，既获得了 Vitreus 最具辨识度的“断轨手绘挤压感”，又将每个滑块的渲染图元数从 ~70 降至 ~5，且天然支持切换填充质感风格。

### 2.3 顶栏指针磁吸微凸（`bar_bulge`）与音乐低音脉动（`bar_beat`）
- **Vitreus 做法**：`pages/bar_shapes.plm:77-83` + `logic/bar_bulge.luau` + `logic/bar_beat.luau`。在玻璃 `body` 中增加一个极轻量的跟随鼠标 X 坐标的小 `box`，通过 `blend: 12 * bu * bg_hot` 融进主边缘，鼠标滑过顶栏或 Clock Notch 边缘时，液态玻璃会像水银表面一样产生细腻的磁吸隆起；播放音乐时根据低音能量让 Notch 产生克制的低频呼吸膨胀。
- **改造建议**：特别适合我们现有的 **Notches Clock 药丸下沿与四边框内沿**！只需 1 个跟随指针的融合形状即可显著强化液态玻璃的生命力（并在设置里留开关，默认柔和档）。
- **性能铁律**：严格遵循 `bar_shapes.plm:23-25` 经验——不触发时把融合形状移至屏外或归零，避免任何多余的 SDF 相交计算。

### 2.4 卡片液态形变展开与共享元素转场（`cardmorph.wgsl` + `tg.*`）
- **Vitreus 做法**：`pages/controls_drawer.plm:608-657` + `vitreus.plm:6174-6196` + `cardmorph.wgsl`。
  - 点击功能瓷砖展开详情时，卡片宽度（`tgx: 280, 26`）先于高度（`tgrow: 150, 17`）响应，先横向舒展再纵向流下；
  - 运动期间由 `cardmorph.wgsl` 根据位移速度对卡片轮廓施加微妙的多瓣液态波动，静止时平滑退化为绝对锐利的标准圆角矩形；
  - 原瓷砖的**图标与标题不消失**，而是作为共享元素（Hero Transition）从瓷砖坐标平滑飞跃缩放至详情页标题栏。
- **适用场景**：中心面板 **07 Actions** 瓷砖展开（蓝牙设备列表、Wi-Fi、Capture、Caffeine、Power）、以及未来通知卡片点击原地展开正文。

### 2.5 值得引入的高质感 WGSL 着色器矩阵

| Vitreus 着色器 | 视觉效果 | 在 `pleamar-shell` 的最佳落点 |
|---|---|---|
| `sky.wgsl` | 程序化实景天空：太阳弧线轨迹、真实月相、闪烁星空、风速驱动双层云与受光边缘、雨雪视差、雾带、闪电 + 自动文字对比度保护 | 中心面板 **01 Overview 天气卡背景**（直接替代纯色底板） |
| `liquid.wgsl` | 跟随指针的 3D 透视倾斜 + 表面柔光聚光灯 + 悬停对角高光扫光 | Settings **壁纸缩略图卡片**、Overview 水箱卡/重点磁贴 |
| `leader.wgsl` | 带细微手绘噪点与回声的水平点状引导线，悬停目标控件时点亮为主色 | Settings **所有单行配置项**（连接左侧标题与右侧控件） |
| `fillstyle.wgsl` | GPU 零线段开销的铅笔斜线/马克笔/波点/渐变填充 | `CpSlider`、`CtSlider`、`SetPick` 选中块 |
| `cardrip.wgsl` / `underwater.wgsl` | 从点击坐标向外扩散的液面边缘波纹 / 面板浮出时的轻度水下折射显影 | 中心面板切页 / 瓷砖点击涟漪，与现有 `water/card.wgsl` 形成统一的水感品牌语言 |

### 2.6 语义化弹簧阶梯与交错入场（Stagger）
- **Vitreus 弹簧分级**（`vitreus.plm:14-18, 1313-1326`）：按物理意图细分快慢与阻尼——`drip`（重液滴回弹）、`dripl`（较长惯性）、`tgx`/`tgrow`（宽快高慢形变）、`pop`（轻快微过冲弹跳）、`splash`（强反馈冲击）、`spike`/`beat`（音频响应）。
- **改进建议**：
  1. 在 `modules/common/motion.plm` 中补充语义弹簧表（如 `snappy`、`bouncy`、`morph_w`、`morph_h`、`trail`），避免全项目混用 `quick` 与 `gentle`；
  2. 列表页（Font 列表、Keybinds、System 进程、Overview 多张 Bento 卡片）打开时根据面板进度增加 **15~25ms 交错入场偏移**，大标题或切换页眉尝试 Pleamar 原生 `letter_move` / `letter_opacity` 逐字微入场；
  3. **触觉微动效升级**：
     - 开关按压时增加 `press` 压缩态（旋钮展宽 `7px`、压扁 `2px`），松手过冲回弹；
     - 瓷砖切换时从开关圆心径向漫出整个卡片的填充色（`wf_fill`）并伴随触点扩散涟漪（`wf_rip`）；
     - 危险操作（关机/重启/注销）提供**“1 秒长按充能 + 渐强高频微震 + 倒计时 + 触发粒子爆碎（`particles`）”**交互，兼顾防误触与极高爽感；
     - 跑马灯/长文本滚动使用 `floor(off + 0.5)` 像素取整，避免亚像素抖动发糊。

---

## 三、设置界面（Settings）专项 UI 与动效借鉴

对照 `Vitreus/pages/SETTINGS-STYLE.md`、`pages/settings_panel.plm` 及各子页，逐项诊断我方 `modules/settings/panel.plm`（共 1325 行），给出可直接照单改造的专项清单。

### 3.1 控件语法规范化：告别“万物皆散装 `CpPill`”
- **现状问题**：`modules/settings/panel.plm` 将 `CpPill` 同时用于**操作按钮**（Save / Apply / Refresh / Test）和**多选单选项**（Coverage、Columns、Toast position、12/24h、Clock size、Date format、Password mask、Mask colour、Material presets、Gradient shape、Animation effects），页面充斥着大量零散圆角框，视觉噪音高且无法一眼区分“按钮”与“当前选中的枚举值”。
- **借鉴 `SETTINGS-STYLE.md` 铁律**：
  1. **Pill 只留给动词操作**（Save / Refresh / Test / Reset / Open folder）。
  2. **2–6 项命名单选统一改为 `SetPick` 滑槽选择器**（`vitreus.plm:4368-4397`）：外层为统一高度（32px）的槽轨，所有同类选择器**严格右对齐卡片内右边线**；内部选中胶囊采用双边滞后拉伸动效，悬停未选项给 `7%` 柔和底色。
  3. **纯视觉差异的枚举项升级为“微型可视化预览瓷砖（Picture Tiles）”**（借鉴 `pages/bar.plm`、`pages/clock.plm`、`pages/style.plm`）：例如 Gradient shape（None / Radial / Linear / Sweep）、Notification position（四角微型屏幕示意图，高亮对应角落）、Clock size、Line/Fill Style，用户看图即懂，减少阅读英文标签负担。

### 3.2 引导虚线 `PLeader` + 严格单行滑块基线重构（最立竿见影的质感飞跃）
- **现状痛点**：我方每个滑块卡片（`CpCard` 高 62px）把标题放在 `y+10`、副标题放在 `y+28`，滑块却被迫放在右下角 `y+47`（`x=520..720`），数值左对齐放在 `x=730`：导致**滑块和主标题不在同一水平线上，反而与左下角副标题挤压错位**，整体显得松散杂乱。
- **借鉴 `SETTINGS-STYLE.md` 单行法则**：
  - **严格同基线**：主标签（左对齐）`—— 引导虚线 PLeader ——` 滑块（同页所有滑块统一左边缘，视觉成列）`——` 数值（右对齐、加粗、主色显示）。
  - **副标题独立成行**：简短解释文字单独置于整行正下方（淡色小字），绝不与滑块争抢水平空间。
  - **动态测量 + 悬停联动**：利用 Pleamar `measure:` 自动测量左侧文字实际宽度，由 `PLeader`（`leader.wgsl`）精准填补“文字右端 → 控件左端”之间的空隙；**鼠标悬停到滑块/开关/选择器时，对应引导虚线立即亮为主色**，视线导引极度舒适。

```text
【现状：错位挤压】
┌──────────────────────────────────────────────────────────┐
│ Background opacity                                       │
│ Tint depth behind the glass                              │
│                                  [======o------]  65%    │
└──────────────────────────────────────────────────────────┘

【借鉴 Vitreus 改造后：基线对齐 + PLeader 虚线导引】
┌──────────────────────────────────────────────────────────┐
│ Background opacity  ············  [====== | ----]   65%  │
│ Tint depth behind the glass                              │
└──────────────────────────────────────────────────────────┘
```

### 3.3 间距韵律、卡片可读性与内部结构清理
- **分组标题外置卡片之上**：借鉴 Vitreus 规范，分组大类标题（如 `SURFACE`、`OPTICS`、`REFRACTION`）使用 13–14px Faint Bold 大写，固定位于卡片上方 12px 处，不再挤在卡片之间或缩成 9px 小字。
- **卡片暗底衬（`card_fill`）**：当前 `CpCard`（`panel.plm:97-100`）仅绘制 `ink 3%` 浅色罩层 + `ink 9%` 描边，在浅色或高通透壁纸下卡片几乎“隐身”发灰；借鉴 Vitreus 在高透玻璃下叠加一层柔和暗底衬（如 `mix(card, #000, ...)` 或随亮度自适应），显著增强层次与文字对比度。
- **统一节奏**：卡片内边距固定 `14px`，卡间与行间统一 `8px` 节奏。
- **代码债清理**：
  - 修复侧边栏 `settings_page` 编号与视觉顺序完全乱序的问题（当前 `pick(settings_page, 6, 2, 5, 7, 1, 9, 8, 11, 12, 14, 3)` 极易在增减页面时出错）；
  - 为所有导航项和选择器补全无障碍 `role: tab / option` 与 `selected:` 属性。

### 3.4 头部徽章与侧边栏动效升级
- **头部齿轮徽章棘轮动效**（`pages/settings_panel.plm`）：
  - 打开设置面板时，头部徽章顺时针旋转半圈弹入；
  - **每次切换侧边栏页面，齿轮以带过冲的弹簧棘轮式顺时针转动一齿（`+45°`）**，小巧却极富机械精致感；
  - 面包屑路径 `Settings › Category › Page` 切换时做轻柔水平微滑过渡。
- **侧边栏双边滞后指示块 + 组分隔线点亮**：
  - 放弃当前 `cp_nav ~quick` 单弹簧平推；改用 `sb_ld`（~76ms）+ `sb_tl`（~238ms）驱动侧边栏选中块，跨多页跳转时指示条先竖向拉长收窄、落位后回弹舒展；
  - 每个分组标题（`APPEARANCE` / `SURFACE` / `SYSTEM` 等）右侧画一根水平细线，当该组内任意页面激活时，细线平滑过渡为主色点亮；
  - 为侧边栏自身套上 `column` 滚动容器，避免后续新增 Night Mode / Keybinds / Power 等设置页后底部溢出。

### 3.5 长页面的滚动引导与可拖拽滚动条
- **现状痛点**：Glass / Bar 页刚加上 `column` 滚动和 3px 细指示条，但初次打开无法一眼看出下方还有更多项，且 3px 指示条只能看不能拖。
- **借鉴 `Vitreus/pages/bar.plm:314-334`**：
  1. 视口底部未滚到底时叠加 **16 阶柔和渐隐遮罩**；
  2. 底部居中悬浮一枚缓慢上下呼吸的 **`"More ⌄"` 玻璃胶囊**（点击平滑下滚一屏，滚动到底自动淡出隐藏）；
  3. 滚动条改为 `14px` 宽热区、默认 3px 悬停展宽至 6px、**支持鼠标点击跳转与按住拖拽滚动**。

### 3.6 重点设置子页的专项体验改造

| 设置子页 | Vitreus 可直接借鉴的交互亮点 | 改造说明 |
|---|---|---|
| **Glass 页** | `pages/glass.plm` | ① 顶部或侧边增加**实时材质交互预览卡**（调 Frosted / Refractive / Tinted / Tint / Edge 时即时观察玻璃边缘色散与通透感）；<br>② Opacity 滑块前 20% 禁用区画半透明斜纹暗区 + 刻度起始线；<br>③ 当 `not glass_on`、`not glass_bend` 或 `glass_frost_auto` 时，自动将从属行淡化至 35% 并禁用 `active:`；<br>④ 新增“填充风格（Pencil / Marker / Plain / Gradient）”选项，驱动全局滑块与选择器。 |
| **Lock Screen 页** | `pages/lockscreen.plm:34-118` | 顶部加入 **实时密码输入体验槽（`Example bar`）**：切换 Password mask（圆点/星号/条纹）或 Mask colour 时，直接点击输入槽打字即可实时预览动画与配色，**不用真的锁屏测试**。 |
| **Idle 页** | `pages/idle.plm:19-51` | 顶部加入 **三阶段时间轴可视化卡片（`ACTIVE → LOCK → SCREEN OFF`）**：启用的阶段高亮发光并标出分钟数，设为 Never 的阶段变暗虚线；离散时间滑块下方绘制对齐的刻度圆点。 |
| **Wallpaper 页** | `pages/wallpaper.plm` | ① 修复 `"Random"` 为真随机切壁纸并配旋转骰子图标；<br>② 缩略图卡片引入 `liquid.wgsl` 悬停 3D 微倾与对角扫光；<br>③ 顶部加入 12 色系筛选条、壁纸目录路径显示与删除 10s 撤销条。 |
| **Font / Theme 页** | `pages/theme.plm` | 为字体列表增加真实字形预览句（包含中英文与数字 `0123456789`），并展示当前壁纸提取出的动态色板（Primary / Secondary / Tertiary / Surface 色块）。 |
| **Notifications 页** | `pages/notifications.plm` | 加入 24h 静音时段拖拽轨、全屏自动静音开关、S/M/L 尺寸预览切换，以及可展开的分应用通知规则表。 |

---

## 四、中心面板（Center Panel）优化建议

针对 `modules/center/panel.plm`（1120×720，7 个 Tab：Overview / System / Tray / Media / Audio / Calendar / Actions），结合 Vitreus 的 `dashboard.plm`、`controls_drawer.plm`、`media_float.plm` 进行逐页精细优化。

### 4.1 全局框架与切页动效
1. **双边拉伸 Tab 滑块**：将顶栏 7 个 Tab 的选中高亮从单弹簧改造成 `SetPick` 式双边滞后拉伸胶囊，跨 Tab 跳转极具弹性。
2. **方向感知的切页转场**：记录上一次 `prev_tab`，往右切页时新页面从右侧 `+18px` 轻柔滑入，往左切页时从左侧 `-18px` 滑入（替代目前所有方向都向下移 `8px` 的单一过渡）。
3. **顶栏精致度升级**：借鉴 `dashboard.plm` 的时钟区，在左上大时间下方加一条 **60 格细腻秒刻度微条**（当前秒高亮）；将顶栏右上常驻的 `1–7 TABS` 提示改得更克制（或悬停 Tab 区时淡现）。

### 4.2 `01 Overview`（概览页）—— 打造“第一屏高密度实景仪表盘”
1. **天气卡片视觉飞跃（接入 `sky.wgsl` + 24h 交互温度曲线）**：
   - 保留现有的中文城市名、体感温度、湿度与风速信息；
   - 将静态深色卡片背景升级为 **简化版 `sky.wgsl` 实时天气天空**（晴天太阳/夜晚星空月相/多云流动/雨雪粒子）；
   - 将当前 6 个静态小时文字格升级为 **24 小时平滑贝塞尔温度曲线 + 降水概率底柱**，鼠标滑过曲线任意位置实时显示该整点温度与天气；鼠标悬停下方未来 4 天某一天时，天空背景实时预览当天的天气状况！
2. **高频快捷控制前移（减少频繁切到 07 Actions）**：
   - 现状 Overview 右侧虽有媒体简控和最近通知，但没有亮度/音量/DND/Caffeine 入口，调节硬件必须切去 Audio 或 Actions。
   - 借鉴 `dashboard.plm` 左侧的垂直玻璃推子（`DshPinch`），在 Overview 布局中腾出一条紧凑控制列：放**亮度 + 音量 2 条垂直液态挤压推子**以及 **DND / Caffeine / Night Mode 3 颗微胶囊开关**，让 80% 的日常操作在第一屏一步完成。
3. **水箱资源卡片（`ct_water`）交互深化**：
   - 保留我方最具辨识度的 CPU / MEM / GPU / Storage 液面水箱，但增加 `liquid.wgsl` 轻度悬停高光，并支持**单击任意水箱卡片直接跳转至 `02 System` 页并高亮对应指标区块**。
4. **Recent Alerts 卡片交互化**：
   - 借鉴 `dashboard.plm` 通知卡：支持每条通知**右滑/点 `×` 单条清除**、点击单条在卡内原地展开完整正文（不再强迫跳转到通知中心）。

### 4.3 `02 System`（系统监控页）
1. **告别字符折线图，改用原生矢量曲线**：
   - 当前 CPU / 内存 / 网络 60s 历史图是通过等宽字体拼接 Unicode 方块字符（`sys_cpu_hist`、`sys_rx_spark`）绘制的，锯齿明显且与液态玻璃风格违和。
   - 改为 Pleamar 原生 `path` 折线/平滑曲线 + 下方半透明渐变填充 + 鼠标悬停显示该时刻具体数值。
2. **进程列表可操作化**：
   - 表头支持点击按 `CPU%` / `MEM%` 切换排序；每行悬停右侧淡现轻量的“终止进程（需二次微确认）”按钮。

### 4.4 `03 System Tray`（系统托盘页）
1. **修复玻璃嵌套割裂感**：修复 `panel.plm:862-864, 894-896, 927-929` 三栏硬编码 `glass: 100%` / `shine: pointer` 问题，统一改为半透明 `veil` + 1px `hairline` 卡片，避免外层玻璃与内层玻璃双重折射发糊。
2. **展开与过渡动画**：中栏（Actions）和右栏（Submenu）在切到新应用或展开子菜单时增加 `12px` 水平平滑展开与淡入过渡，并为长列表补上与 Settings 同款的可视滚动条。

### 4.5 `04 Media`（媒体页）—— 从占位黑胶升级为“旗舰级音乐展台”
- **现状短板明显**（`modules/center/panel.plm:700-759`）：左侧黑胶唱片只有空心圆环和 `♪` 占位符，**无专辑封面**；右侧**没有播放进度条（无法拖拽 Seek）**；频谱只是 6 频段 `mod(b, 6)` 循环重复。
- **全面重构方案**（借鉴 `dashboard.plm:606-868` & `media_float.plm`）：
  1. **真实封面黑胶 / 唱片盘**：在旋转黑胶中心（半径 ~76px）裁剪贴入真实 MPRIS 专辑封面 `med.art`（无封面时优雅回退至现有矢量唱片），外圈叠加受低音能量驱动的柔和色晕呼吸环，暂停时黑胶以弹簧平滑减速停转而非硬卡停。
  2. **48 柱对称径向 / 真实 24 频段频谱**：接入 `spec.s.0..23`，在唱片外缘或右侧展示真实细腻的音乐频谱，彻底消除 `mod(b, 6)` 机械感。
  3. **可拖拽 Seek 进度条 + 直播态识别**：加入 `PSlider` 风格分段挤压进度条（显示已播时间 / 总时长，拖动实时下发 MPRIS `SetPosition`）；当媒体为无时长直播流时，自动切换为缓慢呼吸的 `LIVE` 波形指示条。
  4. **切歌微反馈**：曲目变化瞬间唱片轻微弹跳（`scale` 过冲）并在边缘迸发微量主色火花粒子。
  5. **进阶惊喜（可选）**：卡片右上角加一颗“悬浮窗”按钮，借鉴 `media_float.plm` **拖出一个可自由拖拽位置、可调大小的桌面迷你 Walkman 悬浮播放器**（带峰值保持 LED VU 表与边缘滚轮调音）。

### 4.6 `05 Audio`（音频页）
1. **充分利用大画幅空间，引入 Per-App Mixer**：当前 1120×720 面板里 Audio 页仅放了左大圆环和右侧 2 条滑块，下方大面积留白。在右侧下方直接落地 **PipeWire 每应用独立混音列表**（滚动容器，每行含应用图标、名称、静音钮、`PSlider` 独立音量条），让 Audio 页真正具备桌面级实用价值。
2. **左大旋钮环支持直接交互**：当前左侧大体积圆环只是纯展示，建议加上鼠标滚轮调节与沿圆弧拖拽调节音量，拖动时圆环光晕随音量增强。
3. **输出/输入设备内联平滑展开**：将设备切换做成类似 Vitreus `controls_drawer.plm` 的内联折叠列表，替代突兀的遮罩层。

### 4.7 `06 Calendar`（日历页）
1. **保留核心壁垒**：完整保留农历、节气、中国法定节假日“休/班”角标与纪念日倒计时。
2. **补齐交互闭环**（借鉴 Vitreus Calendar + Dashboard Reminders）：
   - 点击任意日期，右侧详情区切换展示该日农历宜忌/节假日 + **当日提醒事项**；
   - 支持底部一行快速输入框添加本地轻量提醒（支持自然语言时间解析如 `"15:30 项目评审"`），今日未完成提醒同步显示在 **01 Overview** 页并支持一键勾选划除；
   - 切换上/下月时，日历网格执行方向感知的左右微滑动画。

### 4.8 `07 Actions`（快捷操作与会话页）—— 向“控制中心”进化
1. **原地液态展开瓷砖（`cardmorph.wgsl`）**：
   - 现状中蓝牙按钮只是一个盲开关、无法选设备；Actions 页 4 个 Surface 按钮 + 少数开关略显单薄。
   - 借鉴 `controls_drawer.plm` 升级为 **6~8 宫格动态瓷砖**（`Wi-Fi`、`Bluetooth`、`DND`、`Caffeine`、`Capture`、`Night Mode`、`Game Mode`、`Power Profile`）：
     - 短按左侧开关图标立即切换状态（伴随开关挤压 + 从圆心漫出的径向填色 `wf_fill`）；
     - 点击瓷砖右侧区域，瓷砖通过 `cardmorph.wgsl` 液态形变展开为详情面板（蓝牙设备配对/连接列表、Wi-Fi 列表与长按信号强度表、DND/Caffeine 定时档位条、Capture 截图录屏与最近 4 张可拖拽缩略图）。
2. **Session 危险操作升级为“长按充能确认”**：
   - 保留 Lock / Suspend 的单击即触发；
   - 将 Logout / Reboot / Shutdown 升级为 **按住 1 秒液态充能 + 渐强高频微震 + 居中倒计时 + 满槽粒子爆裂触发**（松手随时取消，零全屏黑幕弹窗打断感，同时可选在设置中回切传统弹窗确认）。

---

## 五、建议的分阶段落地路线图

为避免一次性改动面过大导致回归风险，建议按三阶段推进（每个阶段均可独立验收、独立提交）：

### Phase 1：快赢修缮 + Settings 底座升级（预计工作量小，体感提升最大）
- 修复 0.2 节列出的 **4 处现存瑕疵**（Wallpaper 真随机、Tray 玻璃统一、中心面板 24 频段真实频谱、Settings 依赖置灰与 `frame_shapes.plm` 屏外移出）。
- 引入 `SetPick` 双边拉伸选择器、`PLeader`（`leader.wgsl`）引导虚线、GPU 版 `PSlider`（`fillstyle.wgsl`）。
- 重构 Settings 布局规范（单行滑块基线、组标题外置、暗底衬、齿轮棘轮旋转、侧边栏双边弹性滑块、长页 `"More ⌄"` 与可拖拽滚动条），并加上 **Lock Screen 实时输入体验槽** 与 **Idle 流程卡**。

### Phase 2：中心面板全面焕新 + 核心系统刚需补齐
- **Media 页升级**：真实专辑封面黑胶 + 可拖拽 Seek 进度条 + 24 频段真实频谱。
- **Audio 页升级**：PipeWire 每应用独立混音器（`MixRow`）+ 大环滚轮调音。
- **Overview 页升级**：集成 `sky.wgsl` 动态天气背景 + 24h 贝塞尔温度曲线 + 左侧垂直音量/亮度快捷推子 + Recent Alerts 单条清除/展开。
- 新增 **轻量级玻璃 OSD**（音量/亮度/CapsLock/键盘布局）、**Caffeine 防息屏定时**、**Night Mode 护眼色温**。

### Phase 3：标志性交互工艺与进阶能力（按需挑拣）
- **Actions 页液态形变卡片**（`cardmorph.wgsl`）：蓝牙/Wi-Fi 原地展开、Capture 录屏截图 + 最近 4 张 `carries:` 拖拽缩略图 + 截图 OSD OCR、Session 长按震动爆碎确认。
- **顶栏微生命力**：Clock Notch 指针磁吸微凸（`bar_bulge`）+ 隐私指示灯（麦克风/摄像头/投屏）。
- **高级系统工具**：通知 24h 静音时段轨 + 全屏自动静音 + 分应用规则、Power Profile + 电池健康/充电阈值、niri Game Mode、Wallpaper 12 色筛选、日历本地快速提醒、Keybinds 面板与桌面悬浮 `MediaFloat` 迷你播放器。
