import { FileItem, DownloadProgress, FileInfoResponse, FileListResponse } from '../model/FileItem';
import http from '@ohos.net.http';
import { fileIo } from '@kit.CoreFileKit';
import { LogUtil } from '../utils/LogUtil';

export class ApiService {
  private static instance: ApiService;
 // static BASE_URL: string = 'http://192.168.115.144:3000/api';
   static BASE_URL: string = 'http://192.168.1.6:3000/api';

  static setBaseUrl(url: string): void {
    ApiService.BASE_URL = url;
    LogUtil.info(`[ApiService] BASE_URL changed to: ${url}`);
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

  async downloadFile(
    sourcePath: string,
    destPath: string,
    onProgress: (progress: DownloadProgress) => void
  ): Promise<void> {
    const url = `${ApiService.BASE_URL}/download`;
    const body = JSON.stringify({ path: sourcePath });
    LogUtil.info(`[ApiService] downloadFile: ${sourcePath} -> ${destPath}`);

    return new Promise((resolve, reject) => {
      const request = http.createHttp();
      let settled = false;
      let totalBytes = 0;
      let contentLength = 0;

      const doSettle = (err?: Error): void => {
        if (settled) {
          return;
        }
        settled = true;
        request.destroy();
        if (err) {
          LogUtil.error(`[ApiService] downloadFile failed: ${err.message}`);
          reject(err);
        } else {
          LogUtil.info(`[ApiService] downloadFile completed: ${sourcePath}`);
          resolve();
        }
      };

      request.on('headerReceive', (header: object) => {
        if (!header) {
          return;
        }
        const h = header as Record<string, Object>;
        const cl = h['Content-Length'];
        if (cl !== undefined) {
          contentLength = typeof cl === 'number' ? cl : parseInt(String(cl), 10);
        }
      });

      request.on('dataReceive', (chunk: ArrayBuffer) => {
        if (settled) {
          return;
        }
        totalBytes += chunk.byteLength;
        if (contentLength > 0) {
          onProgress({ progress: Math.round((totalBytes / contentLength) * 100) });
        }
      });

      request.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json'
        },
        extraData: body,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      }, (err, data) => {
        if (settled) {
          return;
        }
        if (err) {
          doSettle(new Error(`Download request failed: ${err.message}`));
          return;
        }
        if (data.responseCode !== 200) {
          let errMsg = `HTTP ${data.responseCode}`;
          if (data.result && typeof data.result === 'string') {
            try {
              const errBody = JSON.parse(data.result as string) as Record<string, string>;
              errMsg = `${errBody.code || 'UNKNOWN'}: ${errBody.message || errMsg}`;
            } catch {
              errMsg = `HTTP ${data.responseCode}`;
            }
          }
          doSettle(new Error(errMsg));
          return;
        }
        try {
          const stream = fileIo.createStreamSync(destPath, 'w');
          if (data.result !== null && data.result !== undefined) {
            stream.writeSync(data.result as ArrayBuffer);
          } else {
            LogUtil.warn(`[ApiService] downloadFile empty response body: ${sourcePath}`);
          }
          stream.closeSync();
        } catch (e) {
          LogUtil.error(`[ApiService] downloadFile save failed: ${(e as Error).message}, resultType=${typeof data.result}`);
          doSettle(new Error(`Failed to save file: ${(e as Error).message}`));
          return;
        }
        onProgress({ progress: 100, done: true });
        doSettle(undefined);
      });
    });
  }

  async downloadBatch(
    paths: string[],
    destination: string,
    onProgress: (progress: DownloadProgress) => void
  ): Promise<void> {
    const url = `${ApiService.BASE_URL}/download/batch`;
    const body = JSON.stringify({
      paths: paths,
      destination: destination
    });
    LogUtil.info(`[ApiService] downloadBatch: paths=${JSON.stringify(paths)}`);

    return new Promise((resolve, reject) => {
      const request = http.createHttp();
      let buffer = '';
      let settled = false;
      const doSettle = (err?: Error): void => {
        if (settled) {
          return;
        }
        settled = true;
        request.destroy();
        if (err) {
          LogUtil.error(`[ApiService] downloadBatch failed: ${err.message}`);
          reject(err);
        } else {
          LogUtil.info(`[ApiService] downloadBatch completed`);
          resolve();
        }
      };

      request.on('dataReceive', (chunk: ArrayBuffer) => {
        const text = ApiService.arrayBufferToString(chunk);
        buffer += text;
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          if (!line.trim()) {
            continue;
          }
          try {
            const parsed = JSON.parse(line) as DownloadProgress;
            LogUtil.debug(`[ApiService] downloadBatch progress: ${JSON.stringify(parsed)}`);
            if (parsed.error) {
              doSettle(new Error(parsed.error));
              return;
            }
            onProgress(parsed);
            if (parsed.done) {
              doSettle(undefined);
              return;
            }
          } catch (e) {
            LogUtil.warn(`[ApiService] downloadBatch parse line failed: ${line}`);
          }
        }
      });

      request.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/x-ndjson'
        },
        extraData: body
      }, (err, data) => {
        if (settled) {
          return;
        }
        if (err) {
          doSettle(new Error(`Batch download request failed: ${err.message}`));
          return;
        }
        if (data.responseCode !== 200) {
          doSettle(this.parseError(data.result as string, data.responseCode));
          return;
        }
        if (buffer.trim()) {
          try {
            const parsed = JSON.parse(buffer) as DownloadProgress;
            if (parsed.error) {
              doSettle(new Error(parsed.error));
              return;
            }
            onProgress(parsed);
            if (parsed.done) {
              doSettle(undefined);
              return;
            }
          } catch {
            // ignore
          }
        }
        doSettle(undefined);
      });
    });
  }

  private static arrayBufferToString(buffer: ArrayBuffer): string {
    const uint8 = new Uint8Array(buffer);
    let result = '';
    for (let i = 0; i < uint8.length; i++) {
      result += String.fromCharCode(uint8[i]);
    }
    return result;
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
