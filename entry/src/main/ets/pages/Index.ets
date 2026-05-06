import { FileItem } from '../model/FileItem';
import { DownloadStatus } from '../model/DownloadTask';
import { FileDownloadState, FileListViewModel } from '../viewmodel/FileListViewModel';
import { FileUtils } from '../utils/FileUtils';
import { LogUtil } from '../utils/LogUtil';
import { ObjectUtil } from '../utils/ObjectUtil';
import { ApiService } from '../service/ApiService';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct Index {
  @State fileList: FileItem[] = [];
  @State breadcrumbs: string[] = [''];
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State isMultiSelectMode: boolean = false;
  @State selectedFilesCount: number = 0;
  @State isRefreshing: boolean = false;
  @State fileDownloadStates: Record<string, FileDownloadState> = {};
  @State batchState: FileDownloadState | null = null;
  private viewModel: FileListViewModel = new FileListViewModel(() => {
    this.syncState();
  });

  aboutToAppear(): void {
    try {
      const ctx = getContext(this) as common.Context;
      FileUtils.init(ctx);
      ApiService.setContext(ctx);
      LogUtil.info('Index page aboutToAppear, starting refresh');
    } catch (e) {
      LogUtil.error(`Index aboutToAppear error: ${e.message}`);
    }
    this.viewModel.refresh();
  }

  syncState(): void {
    this.fileList = this.viewModel.fileList.slice();
    this.breadcrumbs = this.viewModel.breadcrumbs;
    this.isLoading = this.viewModel.isLoading;
    this.errorMessage = this.viewModel.errorMessage;
    this.isMultiSelectMode = this.viewModel.isMultiSelectMode;
    this.selectedFilesCount = this.viewModel.selectedFiles.size;
    this.fileDownloadStates = ObjectUtil.cloneRecord(this.viewModel.fileDownloadStates);
    this.batchState = this.viewModel.batchState;
  }

  build() {
    Column() {
      this.buildTopBar()
      if (this.isMultiSelectMode) {
        this.buildMultiSelectBar()
      }
      this.buildMainContent()
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
          .width(28)
          .height(28)
          .onClick(() => {
            this.viewModel.goBack()
          })
      }

      Scroll() {
        Row() {
          ForEach(this.breadcrumbs, (segment: string, index: number) => {
            if (index > 0) {
              Text('/')
                .fontSize(14)
                .fontColor($r('sys.color.ohos_id_color_secondary'))
            }
            Text(segment === '' ? '根目录' : segment)
              .fontSize(14)
              .fontColor(index === this.breadcrumbs.length - 1
                ? $r('sys.color.ohos_id_color_primary')
                : $r('sys.color.ohos_id_color_secondary'))
              .onClick(() => {
                this.viewModel.navigateToBreadcrumb(index)
              })
          })
        }
        .width('100%')
        .padding({ left: 10, right: 10 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .flexGrow(1)
      .layoutWeight(1)

      Blank()

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Text(this.isMultiSelectMode ? '取消' : '多选')
          .fontSize(16)
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
          ? '取消全选' : '全选')
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

      Text(`已选 ${this.selectedFilesCount} 项`)
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_secondary'))

      Blank()

      if (this.batchState && this.batchState.status === DownloadStatus.DOWNLOADING) {
        Stack() {
          Progress({ value: this.batchState.progress, total: 100, type: ProgressType.Ring })
            .width(36)
            .height(36)
            .style({ strokeWidth: 4 })
            .color($r('sys.color.ohos_id_color_primary'))
          Text(`${this.batchState.progress}%`)
            .fontSize(10)
            .fontColor($r('sys.color.ohos_id_color_primary'))
        }
        .width(44)
        .height(44)
      } else if (this.batchState && this.batchState.status === DownloadStatus.COMPLETED) {
        Text('✓')
          .fontSize(20)
          .fontColor(Color.Green)
          .width(44)
          .height(44)
      } else if (this.batchState && this.batchState.status === DownloadStatus.FAILED) {
        Text('✗')
          .fontSize(20)
          .fontColor(Color.Red)
          .width(44)
          .height(44)
      } else if (this.selectedFilesCount > 0) {
        Button() {
          Text(`下载 (${this.selectedFilesCount})`)
            .fontSize(14)
            .fontColor(Color.White)
        }
        .type(ButtonType.Capsule)
        .height(36)
        .padding({ left: 8, right: 8 })
        .backgroundColor($r('sys.color.ohos_id_color_primary'))
        .onClick(() => {
          this.viewModel.startBatchDownload()
        })
      } else {
        Button() {
          Text('下载')
            .fontSize(14)
            .fontColor(Color.White)
        }
        .type(ButtonType.Capsule)
        .height(36)
        .padding({ left: 8, right: 8 })
        .backgroundColor($r('sys.color.ohos_id_color_foreground_contrary_disable'))
        .enabled(false)
      }
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
        Text('加载中...')
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
          Text('重试')
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
        Image($r('app.media.ic_empty'))
          .width(64)
          .height(64)

        Text('暂无文件')
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
          .key(`cb_${item.name}_${this.viewModel.selectedFiles.has(item.name)}`)
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
        this.buildDownloadIndicator(this.fileDownloadStates[item.relativePath], item)
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

  getFileDownloadState(relativePath: string): FileDownloadState | undefined {
    return this.fileDownloadStates[relativePath];
  }

  @Builder
  buildDownloadIndicator(state: FileDownloadState | undefined, item: FileItem) {
    if (state !== undefined && state.status === DownloadStatus.DOWNLOADING) {
      Stack() {
        Progress({ value: state.progress, total: 100, type: ProgressType.Ring })
          .width(28)
          .height(28)
          .style({ strokeWidth: 3 })
          .color($r('sys.color.ohos_id_color_primary'))
        Text(`${state.progress}%`)
          .fontSize(9)
          .fontColor($r('sys.color.ohos_id_color_primary'))
      }
      .width(28)
      .height(28)
    } else if (state !== undefined && state.status === DownloadStatus.COMPLETED) {
      Text('✓')
        .fontSize(18)
        .fontColor(Color.Green)
        .width(28)
        .height(28)
    } else if (state !== undefined && state.status === DownloadStatus.FAILED) {
      Text('✗')
        .fontSize(18)
        .fontColor(Color.Red)
        .width(28)
        .height(28)
    } else {
      Image($r('app.media.ic_download'))
        .width(24)
        .height(24)
        .onClick(() => {
          this.viewModel.startDownload(item)
        })
    }
  }
}
