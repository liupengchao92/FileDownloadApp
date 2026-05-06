import { FileItem } from './FileItem';

export enum DownloadStatus {
  WAITING = 'waiting',
  DOWNLOADING = 'downloading',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  FAILED = 'failed'
}

export interface BatchInfo {
  totalPaths: number;
  phase: 'download' | 'extract';
  fileItems: FileItem[];
}

export class DownloadTask {
  id: string;
  file: FileItem;
  targetPath: string;
  status: DownloadStatus;
  progress: number;
  indeterminate: boolean;
  retryCount: number;
  maxRetries: number;
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

export interface DownloadEvent {
  type: 'progress' | 'statusChange' | 'completed' | 'failed';
  taskId: string;
  task: DownloadTask;
}
