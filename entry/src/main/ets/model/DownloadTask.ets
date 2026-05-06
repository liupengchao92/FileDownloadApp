import { FileItem } from './FileItem';

export enum DownloadStatus {
  WAITING = 'waiting',
  DOWNLOADING = 'downloading',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  FAILED = 'failed'
}

export class DownloadTask {
  id: string;
  file: FileItem;
  targetPath: string;
  status: DownloadStatus;
  progress: number;
  retryCount: number;
  maxRetries: number;

  constructor(file: FileItem, targetPath: string) {
    this.id = `${file.relativePath}_${Date.now()}`;
    this.file = file;
    this.targetPath = targetPath;
    this.status = DownloadStatus.WAITING;
    this.progress = 0;
    this.retryCount = 0;
    this.maxRetries = 3;
  }
}

export interface DownloadEvent {
  type: 'progress' | 'statusChange' | 'completed' | 'failed';
  taskId: string;
  task: DownloadTask;
}
