import { FileItem, FileListResponse } from '../model/FileItem';
import { DownloadStatus, DownloadEvent } from '../model/DownloadTask';
import { ApiService } from '../service/ApiService';
import { DownloadManager } from '../service/DownloadManager';
import { FileUtils } from '../utils/FileUtils';
import { LogUtil } from '../utils/LogUtil';
import { promptAction } from '@kit.ArkUI';
import { ObjectUtil } from '../utils/ObjectUtil';

export interface FileDownloadState {
  status: DownloadStatus;
  progress: number;
}

export class FileListViewModel {
  currentPath: string = '';
  breadcrumbs: string[] = [''];
  fileList: FileItem[] = [];
  isLoading: boolean = false;
  errorMessage: string = '';
  isMultiSelectMode: boolean = false;
  selectedFiles: Set<string> = new Set();
  fileDownloadStates: Record<string, FileDownloadState> = {};
  batchState: FileDownloadState | null = null;

  private onUpdate: () => void;
  private api: ApiService;
  private downloadManager: DownloadManager;

  constructor(onUpdate: () => void) {
    this.onUpdate = onUpdate;
    this.api = ApiService.getInstance();
    this.downloadManager = DownloadManager.getInstance();
    LogUtil.info('FileListViewModel created');

    this.downloadManager.subscribe((event: DownloadEvent) => {
      const task = event.task;
      if (task.batchInfo) {
        this.batchState = {
          status: task.status,
          progress: task.progress
        };
        if (task.status === DownloadStatus.COMPLETED) {
          promptAction.showToast({ message: `批量下载完成`, duration: 2000 });
          setTimeout(() => {
            this.batchState = null;
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
        const path = task.file.relativePath;
        this.fileDownloadStates[path] = {
          status: task.status,
          progress: task.progress
        };
        if (task.status === DownloadStatus.COMPLETED) {
          promptAction.showToast({ message: `${task.file.name} 下载完成`, duration: 2000 });
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
      this.fileDownloadStates = ObjectUtil.cloneRecord(this.fileDownloadStates);
      this.onUpdate();
    });
  }

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

  async navigateToDir(dir: FileItem): Promise<void> {
    LogUtil.info(`[VM] navigateToDir: ${dir.name} (${dir.relativePath})`);
    this.currentPath = dir.relativePath;
    this.updateBreadcrumbs();
    await this.refresh();
  }

  navigateToBreadcrumb(index: number): void {
    if (index < 0 || index >= this.breadcrumbs.length) {
      return;
    }
    const segments: string[] = [];
    for (let i = 1; i <= index; i++) {
      segments.push(this.breadcrumbs[i]);
    }
    this.currentPath = segments.join('/');
    LogUtil.info(`[VM] navigateToBreadcrumb: ${index} -> path="${this.currentPath}"`);
    this.updateBreadcrumbs();
    this.refresh();
  }

  goBack(): void {
    if (this.breadcrumbs.length <= 1) {
      return;
    }
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

  toggleMultiSelect(): void {
    this.isMultiSelectMode = !this.isMultiSelectMode;
    if (!this.isMultiSelectMode) {
      this.selectedFiles.clear();
    }
    LogUtil.info(`[VM] toggleMultiSelect: ${this.isMultiSelectMode}`);
    this.onUpdate();
  }

  toggleSelect(fileName: string): void {
    if (this.selectedFiles.has(fileName)) {
      this.selectedFiles.delete(fileName);
    } else {
      this.selectedFiles.add(fileName);
    }
    this.onUpdate();
  }

  selectAll(): void {
    for (const item of this.fileList) {
      this.selectedFiles.add(item.name);
    }
    this.onUpdate();
  }

  deselectAll(): void {
    this.selectedFiles.clear();
    this.onUpdate();
  }

  startDownload(file: FileItem): void {
    LogUtil.info(`[VM] startDownload: ${file.name}`);
    const targetPath = FileUtils.buildLocalPath(file.relativePath);
    this.downloadManager.addTask(file, targetPath);
    this.onUpdate();
  }

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
