import { FileItem, DownloadProgress, FileInfoResponse, FileListResponse, ApiError } from '../model/FileItem';
import http from '@ohos.net.http';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { LogUtil } from '../utils/LogUtil';
import { FileUtils } from '../utils/FileUtils';

export class ApiService {
  private static instance: ApiService;
  static BASE_URL: string = 'http://192.168.115.144:3000/api';
  static context: common.Context | null = null;
  // static BASE_URL: string = 'http://192.168.1.6:3000/api';

  static setContext(ctx: common.Context): void {
    ApiService.context = ctx;
  }

  static setBaseUrl(url: string): void {
    ApiService.BASE_URL = url;
    LogUtil.info(`[ApiService] BASE_URL changed to: ${url}`);
  }

  static getDownloadErrorMsg(code: number): string {
    const map: Record<number, string> = {
      1: '目标文件不存在',
      2: '网络不可用',
      3: '存储空间不足',
      4: '任务已暂停',
      5: '任务已删除',
      6: 'URL 不可用',
      7: '权限不足',
      8: '文件不存在或资源不可用'
    };
    return map[code] || `下载失败（错误码 ${code}）`;
  }

  static getInstance(): ApiService {
    if (!ApiService.instance) {
      ApiService.instance = new ApiService();
    }
    return ApiService.instance;
  }

  async getFileList(path: string = ''): Promise<FileListResponse> {
    const request = http.createHttp();
    const url = `${ApiService.BASE_URL}/files?path=${encodeURIComponent(path)}`;
    LogUtil.info(`[ApiService] getFileList request: ${url}`);

    return new Promise((resolve, reject) => {
      request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        header: { 'Accept': 'application/json' }
      }, (err, data) => {
        request.destroy();
        if (err) {
          LogUtil.error(`[ApiService] getFileList network error: ${err.message}`);
          reject(new Error(`Network error: ${err.message}`));
          return;
        }
        LogUtil.info(`[ApiService] getFileList response code: ${data.responseCode}`);
        if (data.responseCode !== 200) {
          reject(this.parseError(data.result as string, data.responseCode));
          return;
        }
        try {
          const result = JSON.parse(data.result as string) as FileListResponse;
          LogUtil.info(`[ApiService] getFileList success, files count: ${result.files.length}`);
          resolve(result);
        } catch (e) {
          LogUtil.error(`[ApiService] getFileList parse error, raw: ${data.result}`);
          reject(new Error('Failed to parse response'));
        }
      });
    });
  }

  async getAllFiles(path: string): Promise<FileItem[]> {
    const url = `${ApiService.BASE_URL}/files?path=${encodeURIComponent(path)}&recursive=true`;
    LogUtil.info(`[ApiService] getAllFiles request: ${url}`);

    return new Promise((resolve, reject) => {
      const request = http.createHttp();
      request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        header: { 'Accept': 'application/json' }
      }, (err, data) => {
        request.destroy();
        if (err) {
          reject(new Error(`Network error: ${err.message}`));
          return;
        }
        if (data.responseCode !== 200) {
          reject(this.parseError(data.result as string, data.responseCode));
          return;
        }
        try {
          const result = JSON.parse(data.result as string) as FileListResponse;
          LogUtil.info(`[ApiService] getAllFiles success: ${result.files.length} files`);
          const items: FileItem[] = result.files.map(f => ({
            name: f.name,
            type: f.type,
            size: f.size,
            mtime: f.mtime,
            relativePath: path ? `${path}/${f.name}` : f.name,
            isDownloaded: false
          }) as FileItem);
          resolve(items);
        } catch (e) {
          reject(new Error('Failed to parse response'));
        }
      });
    });
  }

  async getFileInfo(path: string): Promise<FileInfoResponse> {
    const request = http.createHttp();
    const url = `${ApiService.BASE_URL}/files/info?path=${encodeURIComponent(path)}`;
    LogUtil.info(`[ApiService] getFileInfo request: ${url}`);

    return new Promise((resolve, reject) => {
      request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        header: { 'Accept': 'application/json' }
      }, (err, data) => {
        request.destroy();
        if (err) {
          LogUtil.error(`[ApiService] getFileInfo network error: ${err.message}`);
          reject(new Error(`Network error: ${err.message}`));
          return;
        }
        LogUtil.info(`[ApiService] getFileInfo response code: ${data.responseCode}`);
        if (data.responseCode !== 200) {
          reject(this.parseError(data.result as string, data.responseCode));
          return;
        }
        try {
          const result = JSON.parse(data.result as string) as FileInfoResponse;
          LogUtil.info(`[ApiService] getFileInfo success: ${result.name}`);
          resolve(result);
        } catch (e) {
          LogUtil.error(`[ApiService] getFileInfo parse error: ${data.result}`);
          reject(new Error('Failed to parse response'));
        }
      });
    });
  }

  async systemDownload(
    url: string,
    destPath: string,
    onProgress: (progress: DownloadProgress) => void
  ): Promise<void> {
    await FileUtils.ensureDir(destPath);
    const tmpPath = destPath + '.tmp';

    return new Promise((resolve, reject) => {
      LogUtil.info(`[ApiService] url : ${url}`);
      request.downloadFile(ApiService.context!, {
        url: url,
        filePath: tmpPath
      }).then((task) => {
        task.on('progress', (received: number, total: number) => {
          if (total > 0) {
            onProgress({ progress: Math.round((received / total) * 100) });
          }
        });
        task.on('complete', () => {
          FileUtils.renameFile(tmpPath, destPath).then(() => {
            onProgress({ progress: 100, done: true });
            resolve();
          });
        });
        task.on('fail', (err: number) => {
          FileUtils.removeTempFile(tmpPath);
          reject(new Error(`${ApiService.getDownloadErrorMsg(err)}`));
        });
      }).catch((err:BusinessError) => {
        FileUtils.removeTempFile(tmpPath);
        reject(new Error(`Failed to start system download: ${err.message}`));
      });
    });
  }

  async downloadFile(
    sourcePath: string,
    destPath: string,
    onProgress: (progress: DownloadProgress) => void
  ): Promise<void> {
    const url = `${ApiService.BASE_URL}/download/file?path=${encodeURIComponent(sourcePath)}`;
    return this.systemDownload(url, destPath, onProgress);
  }

  async downloadBatch(
  paths: string[],
  savePath: string,
  onProgress: (progress: DownloadProgress) => void
): Promise<void> {
  const pathsJson = JSON.stringify(paths);
  const encoded = encodeURIComponent(pathsJson);
  const url = `${ApiService.BASE_URL}/download/batch?paths=${encoded}`;
  return this.systemDownload(url, savePath, onProgress);
}

  private parseError(body: string, statusCode: number): Error {
    try {
      const errBody = JSON.parse(body) as Record<string, string>;
      return new Error(`${errBody.code || 'UNKNOWN'}: ${errBody.message || 'Unknown error'}`);
    } catch {
      return new Error(`HTTP ${statusCode}`);
    }
  }
}
