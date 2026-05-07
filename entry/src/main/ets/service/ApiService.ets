import { FileItem, DownloadProgress, FileInfoResponse, FileListResponse, ApiError } from '../model/FileItem';
import http from '@ohos.net.http';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { LogUtil } from '../utils/LogUtil';
import { FileUtils } from '../utils/FileUtils';

/**
 * API 服务类（单例）
 * 封装所有与服务端的 HTTP 通信，包括文件列表查询和文件下载
 * 使用 @ohos.net.http 进行 JSON 请求，@kit.BasicServicesKit 的 request.downloadFile 进行文件下载
 */
export class ApiService {
  private static instance: ApiService;
  /** 服务端 API 基础地址 */
  static BASE_URL: string = 'http://192.168.115.144:3000/api';
  /** 应用上下文，系统下载服务需要 */
  static context: common.Context | null = null;
  // static BASE_URL: string = 'http://192.168.1.6:3000/api';

  static setContext(ctx: common.Context): void {
    ApiService.context = ctx;
  }

  static setBaseUrl(url: string): void {
    ApiService.BASE_URL = url;
    LogUtil.info(`[ApiService] BASE_URL changed to: ${url}`);
  }

  /**
   * 将系统下载服务的错误码映射为中文提示
   * @param code 系统下载服务返回的错误码（1-8）
   * @returns 中文错误描述
   */
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

  /**
   * 获取指定目录下的文件列表
   * @param path 相对根目录的路径，空字符串表示根目录
   * @returns 文件列表响应，包含当前路径和文件/目录数组
   */
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

  /**
   * 递归获取指定目录下的所有文件（含子目录）
   * 注意：当前代码中未被调用，预留接口
   * @param path 目录路径
   * @returns 展平的文件列表，relativePath 已拼接完整
   */
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

  /**
   * 获取单个文件/目录的元信息
   * 注意：当前代码中未被调用，预留接口
   * @param path 相对根目录的路径
   * @returns 文件元信息（name、type、size、mtime）
   */
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

  /**
   * 系统级文件下载（核心下载方法）
   * 使用 HarmonyOS 系统下载服务 request.downloadFile，由系统管理网络连接和 I/O
   * 下载流程：先写入 .tmp 临时文件，完成后 rename 到目标路径，防止中断产生损坏文件
   *
   * @param url 下载源 URL
   * @param destPath 本地目标路径（最终路径，内部会自动处理 .tmp 临时路径）
   * @param onProgress 进度回调，返回百分比或不确定进度状态
   */
  async systemDownload(
    url: string,
    destPath: string,
    onProgress: (progress: DownloadProgress) => void
  ): Promise<void> {
    // 确保目标文件的父目录存在
    await FileUtils.ensureDir(destPath);
    // 使用 .tmp 后缀的临时路径，下载完成后再 rename
    const tmpPath = destPath + '.tmp';

    return new Promise((resolve, reject) => {
      LogUtil.info(`[ApiService] url : ${url}`);
      // 调用系统下载服务，filePath 指定临时文件保存位置
      request.downloadFile(ApiService.context!, {
        url: url,
        filePath: tmpPath
      }).then((task) => {
        // 监听下载进度事件
        task.on('progress', (received: number, total: number) => {
          LogUtil.info(`[ApiService] progress  received:${received}  total:${total}`);
          if (total > 0) {
            // 服务端返回了文件大小，计算百分比
            onProgress({ progress: Math.round((received / total) * 100) });
          } else {
            // 服务端未返回 Content-Length，进度不确定
            onProgress({ progress: 0, indeterminate: true });
          }
        });
        // 监听下载完成事件，将临时文件 rename 到目标路径
        task.on('complete', () => {
          FileUtils.renameFile(tmpPath, destPath).then(() => {
            onProgress({ progress: 100, done: true });
            resolve();
          });
        });
        // 监听下载失败事件，清理临时文件
        task.on('fail', (err: number) => {
          FileUtils.removeTempFile(tmpPath);
          reject(new Error(`${ApiService.getDownloadErrorMsg(err)}`));
        });
      }).catch((err:BusinessError) => {
        // 启动下载任务本身失败（如 URL 格式错误、上下文无效等）
        FileUtils.removeTempFile(tmpPath);
        reject(new Error(`Failed to start system download: ${err.message}`));
      });
    });
  }

  /**
   * 单文件下载
   * 拼接下载 URL 后委托给 systemDownload 执行
   *
   * @param sourcePath 文件的相对路径（如 "documents/report.pdf"）
   * @param destPath 本地目标保存路径
   * @param onProgress 进度回调
   */
  async downloadFile(
    sourcePath: string,
    destPath: string,
    onProgress: (progress: DownloadProgress) => void
  ): Promise<void> {
    const url = `${ApiService.BASE_URL}/download/file?path=${encodeURIComponent(sourcePath)}`;
    return this.systemDownload(url, destPath, onProgress);
  }

  /**
   * 批量文件下载
   * 将多个文件路径数组序列化为 JSON 后编码为查询参数，服务端返回 ZIP 压缩包
   *
   * @param paths 要下载的文件相对路径数组
   * @param savePath ZIP 文件的本地保存路径
   * @param onProgress 进度回调
   */
  async downloadBatch(
  paths: string[],
  savePath: string,
  onProgress: (progress: DownloadProgress) => void
): Promise<void> {
  // 将路径数组序列化为 JSON 字符串并 URL 编码
  const pathsJson = JSON.stringify(paths);
  const encoded = encodeURIComponent(pathsJson);
  const url = `${ApiService.BASE_URL}/download/batch?paths=${encoded}`;
  return this.systemDownload(url, savePath, onProgress);
}

  /**
   * 解析服务端错误响应体
   * 尝试从 JSON 中提取 code 和 message，解析失败则返回 HTTP 状态码
   */
  private parseError(body: string, statusCode: number): Error {
    try {
      const errBody = JSON.parse(body) as Record<string, string>;
      return new Error(`${errBody.code || 'UNKNOWN'}: ${errBody.message || 'Unknown error'}`);
    } catch {
      return new Error(`HTTP ${statusCode}`);
    }
  }
}
