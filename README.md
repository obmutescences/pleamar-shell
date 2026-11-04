# pleamar-shell

从零重做一个 pleamar shell：Frame + Island 两种布局，四周有音乐特效，保留液态玻璃的观感，2560×1440@180 下切工作区 ≥120fps。

## 需求

- 显示器 2560×1440@180Hz（DP-1），GPU RX 6500 XT（RADV）。
- 布局：Island（顶部悬浮 bar）和 Frame（四边细边框 + 顶/左/右/底 bar 条）。
- 音乐特效：四条边都有，随 cava / 任何系统声音起伏；宽度可配（伸进来多深）、融合可配（水波感）。
- 基础功能：Vitreus 风格全功能搜索（apps/files/commands/emoji/clipboard/wallpapers/windows/web/calc）、通知（toast + 通知中心 + 声音设置）、Island bar（自动宽度的时钟；搜索/通知中心走 IPC）。
- 性能：切工作区 ≥120fps，音乐开/关都要；打开 launcher/通知中心时可以瞬时掉帧，关掉后回到目标。
- 观感：液态玻璃（每条窄条内部要融），接受跨 surface 的接缝用渐变/阴影假装。

## 实测（这台机器，历史数据：pleamar 0.4.31；当前 flake 用 0.7.7）

| 场景 | 中位帧 | compose | late |
|---|---|---|---|
| 常驻全屏 2560×1440，切工作区 | 16.6ms（60fps） | 3.9-4.5ms | 98.5% |
| 2560×62 bar strip，切空工作区 | 5.6ms（180fps） | 0.39ms | 2.2% |
| 1100×1440 中等 surface | ~11ms（90fps） | 5.8ms | 92.8% |
| 全屏 + 24 根 blend 玻璃柱（音乐） | 27.9ms（36fps） | 17.3ms | 99% |

参考：Quickshell 的 iNiR 154fps，切工作区 109-181fps。180 锁不住，120 是现实目标。

结论：180Hz 每帧 5.56ms。**常驻全屏透明 surface 是唯一的致命伤**，niri 会按整张 layer 合成。只要没有全屏 surface，5.6ms 的 bar strip 就是 180。

## 架构

### Surface 表

| surface | 尺寸 | anchor | 内容 | reserve |
|---|---|---|---|---|
| top | 2560×120 | top | Island bar（自动宽度）/ Frame 顶边 + 顶波形 | 无（Island）/ 46（Frame） |
| left | 150-200×1440 | left | Frame 左边 + 左侧波形；bar 在左边时也放这 | 46 |
| right | 150-200×1440 | right | Frame 右边 + 右侧波形 | 46 |
| bottom | 2560×150-200 | bottom | Frame 底边 + 底波形 | 46 |
| launcher | 660×640 | center | 搜索（居中面板；IPC 可开） | 无 |
| notif centre | 480×650 | bar 下方中间 | 通知历史 / DND / clear（IPC 可开） | 无 |
| toast | 294×112 | bar 下方中间或右侧 | 通知 toast + 主色倒计时（原 420×160 的 70%） | 无 |
| wallpaper | full | background | skwd-wall v2（Nix 默认）/ swaybg 回退；独立进程，不是 Pleamar surface | 无 |

- 永远不要常驻 2560×1440 的 Pleamar surface。壁纸交给 skwd-wall v2
  （或回退的 swaybg）的 background layer；面板只在打开时存在。
- 波形优先用 shader：一条边一个 shader 画整条；不要 24 根 blend 玻璃柱（实测 compose 17.3ms）。
- bar 的点击区留在 bar 所在的条里；面板的点击区在面板 surface 里；只通过 fact/event 通信。
- 各 surface 的 `rate`：bar 静态时低 rate，波形 60-120；不要所有条都 480。

### 面板

- 搜索：居中的 660 面板，apps/files/commands/emoji/clipboard/wallpapers/windows/web/calc；打开时请求键盘。
- 通知：Pleamar 的 notifications service；toast + 通知中心，两者都吸附在 bar 下方。
- 设置：十页 settings panel（含锁屏、IDLE、通知音效/位置/倒计时、MOTION 动效和天气城市）；BAR 页的 PANEL TINT 选择 wallpaper primary/secondary 及混合深度，作用于 bar、Frame、中心面板、设置、launcher、通知与 toast 的背板。
- 搜索、设置、通知中心都可以从终端用 `pleamar-ipc` 打开，见下面“终端 IPC”。

## pleamar 的坑（这次踩过的）

- **`size:` 只接受字面量数字**。`full` 可以，`full, 62` 可以，变量/表达式不行（`expected a number here`）。surface 尺寸不能随布局变，用固定尺寸 + 透明区域。
- **命名 surface 看不到父级绘制期的 let/zone**。surface 声明要放在它用的 let 之后；或者把 bar 的绘制期 zones 留在 bar surface 里。
- **bar 的绘制期 zones 和 panels 的弹簧不要跨 surface**。这次 `ov_btn`、`set_hit`、`vm_*`、`mcx`/`mcy` 和 `need_clock` 同时被 bar 和 panels 引用，一拆就 8 个 `undefined`。
- **`screen.width/height` 不可靠地等于显示器尺寸**：这次 scene 里它跟着 surface 尺寸走，从 1100 改成 `full` 后不重启进程它还是 1100（bar 停在左半边就是这个）。多 surface 时，显示器尺寸用 logic 查（niri/hyprctl）写成 fact，别在每个条里用 `screen`。
- **`reserve:` 会让 shell 自己的全屏 surface 缩小**。只给 bar/frame 条用，不要给面板/toast。
- **一个 scene 最多 65536 properties**；model 的 copies 按 `max` 建，不是按行数。
- **logic 的坑**：handler 读共享 global 是旧值；logic 设 fact 不触发 `on("fact:...")`；scene 和 logic 一起保存可能留旧 logic（保存 logic 后 `touch` 一下）。
- **47 个波形 slot 的几何是每帧都算的**，每个 slot 里两次 24 路 `pick`，实测读 scene 6-7ms。重做时最多 24 个 slot，或者用 shader / model。
- 直接调 Pleamar 时，`--say` 要引号包一条命令；本项目日常用 `pleamar-ipc`，不需要 `pleamar` 在 PATH 里。

## 当前实现（v0.1）

### 终端 IPC

搜索、设置、通知中心都不再依赖 bar 图标，可以直接从终端打开。Nix package
的 wrapper 会把 `PLEAMAR` 指向 flake 从 Git 构建的 0.7.7；仓库里的
`pleamar-ipc` 包装脚本用它找正在运行的 Island/Frame：

| 想打开 | 命令 |
|---|---|
| 搜索 | `pleamar-ipc search` |
| 设置（保持当前页） | `pleamar-ipc settings` |
| 设置指定页 | `pleamar-ipc settings 2` |
| 中心面板 toggle | `pleamar-ipc center` / `pleamar-ipc center toggle` |
| 中心面板指定 tab | `pleamar-ipc center 3` |
| 通知中心 | `pleamar-ipc notifications` |
| 窗口 picker | `pleamar-ipc windows` |
| 换壁纸 | `pleamar-ipc wallpaper /path/to/image.png` |
| 打开官方 picker | `pleamar-ipc picker` |
| 锁屏 | `pleamar-ipc lock` |

页号：`0 FRAME / 1 GLASS / 2 BAR / 3 FONT / 4 WALLPAPER / 5 ALERTS / 6 MOTION / 7 LOCK / 8 IDLE / 9 WEATHER / 10 WINDOWS`。
`pleamar-ipc` 在 `bin/pleamar-ipc`，并已链接到 `~/.local/bin/pleamar-ipc`；
新终端里找不到时用 `./bin/pleamar-ipc …`。两个布局都在运行时默认 Island，
可用 `PLEAMAR_SCENE=frame pleamar-ipc settings` 指定。

它内部对应的原始 IPC 事件是：

```sh
# 直接调 flake 构建的 Pleamar（package wrapper 已设 PLEAMAR）：
pleamar --say island "emit ipc_open_search"
pleamar --say island "emit ipc_open_settings"
pleamar --say island "emit ipc_open_settings 2"
pleamar --say island "emit center_toggle"        # 打开 / 关闭
pleamar --say island "emit ipc_open_center"      # 只打开（保持打开）
pleamar --say island "emit ipc_open_center 3"    # 打开并切到 tab 3
pleamar --say island "emit ipc_open_notifications"
```

没有 `pleamar` 命令时，用包装脚本找真实二进制：

```sh
PL=$(./bin/pleamar-shell --path)
"$PL" --say island "emit ipc_open_search"
```

Frame 把 `island` 换成 `frame`；`--say` 的 scene 名必须和启动的场景名一致。

### 从 Nix 构建/运行

```sh
nix build .#default
./result/bin/pleamar-shell island
./result/bin/pleamar-ipc search
```

`nix build` 会把 `pleamar-ipc`、Pleamar 本体（flake input
`github:k4ditano/pleamar`，从 Git 源码构建；flake.lock 锁当前最新 rev）和所有
运行依赖（cava、fontconfig、jq、niri、skwd-wall v2、swaybg 回退等）装进 package。wrapper 设置
`PLEAMAR` 并把它放在 PATH 前面，所以运行时不会退回系统里的 0.4.31。
拉最新源码：`nix flake update pleamar`，再 `nix build` / rebuild。直接用
`./bin/pleamar-shell` 跑仓库脚本时才走本地发现逻辑，可用
`PLEAMAR=/path/to/pleamar` 或 `nix develop` 指定。

## 接到 NixOS + niri

把仓库当 flake 输入。最小接法（路径换成你的 checkout）：

```nix
# flake.nix
{
  inputs.pleamar-shell = {
    url = "path:/home/zerone/projects/pleamar-shell"; # 换成你的 checkout
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, pleamar-shell }: {
    nixosConfigurations.niri = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        ({ pkgs, ... }: {
          environment.systemPackages = [
            pleamar-shell.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];
        })
      ];
    };
  };
}
```

然后：

```sh
sudo nixos-rebuild switch --flake .#niri
```

包安装 `pleamar-shell`（启动 shell）和 `pleamar-ipc`（发 IPC），并把
Pleamar（flake input `github:k4ditano/pleamar`，从 Git 构建，锁当前最新
rev）、cava、fontconfig、jq、niri、swayidle、skwd-wall v2、swaybg 回退等运行
依赖放进自己的 PATH。wrapper 设置 `PLEAMAR` 指向它；系统里不再需要预装
Pleamar 0.4.x。
更新引擎：`nix flake update pleamar`，再 rebuild；NixOS 的 `pleamar-shell`
input 会带上这个 transitive input。

### systemd user service（推荐）

`nixosModules.default` 提供 `services.pleamar-shell`，会安装包并生成
`pleamar-shell.service`。在 NixOS flake 里：

```nix
imports = [
  inputs.pleamar-shell.nixosModules.default
];

services.pleamar-shell = {
  enable = true;
  layout = "island"; # 或 "frame"
  # x86_64 默认启用；它会额外启动 skwd-walld.service，
  # 并把 PLEAMAR_WALL_BACKEND=skwd 传给 shell。
  skwdWall = true;
};
```

`skwdWall` 使用 flake input `github:liixini/skwd-wall/nix` 的发布二进制。
它只提供 x86_64-linux 包；aarch64 上该选项默认关闭并回退 swaybg。
关闭后 `bin/pleamar-wall` 仍可正常使用 swaybg：

```nix
services.pleamar-shell.skwdWall = false;
```

然后 **删掉** niri 里原来的：

```kdl
spawn-at-startup "pleamar-shell" "island";
```

重新部署后由 systemd 管理，编译/切换新提交后直接：

```sh
systemctl --user restart pleamar-shell.service
systemctl --user status pleamar-shell.service
```

不再需要 niri 重启。首次从 `spawn-at-startup` 迁移时，先停掉旧的 shell，
或在登录时让 systemd 启动它；否则 service 会因为已有 `pleamar --scene` 进程而退出。

niri 里只保留面板/锁屏 IPC 按键：

```kdl
// ~/.config/niri/config.kdl
binds {
    Mod+Space     { spawn "pleamar-ipc" "search"; }
    Mod+Shift+S   { spawn "pleamar-ipc" "settings"; }
    Mod+Shift+C   { spawn "pleamar-ipc" "center"; }
    Mod+Shift+N   { spawn "pleamar-ipc" "notifications"; }
    Mod+W         { spawn "pleamar-ipc" "picker"; }
    Mod+L         { spawn "pleamar-ipc" "lock"; }
}
```

- 用 Frame 就把 `island` 换成 `frame`；不要同时启动两套。
- 键位可换成 `Mod+D` / `Mod+Shift+C` 等，只要不要和已有 launcher 冲突。
- 想直接打开某一设置页：`Mod+Shift+G { spawn "pleamar-ipc" "settings" "2"; }`
  （页号 0–9）。
- 想直接打开中心面板的某一 tab：`Mod+Shift+V { spawn "pleamar-ipc" "center" "3"; }`
  （tab 0–6）。
- 改完 niri 配置后 `niri msg action reload-config`；新键立即生效。
- **不要再启动第二个通知守护进程**：本 shell 已是
  `org.freedesktop.Notifications`。如果还开着 Vitreus/iNiR，先停掉它们的
  notification server，否则 toast/通知中心会归先启动的那个。
- `pleamar-ipc` 自动找正在运行的 Pleamar scene；同时跑 Island/Frame 时用
  `PLEAMAR_SCENE=frame pleamar-ipc settings` 指定。

### 运行

```sh
./bin/pleamar-shell island   # 顶部胶囊 + 四边水波
./bin/pleamar-shell frame    # 四边玻璃框 + 四边水波
./bin/pleamar-shell lock     # 锁屏场景（通常由 IPC / 设置页启动）
./tests/check.sh             # Island / Frame / Lock + 实验都 --check
./tests/baseline.sh          # 无 shell：niri + 1×1 frame-callback 探针
./tests/perf.sh island       # 每 300ms 切一次工作区，测 8s
./tests/perf.sh frame
```

Nix package 的 wrapper 直接用 flake 的 Pleamar 0.7.7（`PLEAMAR`，PATH 优先）；
只有直接跑 `./bin/pleamar-shell` 时才会扫 `/nix/store`，并按 Vulkan loader
版本挑选 fallback；也可以 `PLEAMAR=/path/to/pleamar` 指定。

### 目录

```text
scenes/
  island.plm  island.luau    Island 入口：水波 + 胶囊 + 面板
  frame.plm   frame.luau     Frame 入口：水波 + 连续玻璃框
  lib/shell.luau             cava、~/.config 配置、apps、quiet
modules/
  common/common.plm          palette / facts / springs / shader 声明
  common/motion.plm          PanelPop：fade/spin/unfold/drop/aperture/random 共享动效
  notifications/notifications.plm  toast + notification centre (attached under the bar)
  island/bar.plm             Island 胶囊（只在 Island 布局）
  island/water.plm           Island 四边水波
  frame/glass.plm            连续玻璃框：四条 rail + 四个圆角楔，一个 body
  frame/water.plm            Frame music 的四边水波（当前实现）
  lockscreen/lockscreen.plm  独立锁屏场景（ext-session-lock + PAM）
  settings/panel.plm         Vitreus 风格设置面板：FRAME MUSIC / GLASS / BAR / FONT / WALLPAPER / NOTIFICATIONS / MOTION / LOCK / IDLE / WEATHER
  launcher/launcher.plm      Vitreus 风格全功能搜索（apps/files/commands/emoji/clipboard/wallpapers/windows/web/calc）
  notifications/notifications.plm  toast + 通知中心（吸附在 bar 下方）
  center/panel.plm                 7-tab 中心面板（center panel）
  windows/panel.plm              全屏窗口 picker：玻璃卡片、字母、荧光与动效
  centerkeys.plm / .luau           单 surface 键盘 helper
bin/pleamar-window-previews       niri 窗口截图、缩略图缓存与剪贴板保护
assets/panel.wav / assets/sounds/  面板 click 与 8 种通知音
assets/emoji.json                 搜索的 emoji 数据
  water/water.wgsl           直边水波
  water/water_corner.wgsl    圆角水波
bin/pleamar-shell            本地开发启动器
tests/check.sh               编译检查
tests/baseline.sh            无 shell 基线（1×1 frame-callback 探针）
tests/perf.sh                切工作区性能测量
experiments/wrap.plm         单张全屏水环参考（不默认使用）
experiments/probe.plm        1×1 基线探针
```

### 四边水波

- 四条 120px 边条；上下边条里各自内嵌两个 corner shader，所以四个角是
  圆弧连接，不是四条直条硬拼。
- Island 的水波 corner 是 46×46；Frame 的水波 corner 是 92×92
  （46px 内缩 + 46px 圆弧）。Frame 的玻璃圆角现在由 `frame/glass.plm`
  的 22px 楔子负责；水波 corner 只画水，不再补玻璃。
- 每条边都拿到完整的 6 个 cava band，不是按屏幕角度分配频率，所以四条边
  会一起起伏；不会只有顶边吃低频。
- cava 60fps → 6 个 facts → 弹簧 → shader 在 120fps 画。Ripples 可选
  1–10 条波列；Wave height 控制每条波的起伏幅度；波高 4–58px，
  `AMPLITUDE` 放大。Sensitivity 先按每个
  频段的近期峰值归一化，再用 `GAIN` 塑造动态范围；cava 原始值顶到
  1.0 时，低灵敏度和高灵敏度仍会给出不同的起伏。低频包络同时驱动
  整条边的高度，时间性的细波只做叠加，不再盖过节拍。
- 没有常驻 2560×1440 的 layer；四条水波是 2560×120、120×1440。
- **Frame 的玻璃框是连续的，不是四条矩形。** `modules/frame/glass.plm`
  把四条 10px rail 和四个圆角楔放进**同一个 body**：一个轮廓、一个 lens、
  一个 rim、一个 shadow，内角 22px 圆角。Island 胶囊的宽度由时钟内容
  （`isl_time.width`）加上左右 padding 算出来，宽度随 font / 时间变化；
  margin 8，只在 Island 布局里。Frame 不再复用这条胶囊。
- **最终采用四边 overlay 版本。** 试过 background-layer：四边保留条
  版本 11.7ms / ~79fps，比 overlay 更慢；单张全屏 background 只有
  在没有保留条、靠窗口 gap 露出时才便宜，不适合“四边都可见”的要求。

### Island bar

- 只有时钟，没有搜索/通知/设置图标；胶囊宽度按内容自动算：
  `isl_time.width + padding * 2`，所以字体或时间数字变化时宽度跟着变。
- 时间去掉日期，只显示 `HH:MM`；小时和分钟用壁纸 primary（`aqua`），冒号用
  secondary（`azure`）；秒数在右侧、小一号、同样用 secondary，位置略低于分钟基线。
- 秒数用分体翻页：个位每秒从下方上浮并放大（`isl_sec_ones`）；十位只在
  09→10、19→20… 这类十位真正变化时，才和个位一起翻（`isl_sec_tens`）。
  翻页不改变布局宽度，所以胶囊不会抖。
- 点时间打开设置面板；打开面板的 IPC 命令见上面。

### 设置面板（Vitreus 风格）

`modules/settings/panel.plm` 是 Vitreus `pages/settings_panel.plm` +
`pages/glass.plm` 的结构：居中大面板、gear 徽章、`SETTINGS` 标题和
`SETTINGS › LOOK / SHELL / SCREEN / SYSTEM › page` 面包屑、按四组分类的
左侧 sidebar、右侧 page 的卡片 rows + sliders + switches。侧栏高亮使用
弹簧在 32px 槽位之间滑动；整行的选中图标会轻微放大并转向主色。父菜单
归属如下：

- **LOOK**：Wallpaper、Glass
- **SHELL**：Bar、Frame music、Typeface、Motion、Notifications、Windows
- NixOS 模块额外启用 `pleamar-lock-keeper.service`，做法和 Vitreus 的
  `vitreus-keep` 一致：锁屏作为独立 Pleamar 进程长期运行，退出就重启；
  如果 logind 仍报告锁定，重启后的锁屏会再次收到 `fact locked true`，
  让 niri 用真正的锁面替换红色 fallback。
- **SCREEN**：Lock screen、Idle
- **SYSTEM**：Weather

滑条是 Vitreus 的 12px 双层描边药丸轨道：主色以铅笔竖线填充，末端是
环形 knob；开关是 34→38px 的胶囊轨道，22px 高，knob 17px 并在滑动时
从圆形收成圆角方块。按钮和选项是带 hover 描边的药丸；这些只是视觉
组件，事实、事件和页面索引保持不变。
当前保留十一页，原来的临时小面板已删除：

- **FRAME MUSIC**：Frame music 开关；Amplitude 20–220%；Sensitivity
  80–240%；Ripples 1–10；Wave height 0–300%；Blend 0–100%。
  Ripples 每增加一级就多一条更短、更快的波列；Wave height 单独控制
  每条波峰/波谷的起伏高度（0% 是平滑水线，300% 最粗粝），不受整体
  Amplitude 影响。Sensitivity 用每频段近期峰值归一化后的包络，所以
  安静和响的曲子都会跟着节拍变化，不会因为 cava 原始值顶到 1.0 就失效。
- **GLASS**：Glass 开关；Bend what's behind 开关；Opacity 20–100%；
  Blur 0–100%（lens 内部模糊，即 `glass_frost`；Bend 开启时才有
  效果，关闭时 UI 标出 `Bend off`）；Edge light 0–100%；Edge thickness
  0–2；Rainbow fringe 0–2；Dome 0–1.5；Milk 0–1。niri 的 compositor
  blur 是全局 `blur {}`，不由这个 slider 控制。
- **BAR**：Bar height 32–80px；只作用于 Island 胶囊，默认 44px。
  Frame 布局不再显示这条 bar。
- **WINDOWS**：窗口 picker。Thumbnail size 140–420px、Per row 2–8、
  Reveal（Fade / Rise / Zoom / Drop / Unfold / Spin / Random）、
  Duration 160–900ms、Background blur 0–100%，以及参与选窗的字母
  （A–Z、去重）。默认每个窗口一个字母；窗口数超过配置字母时才切换为
  随机双字母；字母组合容量不足时退回 A–Z。背景是打开前抓取的桌面截图，
  先按 blur 值预模糊再映射，不使用 glass 或 lens，避免与 niri 的模糊叠加
  闪烁。窗口预览通过 niri `screenshot-window` 生成，多张并行抓取，动画
  最后 8% 会等预览就绪；截图前后恢复剪贴板并在 Pleamar 内抑制 niri 的
  “Screenshot captured” toast。键盘由独立的单 surface `windowkeys` helper
  接管，向主场景转发字母、Esc 和 Enter。
- 帧率诊断（`render · slow frame` / `this scene does not keep up`）默认由
  wrapper 过滤；调试时用 `PLEAMAR_RENDER_LOG=1` 启动可恢复完整日志。
- **LOCK**：锁屏外观。Blur（Light/Medium/Heavy）、12/24 小时与秒、
  Clock size、日期格式、密码遮罩（Shapes/Dots/Stars/Special）、遮罩调色板、
  Media pill / Power buttons；`Lock now` 与 `Test lock`。Mask colour 只控制
  输入密码时遮罩符号的颜色；时间、日期、状态和面板颜色来自壁纸 palette。
  锁屏是独立的
  `lockscreen/lockscreen.plm` 场景，用 compositor 的 `ext-session-lock`；
  `pleamar-lock sync` 会在每次上锁前把当前 `palette.json` 推给已预热的锁屏
  和 PAM 验证密码；Ctrl+U 清空，测试锁可用 Esc 空栏或 1 分钟退出。
  `Test lock` 会先换一个全新的锁屏进程，避免复用到 socket 还活着但锁面已失效
  的旧场景；正常上锁仍复用预热进程。
  锁屏用 `PLEAMAR_SWAPCHAIN=1` 启动（锁面提交兼容开关；0.4 必需，0.7.x 下
  保留；Vitreus 官方对 0.4 同样使用）；否则 niri 的 DPMS 关屏/唤醒会让
  0.4 锁屏进程收到 `Output is already locked` 后退出。watchdog 只是兜底：
  shell 每 2 秒探测
  锁屏 socket，session 仍锁定时会自动拉起并重新锁定。niri 红屏时也可以按
  `Mod+L`（已设 `allow-when-locked=true`）手动拉起新的锁屏。
- **IDLE**：`Lock after` / `Screen off after`，步进 0（Never）、5 秒、10 秒、
  30 秒，然后 1、2、3、5、7、10、15、20、30、45、60、90、120 分钟（滑块
  17 档，最短 5 秒）。由 `swayidle` 执行：锁屏调用
  `pleamar-ipc lock`，关屏调用 `niri msg action power-off-monitors`，有输入时
  自动 `power-on-monitors`；不配置 suspend。
- **WEATHER**：城市输入框与 Apply。Open-Meteo 负责当前天气、逐小时和
  未来四天，Nominatim 负责城市名到经纬度；城市无法解析时退回 wttr.in。
  结果缓存十分钟，失败时保留上一次结果。城市写入 `weather_city`。
  设置面板的输入由 `scenes/settingskeys.plm` 的独立单-surface helper 接管
  （主 scene 多 surface 时 Pleamar 不派发 layer 键盘）；它把键入的文字转发到
  `weather_city` / `font_query`，Esc 关闭设置。`bin/pleamar-settingskeys`
  随设置打开和页面切换启动或重启，关闭时停止。
- **MOTION**：Search / Settings / Notification toast / Notification centre 四个面板
  各自选择 Fade、Spin、Unfold、Drop、Aperture 或 Random；选择即时写入
  `anim_*`，下一次打开生效，关闭动画保持同一姿势。
- **WALLPAPER**：`~/Pictures/Wallpapers` 的壁纸网格，3×3 一页，缩略图
  缓存在 `~/.cache/pleamar-shell/wallpapers`；点一张立即换壁纸，当前壁纸
  有主色描边。顶部 **Random** 一键把转场设为 `random`；底部 **Transition**
  行仍可循环 skwd 的 41 个转场（含 Off，默认 `crossfade`），下一次换图生效。
  Auto rotate 按文件夹排序逐张切换，间隔 1–60 分钟；默认关，倒计时显示
  `Next in N min`。到点换图沿用当前 Transition，所以选中 `random` 后每次
  自动换图都是随机动画。skwd 自己的 picker 换图时，shell 会在 5 秒内同步
  当前项和颜色。页面右侧的空位也属于面板，不会点穿到后面的窗口
  （`cp_shield` / `la_shield`）。
- **FONT**：全局字体。搜索 `fc-list` 返回的已安装字体，点一行选
  Selected，Apply 后写入 `font_family` 并由 systemd user service 重启
  整个 shell。重启时 `bin/pleamar-fonts` 直接按 Vitreus 的做法，把所选
  字体复制并改名为 `Space Grotesk`，fontconfig 拒绝真实 Space Grotesk，
  shell 只看到改名后的字体；所以 bar、设置面板、launcher 的所有文本都会
  跟着变。重启通常 5–7 秒。

面板也可以用终端 IPC 直接打开：`pleamar-ipc settings [0–9]`。
锁屏外观的 `lock_*` 与 IDLE 的 `idle_*` 也写在同一份
`~/.config/pleamar-shell/config.json`；`pleamar-ipc lock` 会启动独立的
`lockscreen/lockscreen.plm` 并把设置推进去。IDLE 由 `swayidle` 执行，
默认 Never，不配置 suspend。

全部写入 `~/.config/pleamar-shell/config.json`，slider 拖动即时生效；
字体例外，需要 Apply 重启。`bin/pleamar-shell` 启动时读取
`font_family`，不是 Space Grotesk 就生成
`~/.config/pleamar-shell/fonts.conf` 并导出 `FONTCONFIG_FILE`。
`Bend` 关掉会保留玻璃但不再用全屏 lens（改用 compositor blur），是
Frame 玻璃的主要性能开关。面板玻璃本身也带 `shine: pointer`，鼠标在
面板上移动时边缘高光跟着转，和 Island 胶囊一致。

### 面板动效（参考 iNiR center panel）

`modules/common/motion.plm` 是共享的 `Motion.PanelPop(effect, p, w, h)` 组件，
把玻璃 body 和所有内容包在同一个 group 里。新面板只要 import 这个库，传入
效果编号和弹簧进度，就能复用同一套出场/退场：

- `0 fade`：原地的淡入 + 18px 上浮 + 96%→100% scale。
- `1 spin`：从 24% scale、-30° 旋转到正常；比 iNiR 的 -100° 收敛，避免
  面板 surface 的四角被裁掉。
- `2 unfold`：以底边为 pivot，纵向从 2% 展开到 100%。
- `3 drop`：从 surface 上方 `h + 120` 处落下来，关闭时反向收回。
- `4 aperture`：横向 82%→100%、纵向 2%→100%，像一条缝张开。
- `5 random`：每次打开时随机选一个姿势，关闭动画沿用同一个；不会在动画中途改变。

设置面板的 **MOTION** 页单独设置五个面板：Search / Settings / Notification
toast / Notification centre / Centre panel。配置键是 `anim_search`、
`anim_panel`、`anim_toast`、`anim_center`、`anim_center_panel`；运行时
选中的实际姿势在 `search_fx` / `panel_fx` / `toast_fx` / `center_fx` /
`center_panel_fx`，只用于渲染，不写入 config。
面板的 `open:` 在 `p > 0.01` 时继续保持 surface 存活，所以关闭动画不会
被 surface 提前销毁。

### 中心面板（参考 iNiR CenterPanel）

`modules/center/panel.plm` 是一块 1120×720 的居中玻璃面板：左侧是主色
时钟和壁纸副色的日期，中间是 7 个 tab，右侧是页码和关闭按钮。打开后
用 **1–7** 直接选 tab，**Tab / Shift+Tab** 前后循环，**Esc** 关闭；tab
本身也能点。tab 指示器是一块会滑动的胶囊，内容切换有 260ms 的淡入
上浮，vinyl、cava 频谱、状态环和 system history 各自独立动。

七个 tab：

| # | tab | 内容 |
|---|---|---|
| 1 | Overview | CPU/MEM/GPU/磁盘四张水 tank 卡片（卡片自身是容器，主色水位 + 动态水面，百分比为数字主体）、Now Playing、最近通知；右侧上方是网络 RX/TX 监控卡，下方是压缩后的城市天气（当前、逐小时、未来四天） |
| 2 | System | Vitreus 原版系统监控：host/uptime/load/kernel、CPU ring + 60 秒 history + 核心格、内存、GPU 利用率/VRAM/温度/功耗/风扇/频率 + 60 秒 sparkline、网络 60 秒 RX/TX sparkline、存储、温度、最忙进程；内容可滚轮滚动 |
| 3 | Tray | StatusNotifier 系统托盘：三栏固定布局；左侧应用列表，悬停自动在中间玻璃卡打开动作，带 `›` 的动作在右侧子菜单卡展开；左键仍触发默认动作，右键也打开动作卡 |
| 4 | Media | 当前 MPRIS 曲目、旋转唱片、频谱、prev/play/next |
| 5 | Audio | PipeWire 输出/输入音量、静音、输出设备切换、cava 频谱；滑块直接调用 `wpctl`，设备列表来自 `wpctl status` |
| 6 | Calendar | ccal 农历网格、节气/传统节日、休假/补班、纪念日倒计时、前后月；右侧 Today 显示当前查看月份的纪念日（已过的标为已过）；悬停日期显示完整农历 |
| 7 | Actions | Search / Settings / Notifications / Lock、四个快捷开关，以及带确认的 Log out / Restart / Shut down |

系统监控的数据来自 `bin/pleamar-sysmon`（从 Vitreus 的
`vitreus-sysmon` 移植，只读 `/proc`、`/sys`，GPU 走 `nvidia-smi`
或 sysfs）。它只在中心面板打开时运行，关闭即 `term`，不会常驻。
System 页的网络卡下方是 60 列 RX/TX text sparkline（每秒一列，平方根
缩放）；它复用同一份 60 秒历史，但不走已经满行的 `sys_hist` model，
所以会一直保留整分钟，而不是只在打开时短暂出现几根很矮的柱子。
GPU 卡也使用 60 列利用率 sparkline；AMD 卡的温度、功耗、风扇和频率
从 `amdgpu` 的 hwmon（`temp1_input`、`power1_average`、`fan1_input`）
与 `pp_dpm_sclk` / `pp_dpm_mclk` 当前档位读取，NVIDIA 仍走
`nvidia-smi`。STORAGE 卡下面新增 DISK WRITE 速度卡，只显示当前写入
吞吐，始终使用 KB/s 或 MB/s，不做历史图表。
面板的主色/副色是壁纸色板里的 `primary` / `secondary` 角色；水波仍用
`aqua` / `azure`，两套名字共享同一份 wallpaper palette。

Overview 的四张资源卡不再用圆环：卡片的圆角矩形本身就是水池，水位等于
CPU / 内存 / GPU / 磁盘占用百分比。`modules/water/card.wgsl` 在卡片内部
用 SDF 裁出同样的 16px 圆角，画主色的水体、亮水线、缓慢焦散和三层水面波；
百分比是卡片里的 34px 主数字，磁盘名在右上角，meta 在标题下方。悬停只会
让水面幅度和边框稍微增强，水位始终对应采样值。

网络卡位于右侧天气卡上方，复用 `pleamar-sysmon` 的 60 个 `sys_hist` 样本：
左边是下载/上传实时速率与累计量，右边是 30 列 RX/TX 双行 sparkline（每列
取两秒峰值）。sparkline 由 text 状态生成，不依赖已经满 60 行的 model，
因此开着面板也不会在第一个窗口后丢失历史；低流量用平方根放大，避免
400 B/s 的样本完全消失。`modules/water/netfx.wgsl` 再画持续移动的扫描光带
和右缘脉冲，所以即使链路空闲也能看出监控在运行。天气卡从 396px 压到
260px，仍保留当前天气、6 小时和 4 天预报。

数字键、Tab/Shift+Tab 和 Esc 由 `scenes/centerkeys.plm` 转发：它是一个
只有 1×1 透明 surface 的独立 Pleamar 进程，打开中心面板时启动，关闭时
结束。多 surface 的主场景不一定能拿到 layer 键盘焦点，这个单 surface
helper 负责独占键盘，再把 `center_key_digit` / `center_key_tab` /
`center_key_escape` 发给主场景。实测 1–7、Tab、Esc 都生效。

Calendar 页的数据由 `bin/pleamar-calendar` 汇总：`ccal -x -g -u` 读农历和节气，
holiday-cn 的年度 JSON 提供休假/补班，结果缓存在
`~/.cache/pleamar-shell/holidays/`。纪念日读取
`~/.config/pleamar-shell/anniversaries.json`，格式与 iNiR Holiday Countdown
相同；它必须和 `config.json` 放在同一个配置目录。`ccal` 需在系统 PATH 中，
首次取节假日需要网络，失败时沿用已有缓存。倒计时跟随当前查看的月份，
当月已经过去的纪念日仍会列出并标为“已过”；悬停网格中的任意一天，
月份标题右侧会显示该日的完整农历日期（含闰月）。

Overview 的天气由 `bin/pleamar-weather` 获取：先通过 Nominatim 把设置里的城市
解析为坐标，再请求 Open-Meteo；城市解析失败时退回 wttr.in。结果缓存十分钟，
面板打开和每 15 分钟刷新一次。城市输入在 `SETTINGS › SYSTEM › Weather`，
写入同一份 `config.json` 的 `weather_city`。

### 搜索（原 Vitreus launcher）

- Bar 上不再有放大镜；用 **终端 IPC** 打开一个 **屏幕正中间** 的玻璃面板
  （`launcher.plm`）：`pleamar-ipc search`。
  试过从 bar 长出的液体 neck，但 bar 和搜索是两个 layer surface，接缝/阴影
  无法完全消掉，所以按你的兜底要求改成居中；`la_p` 弹簧驱动
  `Motion.PanelPop`，默认 fade，可在 MOTION 页改。
- 搜索框和两行前缀提示照 Vitreus：`#` files、`>` commands、`:` emoji、
  `^` clipboard、`~` wallpapers、`@` windows、`?`/`!` web、`=`/`+` calc。
  提示格可点，直接把前缀放进输入框。
- 默认搜 apps（也自动识别算式/单位换算，如 `5 km to mi`、`15% of 80`）；
  `↑↓`/`Tab` 选择，Return 运行，Esc 关闭。
- 除 apps 外：files（`find $HOME`，最多 60 个）、commands（设置页、
  screenshot、terminal、wallpaper next、notification test 等）、emoji（原
  assets/emoji.json）、clipboard（cliphist）、wallpapers（当前文件夹）、
  windows（niri JSON）、web（DuckDuckGo/Google/YouTube/GitHub/Wikipedia 等）。
- 没有旧 app launcher 了；`la_apps` 现在是通用结果 model。

### 声音

- `assets/panel.wav`（Vitreus 原文件）在 bar/设置页/search/通知中心点击时
  由 `pw-play` 播放（0.25 音量，250 ms debounce）；BAR 页有 Panel sound 开关。
- `assets/sounds/*.oga` 是 freedesktop 通知音；通知设置页可选 8 种默认音
  （Message/Soft/Bell/Info/Done/Device/Alarm/Warning），Test 按钮会真的
  发一条 `notify-send`。

### 壁纸与配色（照 Vitreus / iNiR 的做法）

原项目的两条路线：

- **Vitreus**：壁纸由 `awww` 守护进程显示；换图后运行
  `iris --json-only --dark 1 --glass <壁纸>`，从输出取 `bg / surface / fg /
  dim / accent / red`，做对比度下限和强调色强度调整；结果变成
  `pal_*` 三通道 facts，场景里的 `rgb(pal_*)` 直接取色，不重载场景；
  同时写 `palette.json` 和锁屏用的 `palette.plm`。bar、设置面板、launcher
  都用 `tint` / `panel` / `ink` / `faint` / `mint` 这些角色，所以换图后
  整壳一起变色。
- **iNiR**：壁纸 → `generate_colors_material.py`（Material You /
  materialyoucolor）→ `colors.json` → `MaterialThemeLoader` → `Appearance`
  tokens → UI；它生成的是整套 Material 角色，不止主色和副色。

这个 checkout 没有 awww / Iris，也不把颜色工作交给外部调色器：

- 壁纸由 **skwd-wall v2**（Nix 默认）或 **swaybg**（回退）画在 compositor
  的 background layer；Pleamar 不常驻 2560×1440 surface（见性能一节）。
  `bin/pleamar-wall` 是唯一入口：`PLEAMAR_WALL_BACKEND=auto` 在 skwd socket
  存在时选 skwd，否则选 swaybg；NixOS service 默认显式选 skwd。
  `bin/pleamar-wall-skwd` 通过
  `$XDG_RUNTIME_DIR/skwd-wall-v2/wall.sock` 发送 `wall.apply` /
  `wall.outputs`，不依赖 skwd 的 GUI。
- skwd 的转场在 Settings → Wallpaper 的 **Transition** 行选择（41 个条目，
  包含 Off；默认 `crossfade`）。`wall.apply` 带
  `transition_shader` / `transition_duration_ms`，默认 650 ms。
  `bin/pleamar-wall` 只有在 skwd 接受后才停掉旧 swaybg，避免两个背景层。
- `pleamar-ipc picker` 打开官方 `skwd-wall-v2` 前端；如果它已经运行，先用
  `skwd-helm ui show` 唤起，不会重复启动。官方 picker 的打开淡入、Slices /
  Geometric / Wall / Sandy 视图和转场预览都由 skwd 自己绘制，不是 Pleamar
  重画。picker 里选图后仍由 5 秒同步更新 Pleamar 设置和 palette。
  官方 picker 内部的转场/动画由它自己的 Motion 设置控制；Pleamar 的
  **Transition** 行控制 Pleamar 网格和 Auto rotate 触发的 `wall.apply`。
- 从 skwd 自己的 picker 或 `skwd-helm apply` 换图时，shell 每 5 秒读一次
  `wall.outputs`；路径变化会先停掉旧 swaybg 层，再走 `adopt_wallpaper()`，
  更新设置页当前项、页码、`config.json`，并触发现有
  `bin/pleamar-colors`。不重复调用后端。自动 apply 也只在后端接受后才
  更新 palette，避免“颜色变了但桌面没变”。
- 回退 swaybg 时仍使用本项目 patch 过的 build，layer namespace 是
  `pleamar-shell-wallpaper`（`niri msg layers` 里可见）；同一路径不重启，
  换图 kill/start 一次，并在 `$XDG_RUNTIME_DIR/pleamar-swaybg.path` 记录当前图。
- `bin/pleamar-colors` 用 ImageMagick 把壁纸缩到 128×128、取 24 色直方图，
  选出**主色**（present + saturated 评分最高）、避开主色相位的**副色**和
  **三级色**；再生成暗色玻璃表面 `tint / panel`、可读的 `ink / faint`，
  以及 Vitreus 的 `mint / mintlo / minthi / onmint / off / alert` 和
  Material 风格的 `primary / secondary / tertiary / on_* / background /
  surface / surface_variant / on_surface / outline / error`。
- 结果写进 `~/.config/pleamar-shell/palette.json`（以后脚本可以直接读）
  和 `config.json` 的 `palette`；logic 再设 `pal_*` facts，bar、设置面板、
  launcher、四边水波的颜色都在下一帧变化，不重启。实测从点壁纸到
  `palette.json` 的 primary 更新约 **312 ms**（在壁纸守护进程切图之前开始
  跑调色，见 `set_wallpaper`）。`palette.json` 同时有
  `primary/secondary/tertiary`、`on_*`、Vitreus 的 `mint/minthi/onmint/...`
  和 Material 风格的 `background/surface/outline/...`。
- **Frame music / 四边水波**用 `aqua = primary` 和 `azure = secondary`：
  水波两端分别是壁纸的主色和副色，和原来固定的 aqua/azure 位置一样。
- 只有一份色板；面板、launcher 的玻璃 body 固定最低 82% 不透明度，避免
  亮壁纸上的白字读不清；bar 仍按 Glass 页的 Opacity。
- 设置面板的右侧现在有一块全表面 `zone` 盾牌，空白处点击不会穿透到背后
  的窗口；侧边栏、slider、按钮的 zone 仍在它上面。

### 通知

- Pleamar 本身是 `org.freedesktop.Notifications` server；logic 用
  `sys.watch("notifications")` 收列表，`notifications.keep(true)` 保留，
  `notifications.dismiss/invoke/clear` 操作。
- **Toast**：294×112 玻璃卡（原 420×160 的 70%，整体缩放），吸附在 bar 下；位置可选 **Top center**
  （bar 正中间下方）或 **Top right**（bar 右端下方），不是屏幕中央。
  左侧是 app 图标；没有图标时画 Vitreus 风格的铅笔铃铛，并带一圈扩散
  ring 和铃铛/图标摆动。app 名称 11px、壁纸 secondary；标题 16px、
  壁纸 primary、最多两行；body 13px、faint 混向 ink、最多两行，并且用
  title 的实际测量高度紧贴排在标题下方，不会再和标题第二行重叠。
  不再绘制 action 按钮，紧急时红色边。Toast 的 lens 现在被圆角 clip
  裁切，所以既保留壁纸的透光背景，也不会在圆角卡后面留一层直角矩形。
  普通 toast 的左侧图标外有一圈主色倒计时：完整圆环从 12 点开始，
  随时间顺时针缩短并变淡，剩余秒数显示在图标正下方；50ms 的逻辑采样
  由 `nt_fill` 弹簧补成连续动画。紧急 toast 不自动消失，因此不画圆环。
- **通知中心**：从终端 `pleamar-ipc notifications` 打开；480×650，吸附在 bar 下方中间。最近 8 条
  历史、DND、Clear、Sounds、Close；点卡片调用该通知的 default action。
- **通知设置**（ALERTS 页）：Top center / Top right；Play a sound；默认音
  （8 种，选择即试听）；Toast countdown（2–60 秒，默认 6，步进按钮）；
  Do Not Disturb；Send test；Open centre。倒计时写入 `nt_secs`，下一次
  toast 生效；紧急通知不自动关闭。
- 音效走 `pw-play`，面板提示走 `/usr/share/sounds` 的 freedesktop 原文件
  （已复制到 `assets/sounds`，不依赖系统是否安装 theme）。

### 玻璃

- Island 胶囊、Frame 连续玻璃框、设置面板和 launcher 共用 `glass_on` /
  `glass_bend` / `glass_refr` / `glass_disp` / `glass_dome` / `glass_milk` /
  `glass_tint` / `glass_frost` / `glass_edge`。默认 glass 开、bend 开、
  tint 58%、frost 100%、edge 34%。
- Island 胶囊小，lens 成本低；Frame 的全屏玻璃环 lens 成本高（见实测）。
  `Bend` 关掉仍保留玻璃和 blur，但不做全屏 lens；`Glass` 关掉只剩 tint。

### 实测（这台机器，用户音乐持续播放，2560×1440@180，RX 6500 XT / niri）

| 场景 | 切工作区中位 | 实际帧率 | p95 | late（对 180Hz） |
|---|---|---|---|---|
| **仅 niri + 1×1 frame-callback 探针** | **11.0–11.1ms** | **90–91fps** | 16.8ms | 82–85% |
| Island：玻璃胶囊 + 四边水波 + swaybg 壁纸 | 10.9ms | 91.7fps | 18.5ms | 83.3% |
| Frame：连续玻璃框 + 四边水波，**GLASS 开** | 20.1ms | 45.6fps | 43.1ms | 77.8% |
| Frame：同上，**GLASS 关** | 11.1ms | 86.3fps | 19.9ms | 83.3% |

- 基线探针只有 1×1 像素、只请求 frame callback，没有 bar / panel / water；
  8 秒 723–729 帧，paint 0.1ms，`waiting for the screen` 10.9–11.9ms。它证明
  **没有 shell 时 niri 自己切工作区就只有 ~90–91fps**。复现：
  `./tests/baseline.sh`。
- 场景里 `rate: 120`；报告里的 late 是按显示器 180Hz 的周期算的，所以
  120fps 本身就会显示较高的 late。实际帧时间看 median / p95。
- **Island 玻璃胶囊 + 四边水波 + swaybg 壁纸是 10.9ms（91.7fps），基本就是
  niri 自己的 11.0ms 基线；壁纸在 compositor 的 background layer，不是
  Pleamar 的全屏 surface。**
- **Frame 的连续玻璃框是 20.1ms（45.6fps），瓶颈是 2560×1440 玻璃 body
  的 lens：paint 11.2ms。GLASS 关掉同一个 Frame 回到 11.1ms（86.3fps），
  和 niri 基线几乎一样。** 这不是四条矩形的问题——矩形已经消失，是一张
  全屏玻璃场的成本。
- 结论：120fps 仍然不是水波 shader 的问题；Frame 玻璃需要下一轮优化
  （lens 改成按边/分块，或默认 GLASS off）。面板里的 `GLASS` 开关现在就是
  这个性能/观感开关。
- 旧的“只有顶边”是 full-screen ring 按角度分频导致的；现在每条边独立
  映射全部 band，四边同时动。
- 旧版四角空是四条独立 layer + reserve 互相缩进、没有角落几何导致的；
  现在水波 corner 内嵌在上下条里；Frame 的玻璃圆角由 `frame/glass.plm`
  的 22px 楔子负责，不再是四条矩形。

## 验收（最初目标；当前实测见上）

- `pleamar --check <scene>.plm` 通过。
- `niri msg layers` 里没有常驻 2560×1440 的 pleamar layer。
- `pleamar --report --seconds 8`：
  - 切工作区：late <5%，中位 ≤5.6ms（180）或 ≤8.33ms（120）。
  - 音乐开：compose <2ms，late <10%。
- 打开 launcher / 通知中心时允许掉帧；关闭后回到目标。

## 最初计划（保留）

1. 一个 2560×62 的 top strip，只画 bar 的壳和几个 zone，`--report` 确认 5.6ms / late <5%。
2. 加 Frame 的四条边（thin strips），确认还是 5.6ms。
3. 加一条边的 shader 波形，确认 compose <1ms；再加四条。
4. 加 launcher 面板和 toast。
5. 最后做设置页和主题。

## 参考

- pleamar（flake input `github:k4ditano/pleamar`，锁当前最新 rev），语言
  0.9；`pleamar --docs reference`、`--docs recipes`。旧的 0.4.31 只作本地
  fallback。
- iNiR Iris（`~/projects/iNiR/modules/iris`）：`frame/IrisFrame.qml`、
  `field/IrisField.frag`、`components/IrisGlassEdge.qml`、`settings/IrisOptions.qml`
  是 Island / Frame / glass / frame music 设置的参考。IrisField 的 frame 是
  “内圆角矩形之外”的一张连续玻璃场；本项目用 pleamar 的单 body 环复刻，
  不用 Qt field。
- Vitreus（`~/projects/Vitreus`）：设置面板照 `pages/settings_panel.plm`
  和 `pages/glass.plm` 的结构/文案/row-slider-switch 写法；字体列表照
  `pages/theme.plm` 的搜索 + 行选择，字体应用直接照 `bin/vitreus-fonts`：
  复制/重命名字体为 Space Grotesk、reject 真实 Space Grotesk、用
  `FONTCONFIG_FILE` 启动。它旧的 bar/frame 全屏 surface 架构不照抄。
