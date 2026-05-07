/**
 * 文件/文件夹条目数据模型
 * 对应服务端 /api/files 接口返回的单个文件/目录信息
 */
export interface FileItem {
  /** 文件或文件夹名称 */
  name: string;
  /** 类型：'dir' 表示文件夹，'file' 表示文件 */
  type: 'dir' | 'file';
  /** 文件大小（字节），文件夹为 0 */
  size: number;
  /** 最后修改时间，ISO 8601 格式 */
  mtime: string;
  /** 相对沙盒根目录的路径，由客户端拼接 currentPath + name */
  relativePath: string;
  /** 是否已下载到本地（预留字段，当前未持久化） */
  isDownloaded: boolean;
}

/**
 * 文件列表接口响应结构
 * 对应 GET /api/files?path=xxx 的响应体
 */
export interface FileListResponse {
  /** 当前查询的目录路径 */
  path: string;
  /** 该目录下的文件/文件夹列表 */
  files: Array<FileInfoResponse>;
}

/**
 * 文件/目录元信息接口响应结构
 * 对应 GET /api/files/info?path=xxx 的响应体
 */
export interface FileInfoResponse {
  name: string;
  type: 'dir' | 'file';
  size: number;
  mtime: string;
}

/**
 * 下载进度信息
 * 由 ApiService 的系统下载回调产生，传递给 DownloadManager 和 UI 层
 */
export interface DownloadProgress {
  /** 下载进度百分比（0-100） */
  progress: number;
  /** 下载是否已完成 */
  done?: boolean;
  /** 当前阶段：'download' 下载中 / 'extract' 解压中（仅批量下载） */
  phase?: 'download' | 'extract';
  /** 是否为不确定进度（服务端未返回 Content-Length 时） */
  indeterminate?: boolean;
}

/**
 * API 错误响应结构
 */
export interface ApiError {
  /** 错误码，如 PATH_TRAVERSAL、FILE_NOT_FOUND */
  code: string;
  /** 人类可读的错误描述 */
  message: string;
}
