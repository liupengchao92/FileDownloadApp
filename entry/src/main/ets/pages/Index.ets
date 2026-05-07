import { FileItem } from '../model/FileItem';
import { DownloadStatus } from '../model/DownloadTask';
import { FileDownloadState, FileListViewModel } from '../viewmodel/FileListViewModel';
import { FileRowComponent } from '../components/FileRowComponent';
import { FileUtils } from '../utils/FileUtils';
import { LogUtil } from '../utils/LogUtil';
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
  @State selectionVersion: number = 0;
  @State batchState: FileDownloadState | null = null;
  private viewModel: FileListViewModel = FileListViewModel.create(() => {
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
    this.selectionVersion = this.viewModel.selectionVersion;
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
        if (this.batchState.indeterminate) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color('#09bb07')
        } else if (this.batchState.phase === 'extract') {
          Stack() {
            Progress({ value: this.batchState.progress, total: 100, type: ProgressType.Ring })
              .width(36)
              .height(36)
              .style({ strokeWidth: 4 })
              .color('#09bb07')
            Text('解压...')
              .fontSize(10)
              .fontColor('#09bb07')
          }
          .width(44)
          .height(44)
        } else {
          Stack() {
            Progress({ value: this.batchState.progress, total: 100, type: ProgressType.Ring })
              .width(36)
              .height(36)
              .style({ strokeWidth: 4 })
              .color('#09bb07')
            Text(`${this.batchState.progress}%`)
              .fontSize(10)
              .fontColor('#09bb07')
          }
          .width(44)
          .height(44)
        }
      } else if (this.batchState && this.batchState.status === DownloadStatus.COMPLETED) {
        Image($r('app.media.ic_complete'))
          .width(24)
          .height(24)
      } else if (this.batchState && this.batchState.status === DownloadStatus.FAILED) {
        Image($r('app.media.ic_error'))
          .width(24)
          .height(24)
      } else if (this.selectedFilesCount > 0) {
        Button(`下载 (${this.selectedFilesCount})`)
        .fontSize(14)
        .fontColor(Color.White)
        .height(32)
        .padding({ left: 8, right: 8 })
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
              FileRowComponent({
                item: item,
                isMultiSelectMode: this.isMultiSelectMode,
                selectionVersion: this.selectionVersion,
                onDownload: (file: FileItem) => { this.viewModel.startDownload(file) },
                onSelect: (name: string) => { this.viewModel.toggleSelect(name) },
                onNavigate: (dir: FileItem) => { this.viewModel.navigateToDir(dir) }
              })
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


}
