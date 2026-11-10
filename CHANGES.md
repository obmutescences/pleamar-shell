# Pleamar 0.8-exp adoption

- The flake follows the upstream `exp2` branch; the lockfile currently pins
  `aeaad83770ae3f9ace6c64395422bba67e0aeddd` (`0.8.0-exp.1`).
- The audio output picker is now a real `popup` with `keyboard: true`, so it
  owns its layer, closes on Escape/outside click, and can frost the centre
  panel underneath.
- The centre pages take a `blur: 3` group effect while a modal is open, giving
  the dialog focus without a second full-screen surface.
- Alpha colours (`#00000075`) replace a separate black box plus opacity.
- The destructive power confirmation is marked `agent: no`.
- Engine-level 0.8 behaviour also applies without scene changes: glass frosts
  what the same scene painted under it, popups get their own surface, and text
  fields gain IME and undo/redo.

---

# Notches Frame Music Visualization - Implementation Complete

## ✅ 完成的修改

### 关键发现：Pleamar不支持在body内使用repeat！

**重要：** 与Vitreus一样，所有音乐柱子必须手动展开（不能使用repeat循环），因为pleamar语言不允许在body块内部使用repeat结构。

### 1. 修改了 `modules/notches/frame.plm`

**架构改进：**
- ✅ 所有shapes（frame、drawers、music bars）在**同一个body**内
- ✅ 音乐柱子手动展开为48个box（每边12个 × 4边）
- ✅ 使用`blend: 14`参数实现液体玻璃融合效果
- ✅ 通过`if(..., 0, 30000)`移动不活跃的柱子到屏幕外

**实现细节：**
- 顶部边缘：12个柱子，避开时钟notch区域
- 底部边缘：12个柱子（仅在all_sides模式）
- 左边缘：12个柱子（仅在all_sides模式）
- 右边缘：12个柱子（仅在all_sides模式）

每个柱子：
- 基于6个音频频段（band.s.0 到 band.s.5）
- 动态高度响应音乐
- 与frame无缝融合（blend参数）
- 静默时自动隐藏（移动到30000px外）

### 2. 修改了 `modules/settings/panel.plm` 和 `modules/center/panel.plm`

**修复：**
- 移除了 `NotchDrawer` 组件的调用
- 直接使用 `NotchDrawerRipples` 和 `NotchDrawerContent`
- 保持了drawer展开的水波衔接效果

### 3. 简化了 `modules/common/common.plm`

**修复：**
- 移除了有问题的 `NotchDrawer` 组件
- 保留了 `NotchDrawerContent` 和 `NotchDrawerRipples`供frame使用

## 架构对比

### Vitreus的实现：
```plm
body {
    glass: 100%
    // frame shapes
    box { ... }
    // drawer shapes
    box { ... }
    // 手动展开的音乐柱子（无repeat）
    box { at: fwx_0, fwy_0; blend: fw.bl }
    box { at: fwx_1, fwy_1; blend: fw.bl }
    // ... 共47个
}
```

### 当前实现（已修复）：
```plm
body {
    glass: if(glass_on, 100%, 0%)
    // frame rails和corners
    box { ... }
    // drawer silhouettes
    box { ... }
    // 手动展开的音乐柱子（无repeat）
    box { at: nf.w * 0.5 / 12; size: nf.bw, nf.level0; blend: 14 }
    box { at: nf.w * 1.5 / 12; size: nf.bw, nf.level0; blend: 14 }
    // ... 共48个（每边12个 × 4边）
}
```

## 测试状态

✅ 编译成功  
✅ Pleamar成功启动  
✅ 所有surface正确创建  
✅ 无GPU过度占用（统一body优化）  
✅ Frame和音乐柱子作为整体融合

## 配置选项

在 `modules/common/common.plm` 中：
- `music_frame_on = true` - 启用/禁用音乐frame
- `music_frame_sides: number = 1` - 0=仅顶部，1=四边

## 性能优化

通过将所有shapes放在同一个body内：
- ✅ 减少了GPU层数（从49个body减少到1个）
- ✅ 降低了渲染开销
- ✅ 实现了真正的液体玻璃融合效果
- ✅ 避免了多个独立glass body的计算成本
