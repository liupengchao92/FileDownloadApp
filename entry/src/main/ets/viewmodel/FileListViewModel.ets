import { FileItem, FileListResponse } from '../model/FileItem';
import { DownloadStatus, DownloadEvent } from '../model/DownloadTask';
import { ApiService } from '../service/ApiService';
import { DownloadManager } from '../service/DownloadManager';
import { FileUtils } from '../utils/FileUtils';
import { LogUtil } from '../utils/LogUtil';
import { promptAction } from '@kit.ArkUI';
import { ObjectUtil } from '../utils/ObjectUtil';

/**
 * 文件下载状态（UI 层使用）
 * 记录单个文件或批量任务的当前下载状态，用于驱动 UI 渲染
 */
export interface FileDownloadState {
  /** 下载状态 */
  status: DownloadStatus;
  /** 进度百分比（0-100） */
  progress: number;
  /** 是否为不确定进度 */
  indeterminate?: boolean;
  /** 批量下载阶段：'download' / 'extract' */
  phase?: string;
}

/**
 * 文件列表 ViewModel
 * 作为页面的核心状态管理器，协调 UI、API 和下载管理器之间的交互
 * 职责：
 * - 管理文件列表数据和目录导航（面包屑）
 * - 管理多选模式和选中状态
 * - 发起下载任务并订阅 DownloadManager 事件更新 UI 状态
 */
export class FileListViewModel {
  static instance: FileListViewModel | null = null;

  /**
   * 创建 ViewModel 实例并注册为单例
   * @param onUpdate 状态变更回调，触发 ArkUI 页面重新渲染
   */
  static create(onUpdate: () => void): FileListViewModel {
    const vm = new FileListViewModel(onUpdate);
    FileListViewModel.instance = vm;
    return vm;
  }

  static getInstance(): FileListViewModel {
    return FileListViewModel.instance!;
  }

  /** 当前浏览的目录路径（空字符串表示根目录） */
  currentPath: string = '';
  /** 面包屑路径段数组，第一项固定为空字符串（代表根目录） */
  breadcrumbs: string[] = [''];
  /** 当前目录下的文件/文件夹列表 */
  fileList: FileItem[] = [];
  /** 是否正在加载文件列表 */
  isLoading: boolean = false;
  /** 加载失败时的错误信息 */
  errorMessage: string = '';
  /** 是否处于多选模式 */
  isMultiSelectMode: boolean = false;
  /** 多选模式下选中的文件名集合 */
  selectedFiles: Set<string> = new Set();
  /** 选中状态版本号，用于触发 ArkUI 响应式更新 */
  selectionVersion: number = 0;
  /** 各文件的下载状态映射表（key 为 relativePath） */
  fileDownloadStates: Record<string, FileDownloadState> = {};
  /** 批量下载的状态（null 表示无批量下载进行中） */
  batchState: FileDownloadState | null = null;

  private onUpdate: () => void;
  private api: ApiService;
  private downloadManager: DownloadManager;

  constructor(onUpdate: () => void) {
    this.onUpdate = onUpdate;
    this.api = ApiService.getInstance();
    this.downloadManager = DownloadManager.getInstance();
    LogUtil.info('FileListViewModel created');

    // 订阅 DownloadManager 的事件，将下载状态同步到 UI 层
    this.downloadManager.subscribe((event: DownloadEvent) => {
      const task = event.task;

      if (task.batchInfo) {
        // 批量下载任务：更新 batchState
        this.batchState = {
          status: task.status,
          progress: task.progress,
          indeterminate: task.indeterminate,
          phase: task.batchInfo?.phase
        };
        if (task.status === DownloadStatus.COMPLETED) {
          promptAction.showToast({ message: `批量下载完成`, duration: 2000 });
          // 2 秒后清除批量状态并退出多选模式
          setTimeout(() => {
            this.batchState = null;
            this.isMultiSelectMode = false;
            this.selectedFiles.clear();
            this.selectionVersion++;
            this.onUpdate();
          }, 2000);
        } else if (task.status === DownloadStatus.FAILED) {
          promptAction.showToast({ message: `批量下载失败`, duration: 2000 });
          setTimeout(() => {
            this.batchState = null;
            this.onUpdate();
          }, 2000);
        }
      } else {
        // 单文件任务：更新 fileDownloadStates 中对应文件的状态
        const path = task.file.relativePath;
        this.fileDownloadStates[path] = {
          status: task.status,
          progress: task.progress,
          indeterminate: task.indeterminate
        };
        if (task.status === DownloadStatus.COMPLETED) {
          promptAction.showToast({ message: `${task.file.name} 下载完成`, duration: 2000 });
          // 2 秒后从下载状态映射中移除（恢复为普通显示）
          setTimeout(() => {
            this.fileDownloadStates = ObjectUtil.removeKey(this.fileDownloadStates, path);
            this.onUpdate();
          }, 2000);
        } else if (task.status === DownloadStatus.FAILED) {
          promptAction.showToast({ message: `${task.file.name} 下载失败`, duration: 2000 });
          setTimeout(() => {
            this.fileDownloadStates = ObjectUtil.removeKey(this.fileDownloadStates, path);
            this.onUpdate();
          }, 2000);
        }
      }
      // 克隆 Record 对象以触发 ArkUI 的响应式更新
      this.fileDownloadStates = ObjectUtil.cloneRecord(this.fileDownloadStates);
      this.onUpdate();
    });
  }

  /**
   * 刷新当前目录的文件列表
   * 调用 ApiService 获取最新数据并重建 fileList
   */
  async refresh(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    this.onUpdate();
    LogUtil.info(`[VM] refresh currentPath: "${this.currentPath}"`);

    try {
      const response = await this.api.getFileList(this.currentPath);
      this.buildFileList(response);
      this.errorMessage = '';
      LogUtil.info(`[VM] refresh success, files: ${this.fileList.length}`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to load file list';
      this.errorMessage = msg;
      LogUtil.error(`[VM] refresh failed: ${msg}`);
    } finally {
      this.isLoading = false;
      this.onUpdate();
    }
  }

  /**
   * 导航进入子目录
   * @param dir 目标文件夹的 FileItem
   */
  async navigateToDir(dir: FileItem): Promise<void> {
    LogUtil.info(`[VM] navigateToDir: ${dir.name} (${dir.relativePath})`);
    this.currentPath = dir.relativePath;
    this.updateBreadcrumbs();
    await this.refresh();
  }

  /**
   * 点击面包屑导航到指定层级
   * @param index 面包屑索引（0 为根目录）
   */
  navigateToBreadcrumb(index: number): void {
    if (index < 0 || index >= this.breadcrumbs.length) {
      return;
    }
    // 拼接从根目录到目标层级的路径
    const segments: string[] = [];
    for (let i = 1; i <= index; i++) {
      segments.push(this.breadcrumbs[i]);
    }
    this.currentPath = segments.join('/');
    LogUtil.info(`[VM] navigateToBreadcrumb: ${index} -> path="${this.currentPath}"`);
    this.updateBreadcrumbs();
    this.refresh();
  }

  /** 返回上级目录 */
  goBack(): void {
    if (this.breadcrumbs.length <= 1) {
      return;
    }
    // 移除面包屑最后一级，重新拼接路径
    const newBreadcrumbs = this.breadcrumbs.slice(0, -1);
    const segments: string[] = [];
    for (let i = 1; i < newBreadcrumbs.length; i++) {
      segments.push(newBreadcrumbs[i]);
    }
    this.currentPath = segments.join('/');
    LogUtil.info(`[VM] goBack -> path="${this.currentPath}"`);
    this.updateBreadcrumbs();
    this.refresh();
  }

  /** 切换多选模式（开启/关闭） */
  toggleMultiSelect(): void {
    this.isMultiSelectMode = !this.isMultiSelectMode;
    if (!this.isMultiSelectMode) {
      // 退出多选模式时清空选中状态
      this.selectedFiles.clear();
      this.selectionVersion++;
    }
    LogUtil.info(`[VM] toggleMultiSelect: ${this.isMultiSelectMode}`);
    this.onUpdate();
  }

  /** 切换指定文件的选中状态 */
  toggleSelect(fileName: string): void {
    if (this.selectedFiles.has(fileName)) {
      this.selectedFiles.delete(fileName);
    } else {
      this.selectedFiles.add(fileName);
    }
    this.selectionVersion++;
    this.onUpdate();
  }

  /** 全选当前目录下的所有文件 */
  selectAll(): void {
    for (const item of this.fileList) {
      this.selectedFiles.add(item.name);
    }
    this.selectionVersion++;
    this.onUpdate();
  }

  /** 取消全选 */
  deselectAll(): void {
    this.selectedFiles.clear();
    this.selectionVersion++;
    this.onUpdate();
  }

  /**
   * 发起单文件下载
   * 计算本地目标路径后委托给 DownloadManager
   * @param file 要下载的文件
   */
  startDownload(file: FileItem): void {
    LogUtil.info(`[VM] startDownload: ${file.name}`);
    // 将服务端相对路径转换为本地沙盒绝对路径
    const targetPath = FileUtils.buildLocalPath(file.relativePath);
    this.downloadManager.addTask(file, targetPath);
    this.onUpdate();
  }

  /**
   * 发起批量下载
   * 收集所有选中的文件，委托给 DownloadManager 创建批量任务
   */
  async startBatchDownload(): Promise<void> {
    const files: FileItem[] = [];
    for (const item of this.fileList) {
      if (this.selectedFiles.has(item.name)) {
        files.push(item);
      }
    }
    LogUtil.info(`[VM] startBatchDownload: ${files.length} items selected`);
    if (files.length > 0) {
      this.downloadManager.addBatch(files);
      this.onUpdate();
    }
  }

  /**
   * 根据 currentPath 更新面包屑数组
   * 将路径按 '/' 分割为段，第一项固定为空字符串（代表根目录）
   */
  private updateBreadcrumbs(): void {
    if (!this.currentPath) {
      this.breadcrumbs = [''];
      return;
    }
    this.breadcrumbs = [''];
    const segments = this.currentPath.split('/');
    for (const seg of segments) {
      if (seg) {
        this.breadcrumbs.push(seg);
      }
    }
  }

  /**
   * 将接口响应转换为 UI 使用的 FileItem 数组
   * 为每个文件拼接完整的 relativePath
   */
  private buildFileList(response: FileListResponse): void {
    const items: FileItem[] = [];
    for (const f of response.files) {
      const relPath = this.currentPath
        ? `${this.currentPath}/${f.name}`
        : f.name;
      items.push({
        name: f.name,
        type: f.type,
        size: f.size,
        mtime: f.mtime,
        relativePath: relPath,
        isDownloaded: false
      });
    }
    this.fileList = items;
  }
}
