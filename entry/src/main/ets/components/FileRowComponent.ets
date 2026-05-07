import { FileItem } from '../model/FileItem';
import { DownloadEvent, DownloadStatus } from '../model/DownloadTask';
import { FileDownloadState, FileListViewModel } from '../viewmodel/FileListViewModel';
import { DownloadManager } from '../service/DownloadManager';
import { FileUtils } from '../utils/FileUtils';

/**
 * 文件列表行组件
 * 渲染单个文件/文件夹的信息行，包括：
 * - 多选模式下的复选框
 * - 文件夹/文件图标
 * - 文件名、大小、修改时间
 * - 文件的下载状态指示器（下载中显示进度环、完成显示勾、失败显示叉）
 *
 * 通过订阅 DownloadManager 事件实时更新下载状态
 */
@Component
export struct FileRowComponent {
  /** 文件/文件夹数据 */
  @Prop item: FileItem;
  /** 是否处于多选模式 */
  @Prop isMultiSelectMode: boolean;
  /** 选中状态版本号（用于触发响应式更新） */
  @Prop selectionVersion: number;
  /** 下载按钮点击回调 */
  private onDownload?: (file: FileItem) => void;
  /** 多选勾选回调 */
  private onSelect?: (name: string) => void;
  /** 目录点击导航回调 */
  private onNavigate?: (item: FileItem) => void;
  /** 当前文件的下载状态（null 表示无下载任务） */
  @State private downloadState: FileDownloadState | null = null;
  private downloadManager: DownloadManager = DownloadManager.getInstance();
  /** 事件处理器引用，用于 aboutToDisappear 时取消订阅 */
  private eventHandler?: (event: DownloadEvent) => void;

  /**
   * 组件生命周期：即将出现
   * 恢复已有任务的下载状态，并订阅 DownloadManager 事件
   */
  aboutToAppear(): void {
    // 检查是否有进行中的下载任务（组件重建时恢复状态）
    const existing = this.downloadManager.getTaskByPath(this.item.relativePath);
    if (existing) {
      this.downloadState = {
        status: existing.status,
        progress: existing.progress
      };
    }
    // 注册事件处理器：仅处理与当前文件路径匹配的事件
    this.eventHandler = (event: DownloadEvent) => {
      if (event.task.file.relativePath === this.item.relativePath) {
        this.downloadState = {
          status: event.task.status,
          progress: event.task.progress
        };
      }
    };
    this.downloadManager.subscribe(this.eventHandler);
  }

  /**
   * 组件生命周期：即将销毁
   * 取消订阅 DownloadManager 事件，避免内存泄漏
   */
  aboutToDisappear(): void {
    if (this.eventHandler) {
      this.downloadManager.unsubscribe(this.eventHandler);
    }
  }

  build() {
    Row() {
      // 多选模式下显示复选框
      if (this.isMultiSelectMode) {
        Image(FileListViewModel.getInstance().selectedFiles.has(this.item.name) ?
          $r('app.media.ic_checkbox_selected') : $r('app.media.ic_checkbox_normal'))
          .width(24)
          .height(24)
          .margin({ right: 8 })
      }

      // 文件夹/文件图标
      Image(this.item.type === 'dir' ? $r('app.media.ic_folder') : $r('app.media.ic_file'))
        .size({ width: 24, height: 25 })

      // 文件名和元信息区域
      Column() {
        Text(this.item.name)
          .fontSize(16)
          .width('100%')
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .maxLines(1)

        Row() {
          // 仅文件显示大小
          if (this.item.type !== 'dir') {
            Text(FileUtils.formatFileSize(this.item.size))
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_secondary'))
            Text('  ')
          }

          Text(FileUtils.formatDate(this.item.mtime))
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_secondary'))
        }
        .width('100%')
      }
      .layoutWeight(1)
      .margin({ left: 8, right: 8 })

      // 仅文件显示下载状态指示器
      if (this.item.type === 'file') {
        this.buildDownloadIndicator()
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      if (this.isMultiSelectMode) {
        // 多选模式：点击切换选中状态
        this.onSelect?.(this.item.name)
      } else if (this.item.type === 'dir') {
        // 非多选模式：点击文件夹进入导航
        this.onNavigate?.(this.item)
      }
    })
  }

  /**
   * 构建下载状态指示器
   * 根据 downloadState 渲染不同的 UI：
   * - DOWNLOADING：进度环 + 百分比文字（或不确定进度的 LoadingProgress）
   * - COMPLETED：完成勾图标
   * - FAILED：错误叉图标
   * - 默认（无状态）：下载按钮图标
   */
  @Builder
  buildDownloadIndicator() {
    if (this.downloadState !== null && this.downloadState.status === DownloadStatus.DOWNLOADING) {
      if (this.downloadState.indeterminate) {
        // 不确定进度：显示旋转加载动画
        LoadingProgress()
          .width(28)
          .height(28)
          .color('#09bb07')
      } else {
        // 确定进度：显示环形进度条 + 百分比文字
        Stack() {
          Progress({ value: this.downloadState.progress, total: 100, type: ProgressType.Ring })
            .width(28)
            .height(28)
            .style({ strokeWidth: 3 })
            .color('#09bb07')
          Text(`${this.downloadState.progress}%`)
            .fontSize(9)
            .fontColor('#09bb07')
        }
        .width(28)
        .height(28)
      }
    } else if (this.downloadState !== null && this.downloadState.status === DownloadStatus.COMPLETED) {
      // 下载完成：显示绿色勾
      Image($r('app.media.ic_complete'))
        .width(24)
        .height(24)
    } else if (this.downloadState !== null && this.downloadState.status === DownloadStatus.FAILED) {
      // 下载失败：显示红色叉
      Image($r('app.media.ic_error'))
        .width(24)
        .height(24)
    } else if (!this.isMultiSelectMode) {
      // 默认状态（非多选模式）：显示下载按钮，点击触发下载
      Image($r('app.media.ic_download'))
        .width(24)
        .height(24)
        .onClick(() => {
          this.onDownload?.(this.item)
        })
    }
  }
}
