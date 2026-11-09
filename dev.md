## ✅ 已完成 - Notches Frame Music 功能实现

参考了 Vitreus 项目的实现方式，成功实现了以下功能：

### 实现的功能：

1. **音乐可视化四边frame** ✅
   - 顶部边缘：12个柱子（避开时钟notch）
   - 底部、左、右边缘：各12个柱子
   - 可通过 `music_frame_sides` 切换：0=仅顶部，1=四边
   - 所有柱子在同一个body内，实现真正的液体玻璃融合

2. **Drawer展开效果** ✅
   - 设置面板和中心面板都实现了像Vitreus那样的水波衔接效果
   - Drawer通过 `blend` 参数与frame液体融合
   - 展开时的neck拉伸动画使用 `notch_drip` spring

3. **架构改进** ✅
   - 所有shapes（frame、drawers、music bars）在同一个body内
   - 音乐柱子手动展开（pleamar不支持body内使用repeat）
   - 每个柱子通过 `blend: 14` 参数与frame融合
   - 使用 `if(..., 0, 30000)` 移动不活跃柱子到屏幕外

### 关键技术发现：

**Pleamar语言限制：**
- ❌ 不能在body块内使用`repeat`循环
- ✅ 必须手动展开所有shapes（如Vitreus所示）
- ✅ 所有shapes必须在同一个body内才能真正融合

### 修改的文件：
- `modules/notches/frame.plm` - 重构为统一body，手动展开48个音乐柱子
- `modules/settings/panel.plm` - 修复drawer组件使用
- `modules/center/panel.plm` - 修复drawer组件使用  
- `modules/common/common.plm` - 简化组件结构

### 测试状态：
✅ 编译成功
✅ 运行正常
✅ 所有surface正确创建
✅ 无GPU过度占用
✅ Frame和音乐柱子作为整体融合

详细信息见 `CHANGES.md`

---

## 原始需求记录：

我用其他ai 实现 @reports/notches-four-side-frame-feasibility.md 功能，给了下面的提示:

注意：设置面板，中心面板，都需要实现像 原项目时间点击展开那种效果，吸附在顶部 位置，重要的是展开的那种水波衔接的效果，。2.音乐的frame 是四边都可以，然后可以设置只出现顶部，或者四边都开启这两种选项

然后还是有下面的问题，
你的还是有问题，我说了你为什么不直接复制参考的项目的 notches 的面板代码，你现在的notches 面板top 和四周的块单独分开的，然后这四边又跟 music 动画是分开的

现在你帮我去实现改动，参考项目目录在 /home/zerone/projects/Vitreus ，你可以去那个目录启动它截图参考
当前项目你改完也要启动去测试，截图等
