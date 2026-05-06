# FileRowComponent 独立订阅下载进度 — 设计规范

## 问题概述

点击下载按钮后，`ApiService.systemDownload` 的 `task.on('progress', ...)` 回调正常触发并计算进度百分比，但 `Index.ets` 界面上的 `Progress` 组件未更新。

### 根因

`Index.ets` 中列表行内容通过 `ForEach` + `@Builder` 实现：

```
ForEach(this.fileList, (item) => {
  ListItem() { this.buildFileRow(item) }
})
```

`buildFileRow` 内部调用 `buildDownloadIndicator(this.fileDownloadStates[item.relativePath], item)`。在 ArkUI 中，`ForEach` 在数组未变化时不重新评估已有项的生成器（即 `buildFileRow` 函数体不被重新调用），因此 `buildDownloadIndicator` 拿到的 `state` 参数是初始捕获值，无法响应后续 `@State fileDownloadStates` 的更新。

## 设计方案

### 核心思路

将列表行抽取为独立 `@Component`（`FileRowComponent`），在 `aboutToAppear` 时直接订阅 `DownloadManager` 事件。各列表项独立的 `@State downloadState` 由订阅回调驱动更新，彻底绕过 `ForEach` 的参数传递链路。

### 文件结构变更

| 文件 | 操作 |
|------|------|
| `entry/src/main/ets/components/FileRowComponent.ets` | **新增** — 列表行自定义组件 |
| `entry/src/main/ets/pages/Index.ets` | **修改** — ForEach 内替换为 FileRowComponent，移除旧 @Builder |

### FileRowComponent 设计

```typescript
@Component
struct FileRowComponent {
  @Prop item: FileItem
  @Prop isMultiSelectMode: boolean
  @Prop isSelected: boolean
  private onDownload?: (file: FileItem) => void
  private onSelect?: (name: string) => void
  private onNavigate?: (item: FileItem) => void

  @State private downloadState: FileDownloadState | null = null
  private downloadManager: DownloadManager = DownloadManager.getInstance()
  private eventHandler: (event: DownloadEvent) => void = () => {}
```

#### 生命周期

- `aboutToAppear`：订阅 DownloadManager，同时检查该文件是否已有下载任务
- `aboutToDisappear`：取消订阅

#### 事件处理

```typescript
aboutToAppear(): void {
  this.eventHandler = (event: DownloadEvent) => {
    if (event.task.file.relativePath === this.item.relativePath) {
      this.downloadState = {
        status: event.task.status,
        progress: event.task.progress
      }
    }
  }
  this.downloadManager.subscribe(this.eventHandler)
}

aboutToDisappear(): void {
  this.downloadManager.unsubscribe(this.eventHandler)
}
```

#### 渲染逻辑

将原有 `buildFileRow` + `buildDownloadIndicator` 的内容移入 `build()`：

- 多选模式下显示 Checkbox
- 文件/文件夹图标
- 文件名、大小、日期
- 下载状态指示器（Progress Ring / 完成 ✓ / 失败 ✗ / 下载按钮）
- 行点击事件处理

#### 下载按钮点击

```typescript
// 触发委托给父组件传递的 onDownload 回调
this.onDownload?.(this.item)
```

### Index.ets 修改

#### ForEach 替换

```typescript
ForEach(this.fileList, (item: FileItem) => {
  ListItem() {
    FileRowComponent({
      item: item,
      isMultiSelectMode: this.isMultiSelectMode,
      isSelected: this.viewModel.selectedFiles.has(item.name),
      onDownload: (file) => { this.viewModel.startDownload(file) },
      onSelect: (name) => { this.viewModel.toggleSelect(name) },
      onNavigate: (dir) => { this.viewModel.navigateToDir(dir) }
    })
  }
})
```

#### 移除内容

- `syncState()` 中移除 `fileDownloadStates` 的同步（由组件自行管理）
- 移除 `@State fileDownloadStates` 声明
- 移除 `buildFileRow`、`buildDownloadIndicator`、`getFileDownloadState` 三个 `@Builder`
- 移除 `buildMultiSelectBar` 中的批量进度显示（仍保留，但数据来自 ViewModel.batchState）

#### 保留内容

- `@State batchState` 仍保留，用于 `buildMultiSelectBar` 中的批量下载进度显示
- `ViewModel.batchState` 同步逻辑不受影响

### 数据流

```
DownloadManager.notify()
  → FileRowComponent.eventHandler()
    → this.downloadState = { status, progress }  (@State 更新)
      → ArkUI 自动重渲染 ⭕Progress / ✓ / ✗
```

### 边界处理

- 组件未出现在可视区时不会被创建（`ForEach` + `ListItem` 懒加载），不消耗订阅资源
- 组件销毁时通过 `aboutToDisappear` 取消订阅，避免内存泄漏
- 文件列表刷新重建时，旧组件全部销毁并取消订阅，新组件重新订阅

### 性能分析

- 每个可见列表项有一个订阅回调
- `DownloadManager.notify` 使用 `Set.forEach` 同步遍历，数十个订阅者无性能问题
- 进度事件频率受限于 `request.downloadFile` 的回调，不会高频触发

## 回退方案

若组件订阅方案因不可预见的 ArkUI 限制导致问题，可回退为：

1. 恢复 `fileDownloadStates` 同步
2. 修改 `ForEach` 的 `keyGenerator` 使其包含下载进度状态，强制重建
3. 或使用 `@ObjectLink` + `@Observed` 方案
