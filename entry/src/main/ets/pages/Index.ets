import { FileItem } from '../model/FileItem';
import { DownloadStatus, DownloadTask } from '../model/DownloadTask';
import { FileListViewModel } from '../viewmodel/FileListViewModel';
import { FileUtils } from '../utils/FileUtils';
import { LogUtil } from '../utils/LogUtil';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  @State fileList: FileItem[] = [];
  @State breadcrumbs: string[] = [''];
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State isMultiSelectMode: boolean = false;
  @State selectedFilesCount: number = 0;
  @State downloadTasks: DownloadTask[] = [];
  @State isRefreshing: boolean = false;
  @State isDownloadPanelExpanded: boolean = true;
  private viewModel: FileListViewModel = new FileListViewModel(() => {
    this.syncState();
  });

  aboutToAppear(): void {
    try {
      const ctx = getContext(this) as common.Context;
      FileUtils.init(ctx);
      LogUtil.info('Index page aboutToAppear, starting refresh');
    } catch (e) {
      LogUtil.error(`Index aboutToAppear error: ${e.message}`);
    }
    this.viewModel.refresh();
  }

  syncState(): void {
    this.fileList = this.viewModel.fileList;
    this.breadcrumbs = this.viewModel.breadcrumbs;
    this.isLoading = this.viewModel.isLoading;
    this.errorMessage = this.viewModel.errorMessage;
    this.isMultiSelectMode = this.viewModel.isMultiSelectMode;
    this.selectedFilesCount = this.viewModel.selectedFiles.size;
    this.downloadTasks = this.viewModel.downloadTasks;
    const completedFiles = this.viewModel.consumeRecentCompleted();
    for (const name of completedFiles) {
      promptAction.showToast({
        message: `${name} downloaded`,
        duration: 2000
      });
    }
  }

  build() {
    Column() {
      this.buildTopBar()
      if (this.isMultiSelectMode) {
        this.buildMultiSelectBar()
      }
      this.buildMainContent()
      if (this.downloadTasks.length > 0) {
        this.buildDownloadPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
  }

  @Builder
  buildTopBar() {
    Row() {
      if (this.breadcrumbs.length > 1) {
        Image($r('app.media.ic_back'))
          .width(32)
          .height(32)
          .onClick(() => {
            this.viewModel.goBack()
          })
      }

      Scroll() {
        Row() {
          ForEach(this.breadcrumbs, (segment: string, index: number) => {
            if (index > 0) {
              Text(' > ')
                .fontSize(14)
                .fontColor($r('sys.color.ohos_id_color_secondary'))
            }
            Text(segment === '' ? 'Root' : segment)
              .fontSize(14)
              .fontColor(index === this.breadcrumbs.length - 1
                ? $r('sys.color.ohos_id_color_primary')
                : $r('sys.color.ohos_id_color_secondary'))
              .onClick(() => {
                this.viewModel.navigateToBreadcrumb(index)
              })
          })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .flexGrow(1)

      Blank()

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Text(this.isMultiSelectMode ? '☑' : '☐')
          .fontSize(20)
      }
      .width(44)
      .height(44)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.viewModel.toggleMultiSelect()
      })
    }
    .width('100%')
    .height(48)
    .padding({ left: 8, right: 8 })
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  @Builder
  buildMultiSelectBar() {
    Row() {
      Button() {
        Text(this.selectedFilesCount === this.fileList.length
          ? 'Deselect All' : 'Select All')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_primary'))
      }
      .type(ButtonType.Normal)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        if (this.selectedFilesCount === this.fileList.length) {
          this.viewModel.deselectAll()
        } else {
          this.viewModel.selectAll()
        }
      })

      Blank()

      Text(`${this.selectedFilesCount} selected`)
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_secondary'))

      Blank()

      Button() {
        Text(`Download (${this.selectedFilesCount})`)
          .fontSize(14)
          .fontColor(Color.White)
      }
      .type(ButtonType.Capsule)
      .height(36)
      .backgroundColor(this.selectedFilesCount > 0
        ? $r('sys.color.ohos_id_color_primary')
        : $r('sys.color.ohos_id_color_foreground_contrary_disable'))
      .enabled(this.selectedFilesCount > 0)
      .onClick(() => {
        if (this.selectedFilesCount > 0) {
          this.viewModel.startBatchDownload()
          this.viewModel.toggleMultiSelect()
        }
      })
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  @Builder
  buildMainContent() {
    if (this.isLoading && this.fileList.length === 0) {
      Column() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color($r('sys.color.ohos_id_color_primary'))
        Text('Loading...')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_secondary'))
          .margin({ top: 12 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.errorMessage) {
      Column() {
        Text('⚠')
          .fontSize(48)
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_secondary'))
          .margin({ top: 12 })
        Button() {
          Text('Retry')
            .fontSize(14)
            .fontColor(Color.White)
        }
        .type(ButtonType.Capsule)
        .height(36)
        .margin({ top: 16 })
        .backgroundColor($r('sys.color.ohos_id_color_primary'))
        .onClick(() => {
          this.viewModel.refresh()
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.fileList.length === 0) {
      Column() {
        Text('📂')
          .fontSize(48)
        Text('Empty directory')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_secondary'))
          .margin({ top: 12 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      Refresh({ refreshing: $$this.isRefreshing }) {
        List() {
          ForEach(this.fileList, (item: FileItem) => {
            ListItem() {
              this.buildFileRow(item)
            }
          })
        }
        .width('100%')
        .height('100%')
        .divider({
          color: '#e5e5e5',
          strokeWidth: 1
        })
      }
      .onRefreshing(() => {
        this.isRefreshing = true;
        this.viewModel.refresh().then(() => {
          this.isRefreshing = false;
        }).catch(() => {
          this.isRefreshing = false;
        });
      })
    }
  }

  @Builder
  buildFileRow(item: FileItem) {
    Row() {
      if (this.isMultiSelectMode) {
        Checkbox({ name: item.name })
          .select(this.viewModel.selectedFiles.has(item.name))
          .selectedColor($r('sys.color.ohos_id_color_primary'))
          .onChange(() => {
            this.viewModel.toggleSelect(item.name)
          })
          .margin({ right: 8 })
      }

      Image(item.type === 'dir' ? $r('app.media.ic_folder') : $r('app.media.ic_file'))
        .size({ width: 24, height: 25 })

      Column() {
        Text(item.name)
          .fontSize(16)
          .width('100%')
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .maxLines(1)

        Row() {
          Text(FileUtils.formatFileSize(item.size))
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_secondary'))
          Text('  ')
          Text(FileUtils.formatDate(item.mtime))
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_secondary'))
        }
        .width('100%')
      }
      .layoutWeight(1)
      .margin({ left: 8, right: 8 })

      if (item.type === 'file') {
        Image($r('app.media.ic_download'))
          .width(24)
          .height(24)
          .onClick(() => {
            this.viewModel.startDownload(item)
          })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      if (this.isMultiSelectMode) {
        this.viewModel.toggleSelect(item.name)
      } else if (item.type === 'dir') {
        this.viewModel.navigateToDir(item)
      }
    })
  }

  @Builder
  buildDownloadPanel() {
    Column() {
      Row() {
        Text(`Downloads (${this.downloadTasks.length})`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)

        Blank()

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text(this.isDownloadPanelExpanded ? '▼' : '▲')
            .fontSize(14)
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.isDownloadPanelExpanded = !this.isDownloadPanelExpanded
        })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text('Cancel All')
            .fontSize(12)
            .fontColor(Color.Red)
        }
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.viewModel.cancelAllTasks()
        })
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 4 })

      if (this.isDownloadPanelExpanded) {
        List() {
          ForEach(this.downloadTasks, (task: DownloadTask) => {
            ListItem() {
              this.buildDownloadTaskRow(task)
            }
          })
        }
        .height(160)
        .width('100%')
      }
    }
    .width('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .borderRadius({ topLeft: 12, topRight: 12 })
  }

  @Builder
  buildDownloadTaskRow(task: DownloadTask) {
    Row() {
      Text(task.file.name)
        .fontSize(13)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(1)
        .layoutWeight(1)

      if (task.status === DownloadStatus.DOWNLOADING) {
        Progress({ value: task.progress, total: 100 })
          .width(80)
          .height(6)
          .margin({ left: 8, right: 8 })
        Text(`${task.progress}%`)
          .fontSize(12)
      } else if (task.status === DownloadStatus.COMPLETED) {
        Text('✓')
          .fontSize(16)
          .fontColor(Color.Green)
          .margin({ left: 8 })
      } else if (task.status === DownloadStatus.FAILED) {
        Text('✗')
          .fontSize(16)
          .fontColor(Color.Red)
          .margin({ left: 8 })
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text('Retry')
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_primary'))
        }
        .height(28)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.viewModel.retryTask(task.id)
        })
      } else if (task.status === DownloadStatus.WAITING) {
        Text('Waiting...')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_secondary'))
      }

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Text('✕')
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_secondary'))
      }
      .width(28)
      .height(28)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.viewModel.cancelTask(task.id)
      })
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 4 })
  }
}
