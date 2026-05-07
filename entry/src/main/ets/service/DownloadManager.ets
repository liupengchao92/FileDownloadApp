import { FileItem, DownloadProgress } from '../model/FileItem';
import { DownloadTask, DownloadStatus, DownloadEvent } from '../model/DownloadTask';
import { ApiService } from './ApiService';
import { FileUtils } from '../utils/FileUtils';
import { LogUtil } from '../utils/LogUtil';

/** 最大并发下载任务数 */
const MAX_CONCURRENT = 3;

/** 下载事件监听器类型 */
type Listener = (event: DownloadEvent) => void;

/**
 * 下载管理器（单例）
 * 负责管理所有下载任务的生命周期，包括：
 * - 任务队列管理（等待队列、进行中任务、已完成任务）
 * - 并发控制（最多同时执行 MAX_CONCURRENT 个任务）
 * - 失败重试（指数退避策略，最多重试 3 次）
 * - 观察者模式通知 UI 层更新
 */
export class DownloadManager {
  private static instance: DownloadManager;
  /** 等待队列：尚未开始的任务 */
  private waitingQueue: DownloadTask[] = [];
  /** 进行中的任务映射表，key 为任务 ID */
  private activeTasks: Map<string, DownloadTask> = new Map();
  /** 已完成/失败的任务映射表，用于查询历史状态 */
  private completedTasks: Map<string, DownloadTask> = new Map();
  /** 事件监听器集合（UI 组件通过 subscribe 注册） */
  private listeners: Set<Listener> = new Set();
  /** 已取消任务的 ID 集合，用于在异步流程中检测取消状态 */
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

  /** 订阅下载事件，UI 组件注册后可接收进度和状态更新 */
  subscribe(listener: Listener): void {
    this.listeners.add(listener);
  }

  /** 取消订阅，UI 组件销毁时应调用以避免内存泄漏 */
  unsubscribe(listener: Listener): void {
    this.listeners.delete(listener);
  }

  /** 向所有监听器广播下载事件 */
  private notify(event: DownloadEvent): void {
    this.listeners.forEach(l => l(event));
  }

  getWaitingCount(): number {
    return this.waitingQueue.length;
  }

  getActiveCount(): number {
    return this.activeTasks.size;
  }

  /** 获取所有任务（等待 + 进行中 + 已完成） */
  getAllTasks(): DownloadTask[] {
    const all: DownloadTask[] = [];
    this.waitingQueue.forEach(t => all.push(t));
    this.activeTasks.forEach(t => all.push(t));
    this.completedTasks.forEach(t => all.push(t));
    return all;
  }

  /**
   * 根据文件相对路径查找任务
   * 用于 UI 组件初始化时恢复下载状态显示
   */
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

  /**
   * 添加单文件下载任务
   * 创建任务后加入等待队列，并尝试调度执行
   *
   * @param file 要下载的文件信息
   * @param targetPath 本地目标保存路径
   * @returns 创建的下载任务实例
   */
  addTask(file: FileItem, targetPath: string): DownloadTask {
    LogUtil.info(`[DM] addTask: ${file.name}, target: ${targetPath}`);
    const task = new DownloadTask(file, targetPath);
    this.waitingQueue.push(task);
    this.notify({ type: 'statusChange', taskId: task.id, task });
    this.scheduleNext();
    return task;
  }

  /**
   * 添加批量下载任务
   * 将多个文件打包为一个批量任务，服务端返回 ZIP 后本地解压
   * 批量任务在队列中作为一个整体占用一个并发槽位
   *
   * @param files 要批量下载的文件列表
   * @returns 创建的批量下载任务实例
   */
  addBatch(files: FileItem[]): DownloadTask {
    LogUtil.info(`[DM] addBatch: ${files.length} files`);
    // 创建一个合成的占位 FileItem 代表整个批量任务
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
    // 设置批量下载附加信息
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

  /**
   * 取消指定任务
   * 如果任务正在执行中，从 activeTasks 移除并清理临时文件
   * 如果任务在等待队列中，直接移除
   */
  cancel(taskId: string): void {
    LogUtil.info(`[DM] cancel: ${taskId}`);
    this.cancelledTasks.add(taskId);

    // 尝试从进行中的任务取消
    const active = this.activeTasks.get(taskId);
    if (active) {
      active.status = DownloadStatus.FAILED;
      this.activeTasks.delete(taskId);
      this.completedTasks.set(taskId, active);
      this.notify({ type: 'statusChange', taskId, task: active });
      // 清理单文件下载的临时文件（批量任务的 ZIP 由 executeBatchTask 自行清理）
      if (!active.batchInfo) {
        FileUtils.removeTempFile(active.targetPath + '.tmp');
      }
      this.scheduleNext();
      return;
    }

    // 尝试从等待队列取消
    const idx = this.waitingQueue.findIndex(t => t.id === taskId);
    if (idx >= 0) {
      const task = this.waitingQueue.splice(idx, 1)[0];
      task.status = DownloadStatus.FAILED;
      this.completedTasks.set(taskId, task);
      this.notify({ type: 'statusChange', taskId, task });
    }
  }

  /** 取消所有任务（进行中 + 等待中） */
  cancelAll(): void {
    LogUtil.info('[DM] cancelAll');
    const activeIds: string[] = [];
    this.activeTasks.forEach((_, key) => activeIds.push(key));
    activeIds.forEach(id => this.cancel(id));
    const waitingIds = this.waitingQueue.map(t => t.id);
    waitingIds.forEach(id => this.cancel(id));
  }

  /**
   * 重试指定的失败任务
   * 将任务从已完成队列移回等待队列，重置重试计数
   */
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

  /** 重试所有失败的任务 */
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

  /**
   * 调度下一个任务执行
   * 从等待队列中取出任务填入空闲的并发槽位，直到达到 MAX_CONCURRENT 上限或队列为空
   * 在任务完成、失败、取消时自动调用
   */
  private scheduleNext(): void {
    while (this.activeTasks.size < MAX_CONCURRENT && this.waitingQueue.length > 0) {
      const task = this.waitingQueue.shift();
      if (task) {
        this.executeTask(task);
      }
    }
  }

  /**
   * 执行单个下载任务（统一分发入口）
   * 根据是否携带 batchInfo 分发到单文件下载或批量下载
   * 包含完整的错误处理和重试逻辑
   *
   * @param task 要执行的下载任务
   */
  private async executeTask(task: DownloadTask): Promise<void> {
    // 检查任务是否在执行前已被取消
    if (this.cancelledTasks.has(task.id)) {
      this.cancelledTasks.delete(task.id);
      return;
    }

    // 将任务标记为下载中，加入进行中队列
    task.status = DownloadStatus.DOWNLOADING;
    this.activeTasks.set(task.id, task);
    this.notify({ type: 'statusChange', taskId: task.id, task });
    LogUtil.info(`[DM] executeTask: ${task.file.name}, active: ${this.activeTasks.size}/${MAX_CONCURRENT}`);

    try {
      // 根据是否有批量信息分发到不同的执行逻辑
      if (task.batchInfo) {
        await this.executeBatchTask(task);
      } else {
        await this.executeSingleTask(task);
      }

      // 下载成功：更新状态，移入已完成队列
      task.status = DownloadStatus.COMPLETED;
      task.progress = 100;
      this.activeTasks.delete(task.id);
      this.completedTasks.set(task.id, task);
      this.notify({ type: 'completed', taskId: task.id, task });
      LogUtil.info(`[DM] task completed: ${task.file.name}`);
    } catch (err) {
      this.activeTasks.delete(task.id);
      LogUtil.warn(`[DM] task failed: ${task.file.name}, error: ${err.message}`);

      // 检查是否在下载过程中被取消
      if (this.cancelledTasks.has(task.id)) {
        this.cancelledTasks.delete(task.id);
        task.status = DownloadStatus.FAILED;
        this.completedTasks.set(task.id, task);
        this.notify({ type: 'statusChange', taskId: task.id, task });
        this.scheduleNext();
        return;
      }

      // 重试逻辑：指数退避策略（1s → 2s → 4s）
      if (task.retryCount < task.maxRetries) {
        task.retryCount++;
        task.status = DownloadStatus.WAITING;
        // 延迟 = 2^(retryCount-1) * 1000ms，即第1次1秒、第2次2秒、第3次4秒
        const delay = Math.pow(2, task.retryCount - 1) * 1000;
        LogUtil.info(`[DM] retry ${task.retryCount}/${task.maxRetries} for ${task.file.name} in ${delay}ms`);
        this.notify({ type: 'statusChange', taskId: task.id, task });
        // 延迟后将任务插回等待队列头部（优先重试）
        setTimeout(() => {
          if (!this.cancelledTasks.has(task.id)) {
            this.waitingQueue.unshift(task);
            this.scheduleNext();
          }
        }, delay);
      } else {
        // 重试次数耗尽，标记为最终失败
        task.status = DownloadStatus.FAILED;
        this.completedTasks.set(task.id, task);
        this.notify({ type: 'failed', taskId: task.id, task });
        LogUtil.error(`[DM] task exhausted retries: ${task.file.name}`);
      }
    }

    // 当前任务处理完毕，尝试调度队列中的下一个任务
    this.scheduleNext();
  }

  /**
   * 执行单文件下载任务
   * 流程：确保目录存在 → 调用 ApiService 下载 → rename 临时文件到目标路径
   *
   * @param task 单文件下载任务
   */
  private async executeSingleTask(task: DownloadTask): Promise<void> {
    const tmpPath = task.targetPath + '.tmp';
    try {
      // 确保目标文件的父目录存在
      await FileUtils.ensureDir(task.targetPath);
      // 调用系统下载服务下载文件到临时路径
      await ApiService.getInstance().downloadFile(
        task.file.relativePath,
        tmpPath,
        (progress: DownloadProgress) => {
          // 更新任务进度并通知 UI
          task.progress = progress.progress;
          if (progress.indeterminate) {
            task.indeterminate = true;
          }
          this.notify({ type: 'progress', taskId: task.id, task });
        }
      );

      // 下载完成，将临时文件重命名为目标文件
      await FileUtils.renameFile(tmpPath, task.targetPath);
    } catch (err) {
      // 下载失败，清理临时文件后向上抛出错误
      FileUtils.removeTempFile(tmpPath);
      throw err as Error;
    }
  }

  /**
   * 执行批量下载任务
   * 流程：
   *   1. 收集所有文件路径，请求服务端打包为 ZIP 下载
   *   2. 下载完成后将 ZIP 解压到沙盒根目录（保持目录结构）
   *   3. 清理临时 ZIP 文件
   *
   * @param task 批量下载任务（携带 batchInfo）
   */
  private async executeBatchTask(task: DownloadTask): Promise<void> {
    const sandboxRoot = FileUtils.getSandboxRoot();
    const zipPath = FileUtils.getBatchZipPath();
    // 收集所有参与批量下载的文件相对路径
    const paths: string[] = [];
    for (const item of task.batchInfo!.fileItems) {
      paths.push(item.relativePath);
    }
    // 阶段一：下载 ZIP 文件
    if (task.batchInfo) {
      task.batchInfo.phase = 'download';
    }
    this.notify({ type: 'statusChange', taskId: task.id, task });

    try {
      // 调用批量下载接口，下载 ZIP 到本地临时路径
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

      // 下载完成后检查是否在解压前被取消
      if (this.cancelledTasks.has(task.id)) {
        FileUtils.removeTempFile(zipPath);
        throw new Error('Task cancelled before extraction');
      }

      // 阶段二：解压 ZIP 到沙盒根目录
      if (task.batchInfo) {
        task.batchInfo.phase = 'extract';
      }
      task.progress = 60;
      this.notify({ type: 'statusChange', taskId: task.id, task });

      // 解压 ZIP，文件会自动按服务端目录结构保存
      await FileUtils.extractZip(zipPath, sandboxRoot);

      task.progress = 99;
      this.notify({ type: 'progress', taskId: task.id, task });
    } catch (err) {
      // 出错时清理临时 ZIP 文件
      FileUtils.removeTempFile(zipPath);
      throw err as Error;
    }

    // 成功后也清理临时 ZIP 文件
    FileUtils.removeTempFile(zipPath);
  }
}
