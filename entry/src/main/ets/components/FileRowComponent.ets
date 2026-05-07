import { FileItem } from '../model/FileItem';
import { DownloadEvent, DownloadStatus } from '../model/DownloadTask';
import { FileDownloadState, FileListViewModel } from '../viewmodel/FileListViewModel';
import { DownloadManager } from '../service/DownloadManager';
import { FileUtils } from '../utils/FileUtils';

@Component
export struct FileRowComponent {
  @Prop item: FileItem;
  @Prop isMultiSelectMode: boolean;
  @Prop selectionVersion: number;
  private onDownload?: (file: FileItem) => void;
  private onSelect?: (name: string) => void;
  private onNavigate?: (item: FileItem) => void;
  @State private downloadState: FileDownloadState | null = null;
  private downloadManager: DownloadManager = DownloadManager.getInstance();
  private eventHandler?: (event: DownloadEvent) => void;

  aboutToAppear(): void {
    const existing = this.downloadManager.getTaskByPath(this.item.relativePath);
    if (existing) {
      this.downloadState = {
        status: existing.status,
        progress: existing.progress
      };
    }
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

  aboutToDisappear(): void {
    if (this.eventHandler) {
      this.downloadManager.unsubscribe(this.eventHandler);
    }
  }

  build() {
    Row() {
      if (this.isMultiSelectMode) {
        Image(FileListViewModel.getInstance().selectedFiles.has(this.item.name) ?
          $r('app.media.ic_checkbox_selected') : $r('app.media.ic_checkbox_normal'))
          .width(24)
          .height(24)
          .margin({ right: 8 })
      }

      Image(this.item.type === 'dir' ? $r('app.media.ic_folder') : $r('app.media.ic_file'))
        .size({ width: 24, height: 25 })

      Column() {
        Text(this.item.name)
          .fontSize(16)
          .width('100%')
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .maxLines(1)

        Row() {
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

      if (this.item.type === 'file') {
        this.buildDownloadIndicator()
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      if (this.isMultiSelectMode) {
        this.onSelect?.(this.item.name)
      } else if (this.item.type === 'dir') {
        this.onNavigate?.(this.item)
      }
    })
  }

  @Builder
  buildDownloadIndicator() {
    if (this.downloadState !== null && this.downloadState.status === DownloadStatus.DOWNLOADING) {
      if (this.downloadState.indeterminate) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color('#09bb07')
      } else {
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
      Image($r('app.media.ic_complete'))
        .width(24)
        .height(24)
    } else if (this.downloadState !== null && this.downloadState.status === DownloadStatus.FAILED) {
      Image($r('app.media.ic_error'))
        .width(24)
        .height(24)
    } else if (!this.isMultiSelectMode) {
      Image($r('app.media.ic_download'))
        .width(24)
        .height(24)
        .onClick(() => {
          this.onDownload?.(this.item)
        })
    }
  }
}
