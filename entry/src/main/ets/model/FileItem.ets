export interface FileItem {
  name: string;
  type: 'dir' | 'file';
  size: number;
  mtime: string;
  relativePath: string;
  isDownloaded: boolean;
}

export interface FileListResponse {
  path: string;
  files: Array<FileInfoResponse>;
}

export interface FileInfoResponse {
  name: string;
  type: 'dir' | 'file';
  size: number;
  mtime: string;
}

export interface DownloadProgress {
  progress: number;
  done?: boolean;
  phase?: 'download' | 'extract';
}

export interface ApiError {
  code: string;
  message: string;
}

