import { FileItem } from './FileItem';

/**
 * 下载任务状态枚举
 */
export enum DownloadStatus {
  /** 等待中——已入队，等待调度执行 */
  WAITING = 'waiting',
  /** 下载中——正在通过系统下载服务传输数据 */
  DOWNLOADING = 'downloading',
  /** 已暂停（预留，当前未实现） */
  PAUSED = 'paused',
  /** 已完成——文件已成功下载到本地 */
  COMPLETED = 'completed',
  /** 已失败——下载出错且重试次数已耗尽 */
  FAILED = 'failed'
}

/**
 * 批量下载附加信息
 * 仅批量下载任务才会携带此字段，单文件下载为 undefined
 */
export interface BatchInfo {
  /** 批量下载包含的文件/文件夹路径总数 */
  totalPaths: number;
  /** 当前阶段：'download' 下载 ZIP / 'extract' 解压 ZIP */
  phase: 'download' | 'extract';
  /** 参与批量下载的文件列表 */
  fileItems: FileItem[];
}

/**
 * 下载任务类
 * 每个下载任务（单文件或批量）对应一个 DownloadTask 实例
 * 由 DownloadManager 创建并管理生命周期
 */
export class DownloadTask {
  /** 任务唯一标识，格式：{relativePath}_{timestamp} */
  id: string;
  /** 关联的文件信息（批量任务为合成的占位 FileItem） */
  file: FileItem;
  /** 本地目标保存路径（批量任务为空字符串） */
  targetPath: string;
  /** 当前任务状态 */
  status: DownloadStatus;
  /** 下载进度（0-100） */
  progress: number;
  /** 是否为不确定进度（服务端未返回文件大小时） */
  indeterminate: boolean;
  /** 当前已重试次数 */
  retryCount: number;
  /** 最大重试次数 */
  maxRetries: number;
  /** 批量下载附加信息，单文件下载时为 undefined */
  batchInfo?: BatchInfo;

  constructor(file: FileItem, targetPath: string) {
    this.id = `${file.relativePath}_${Date.now()}`;
    this.file = file;
    this.targetPath = targetPath;
    this.status = DownloadStatus.WAITING;
    this.progress = 0;
    this.indeterminate = false;
    this.retryCount = 0;
    this.maxRetries = 3;
  }
}

/**
 * 下载事件接口
 * DownloadManager 通过观察者模式向 UI 层推送下载状态变更
 */
export interface DownloadEvent {
  /** 事件类型：进度更新 / 状态变更 / 完成 / 失败 */
  type: 'progress' | 'statusChange' | 'completed' | 'failed';
  /** 触发事件的任务 ID */
  taskId: string;
  /** 触发事件的任务实例 */
  task: DownloadTask;
}
