import { FileItem } from '../model/FileItem';
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

  addTask(file: FileItem, targetPath: string): DownloadTask {
    LogUtil.info(`[DM] addTask: ${file.name}, target: ${targetPath}`);
    const task = new DownloadTask(file, targetPath);
    this.waitingQueue.push(task);
    this.notify({ type: 'statusChange', taskId: task.id, task });
    this.scheduleNext();
    return task;
  }

  addBatch(files: FileItem[]): DownloadTask[] {
    LogUtil.info(`[DM] addBatch: ${files.length} files`);
    const tasks: DownloadTask[] = [];
    for (const file of files) {
      const targetPath = FileUtils.buildLocalPath(file.relativePath);
      const task = new DownloadTask(file, targetPath);
      this.waitingQueue.push(task);
      tasks.push(task);
      this.notify({ type: 'statusChange', taskId: task.id, task });
    }
    LogUtil.info(`[DM] addBatch: ${tasks.length} tasks queued`);
    this.scheduleNext();
    return tasks;
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
      FileUtils.removeTempFile(active.targetPath + '.tmp');
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

    const tmpPath = task.targetPath + '.tmp';

    try {
      await FileUtils.ensureDir(task.targetPath);

      await ApiService.getInstance().downloadFile(
        task.file.relativePath,
        tmpPath,
        (progress) => {
          task.progress = progress.progress;
          this.notify({ type: 'progress', taskId: task.id, task });
        }
      );

      await FileUtils.renameFile(tmpPath, task.targetPath);

      task.status = DownloadStatus.COMPLETED;
      task.progress = 100;
      this.activeTasks.delete(task.id);
      this.completedTasks.set(task.id, task);
      this.notify({ type: 'completed', taskId: task.id, task });
      LogUtil.info(`[DM] task completed: ${task.file.name}`);
    } catch (err) {
      this.activeTasks.delete(task.id);
      FileUtils.removeTempFile(tmpPath);
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
}
