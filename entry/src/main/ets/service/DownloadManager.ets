import { FileItem, DownloadProgress } from '../model/FileItem';
import { DownloadTask, DownloadStatus, DownloadEvent } from '../model/DownloadTask';
import { ApiService } from './ApiService';
import { FileUtils } from '../utils/FileUtils';
import { LogUtil } from '../utils/LogUtil';

const MAX_CONCURRENT = 3;

type Listener = (event: DownloadEvent) => void;

export class DownloadManager {
  private static instance: DownloadManager;
  private waitingQueue: DownloadTask[] = [];
  private activeTasks: Map<string, DownloadTask> = new Map();
  private completedTasks: Map<string, DownloadTask> = new Map();
  private listeners: Set<Listener> = new Set();
  private cancelledTasks: Set<string> = new Set();

  private constructor() {
    LogUtil.info('DownloadManager initialized');
  }

  static getInstance(): DownloadManager {
    if (!DownloadManager.instance) {
      DownloadManager.instance = new DownloadManager();
    }
    return DownloadManager.instance;
  }

  subscribe(listener: Listener): void {
    this.listeners.add(listener);
  }

  unsubscribe(listener: Listener): void {
    this.listeners.delete(listener);
  }

  private notify(event: DownloadEvent): void {
    this.listeners.forEach(l => l(event));
  }

  getWaitingCount(): number {
    return this.waitingQueue.length;
  }

  getActiveCount(): number {
    return this.activeTasks.size;
  }

  getAllTasks(): DownloadTask[] {
    const all: DownloadTask[] = [];
    this.waitingQueue.forEach(t => all.push(t));
    this.activeTasks.forEach(t => all.push(t));
    this.completedTasks.forEach(t => all.push(t));
    return all;
  }

  getTaskByPath(relativePath: string): DownloadTask | undefined {
    for (const t of this.waitingQueue) {
      if (t.file.relativePath === relativePath) {
        return t;
      }
    }
    for (const t of this.activeTasks) {
      if (t[1].file.relativePath === relativePath) {
        return t[1];
      }
    }
    for (const t of this.completedTasks) {
      if (t[1].file.relativePath === relativePath) {
        return t[1];
      }
    }
    return undefined;
  }

  addTask(file: FileItem, targetPath: string): DownloadTask {
    LogUtil.info(`[DM] addTask: ${file.name}, target: ${targetPath}`);
    const task = new DownloadTask(file, targetPath);
    this.waitingQueue.push(task);
    this.notify({ type: 'statusChange', taskId: task.id, task });
    this.scheduleNext();
    return task;
  }

  addBatch(files: FileItem[]): DownloadTask {
    LogUtil.info(`[DM] addBatch: ${files.length} files`);
    const batchFileName = `Batch (${files.length} files)`;
    const batchFile: FileItem = {
      name: batchFileName,
      type: 'file',
      size: 0,
      mtime: new Date().toISOString(),
      relativePath: '',
      isDownloaded: false
    };
    const task = new DownloadTask(batchFile, '');
    task.batchInfo = {
      totalPaths: files.length,
      phase: 'download',
      fileItems: files
    };
    this.waitingQueue.push(task);
    this.notify({ type: 'statusChange', taskId: task.id, task });
    LogUtil.info(`[DM] addBatch: 1 batch task queued (${files.length} files)`);
    this.scheduleNext();
    return task;
  }

  cancel(taskId: string): void {
    LogUtil.info(`[DM] cancel: ${taskId}`);
    this.cancelledTasks.add(taskId);

    const active = this.activeTasks.get(taskId);
    if (active) {
      active.status = DownloadStatus.FAILED;
      this.activeTasks.delete(taskId);
      this.completedTasks.set(taskId, active);
      this.notify({ type: 'statusChange', taskId, task: active });
      if (!active.batchInfo) {
        FileUtils.removeTempFile(active.targetPath + '.tmp');
      }
      this.scheduleNext();
      return;
    }

    const idx = this.waitingQueue.findIndex(t => t.id === taskId);
    if (idx >= 0) {
      const task = this.waitingQueue.splice(idx, 1)[0];
      task.status = DownloadStatus.FAILED;
      this.completedTasks.set(taskId, task);
      this.notify({ type: 'statusChange', taskId, task });
    }
  }

  cancelAll(): void {
    LogUtil.info('[DM] cancelAll');
    const activeIds: string[] = [];
    this.activeTasks.forEach((_, key) => activeIds.push(key));
    activeIds.forEach(id => this.cancel(id));
    const waitingIds = this.waitingQueue.map(t => t.id);
    waitingIds.forEach(id => this.cancel(id));
  }

  retry(taskId: string): void {
    LogUtil.info(`[DM] retry: ${taskId}`);
    const task = this.completedTasks.get(taskId);
    if (!task || task.status !== DownloadStatus.FAILED) {
      return;
    }
    task.status = DownloadStatus.WAITING;
    task.progress = 0;
    task.retryCount = 0;
    this.completedTasks.delete(taskId);
    this.waitingQueue.push(task);
    this.notify({ type: 'statusChange', taskId, task });
    this.scheduleNext();
  }

  retryAll(): void {
    LogUtil.info('[DM] retryAll');
    const failedTasks: DownloadTask[] = [];
    this.completedTasks.forEach(t => {
      if (t.status === DownloadStatus.FAILED) {
        failedTasks.push(t);
      }
    });
    for (const task of failedTasks) {
      task.status = DownloadStatus.WAITING;
      task.progress = 0;
      task.retryCount = 0;
      this.completedTasks.delete(task.id);
      this.waitingQueue.push(task);
      this.notify({ type: 'statusChange', taskId: task.id, task });
    }
    this.scheduleNext();
  }

  private scheduleNext(): void {
    while (this.activeTasks.size < MAX_CONCURRENT && this.waitingQueue.length > 0) {
      const task = this.waitingQueue.shift();
      if (task) {
        this.executeTask(task);
      }
    }
  }

  private async executeTask(task: DownloadTask): Promise<void> {
    if (this.cancelledTasks.has(task.id)) {
      this.cancelledTasks.delete(task.id);
      return;
    }

    task.status = DownloadStatus.DOWNLOADING;
    this.activeTasks.set(task.id, task);
    this.notify({ type: 'statusChange', taskId: task.id, task });
    LogUtil.info(`[DM] executeTask: ${task.file.name}, active: ${this.activeTasks.size}/${MAX_CONCURRENT}`);

    try {
      if (task.batchInfo) {
        await this.executeBatchTask(task);
      } else {
        await this.executeSingleTask(task);
      }

      task.status = DownloadStatus.COMPLETED;
      task.progress = 100;
      this.activeTasks.delete(task.id);
      this.completedTasks.set(task.id, task);
      this.notify({ type: 'completed', taskId: task.id, task });
      LogUtil.info(`[DM] task completed: ${task.file.name}`);
    } catch (err) {
      this.activeTasks.delete(task.id);
      LogUtil.warn(`[DM] task failed: ${task.file.name}, error: ${err.message}`);

      if (this.cancelledTasks.has(task.id)) {
        this.cancelledTasks.delete(task.id);
        task.status = DownloadStatus.FAILED;
        this.completedTasks.set(task.id, task);
        this.notify({ type: 'statusChange', taskId: task.id, task });
        this.scheduleNext();
        return;
      }

      if (task.retryCount < task.maxRetries) {
        task.retryCount++;
        task.status = DownloadStatus.WAITING;
        const delay = Math.pow(2, task.retryCount - 1) * 1000;
        LogUtil.info(`[DM] retry ${task.retryCount}/${task.maxRetries} for ${task.file.name} in ${delay}ms`);
        this.notify({ type: 'statusChange', taskId: task.id, task });
        setTimeout(() => {
          if (!this.cancelledTasks.has(task.id)) {
            this.waitingQueue.unshift(task);
            this.scheduleNext();
          }
        }, delay);
      } else {
        task.status = DownloadStatus.FAILED;
        this.completedTasks.set(task.id, task);
        this.notify({ type: 'failed', taskId: task.id, task });
        LogUtil.error(`[DM] task exhausted retries: ${task.file.name}`);
      }
    }

    this.scheduleNext();
  }

  private async executeSingleTask(task: DownloadTask): Promise<void> {
    const tmpPath = task.targetPath + '.tmp';
    try {
      await FileUtils.ensureDir(task.targetPath);

      await ApiService.getInstance().downloadFile(
        task.file.relativePath,
        tmpPath,
        (progress: DownloadProgress) => {
          task.progress = progress.progress;
          if (progress.indeterminate) {
            task.indeterminate = true;
          }
          this.notify({ type: 'progress', taskId: task.id, task });
        }
      );

      await FileUtils.renameFile(tmpPath, task.targetPath);
    } catch (err) {
      FileUtils.removeTempFile(tmpPath);
      throw err as Error;
    }
  }

  private async executeBatchTask(task: DownloadTask): Promise<void> {
    const sandboxRoot = FileUtils.getSandboxRoot();
    const zipPath = FileUtils.getBatchZipPath();
    const paths: string[] = [];

    for (const item of task.batchInfo!.fileItems) {
      paths.push(item.relativePath);
    }

    if (task.batchInfo) {
      task.batchInfo.phase = 'download';
    }
    this.notify({ type: 'statusChange', taskId: task.id, task });

    try {
      await ApiService.getInstance().downloadBatch(
        paths,
        zipPath,
        (progress: DownloadProgress) => {
          task.progress = progress.progress;
          if (progress.indeterminate) {
            task.indeterminate = true;
          }
          this.notify({ type: 'progress', taskId: task.id, task });
        }
      );

      if (this.cancelledTasks.has(task.id)) {
        FileUtils.removeTempFile(zipPath);
        throw new Error('Task cancelled before extraction');
      }

      if (task.batchInfo) {
        task.batchInfo.phase = 'extract';
      }
      task.progress = 60;
      this.notify({ type: 'statusChange', taskId: task.id, task });

      await FileUtils.extractZip(zipPath, sandboxRoot);

      task.progress = 99;
      this.notify({ type: 'progress', taskId: task.id, task });
    } catch (err) {
      FileUtils.removeTempFile(zipPath);
      throw err as Error;
    }

    FileUtils.removeTempFile(zipPath);
  }
}
