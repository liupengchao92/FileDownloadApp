import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { zlib as zip } from '@kit.BasicServicesKit';
import { LogUtil } from './LogUtil';

/**
 * 文件工具类
 * 提供文件系统操作的封装，包括：
 * - 沙盒根目录管理
 * - 路径安全校验（防止路径遍历攻击）
 * - 目录创建、文件重命名、临时文件清理
 * - 文件大小/日期格式化
 * - ZIP 解压
 */
export class FileUtils {
  /** 沙盒根目录路径，init() 时由应用上下文确定 */
  private static sandboxRoot: string = '';

  /**
   * 初始化沙盒根目录
   * 路径为 {应用filesDir}/gtdata，所有下载文件保存在此目录下
   * @param context 应用上下文
   */
  static init(context: common.Context): void {
    FileUtils.sandboxRoot = `${context.filesDir}/gtdata`;
    LogUtil.info(`FileUtils initialized, sandboxRoot: ${FileUtils.sandboxRoot}`);
  }

  /** 获取沙盒根目录路径 */
  static getSandboxRoot(): string {
    return FileUtils.sandboxRoot;
  }

  /**
   * 将服务端相对路径转换为本地沙盒绝对路径
   * 安全处理：过滤掉 '..' 防止路径遍历攻击
   *
   * @param relativePath 服务端文件的相对路径（如 "folderA/sub/file.pdf"）
   * @returns 本地沙盒绝对路径（如 "{sandboxRoot}/folderA/sub/file.pdf"）
   */
  static buildLocalPath(relativePath: string): string {
    // 统一路径分隔符并去除前导斜杠
    const normalized = relativePath.replace(/\\/g, '/').replace(/^\/+/, '');
    // 过滤掉 '..' 路径段，防止目录穿越
    const segments = normalized.split('/').filter(s => s !== '..');
    const safePath = segments.join('/');
    const fullPath = `${FileUtils.sandboxRoot}/${safePath}`;
    LogUtil.debug(`buildLocalPath: ${relativePath} -> ${fullPath}`);
    return fullPath;
  }

  /**
   * 确保目标文件的父目录存在
   * 如果目录不存在则递归创建
   * @param filePath 文件的完整路径（会自动提取父目录）
   */
  static async ensureDir(filePath: string): Promise<void> {
    const dir = filePath.substring(0, filePath.lastIndexOf('/'));
    if (!dir) {
      return;
    }
    try {
      if (!fileIo.accessSync(dir)) {
        // 递归创建目录（第三个参数 true 表示递归创建）
        await fileIo.mkdir(dir, true);
      }
      LogUtil.debug(`ensureDir success: ${dir}`);
    } catch (e) {
      // 错误码 139000015 表示目录已存在，忽略即可
      if (e.code !== 139000015) {
        LogUtil.error(`ensureDir failed: ${dir}, error: ${e.message}`);
        throw e as Error;
      }
    }
  }

  /** 检查文件是否存在 */
  static async fileExists(filePath: string): Promise<boolean> {
    try {
      await fileIo.stat(filePath);
      return true;
    } catch {
      return false;
    }
  }

  /**
   * 格式化文件大小为人类可读格式
   * @param bytes 文件大小（字节）
   * @returns 如 "1.5 MB"、"320 KB"
   */
  static formatFileSize(bytes: number): string {
    if (bytes === 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    const size = bytes / Math.pow(1024, i);
    return `${size.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
  }

  /**
   * 格式化 ISO 日期字符串为本地化格式
   * @param isoString ISO 8601 格式的日期字符串
   * @returns 如 "2026-04-30 10:20"
   */
  static formatDate(isoString: string): string {
    try {
      const date = new Date(isoString);
      const y = date.getFullYear();
      const m = String(date.getMonth() + 1).padStart(2, '0');
      const d = String(date.getDate()).padStart(2, '0');
      const h = String(date.getHours()).padStart(2, '0');
      const min = String(date.getMinutes()).padStart(2, '0');
      return `${y}-${m}-${d} ${h}:${min}`;
    } catch {
      return isoString;
    }
  }
  /**
   * 删除临时文件（静默失败）
   * 下载失败或取消时调用，清理 .tmp 文件
   */
  static async removeTempFile(filePath: string): Promise<void> {
    try {
      await fileIo.unlink(filePath);
      LogUtil.debug(`removeTempFile: ${filePath}`);
    } catch {
      // 忽略删除失败（文件可能不存在）
    }
  }

  /**
   * 重命名文件（移动文件）
   * 优先使用 moveFile，失败时降级为 copyFile + unlink
   * @param oldPath 源路径（通常是 .tmp 临时文件）
   * @param newPath 目标路径（最终文件路径）
   */
  static async renameFile(oldPath: string, newPath: string): Promise<void> {
    try {
      await fileIo.moveFile(oldPath, newPath);
      LogUtil.debug(`renameFile success: ${oldPath} -> ${newPath}`);
    } catch {
      // moveFile 失败（可能跨文件系统），降级为复制+删除
      try {
        await fileIo.copyFile(oldPath, newPath);
        await fileIo.unlink(oldPath);
        LogUtil.debug(`renameFile via copy: ${oldPath} -> ${newPath}`);
      } catch (e) {
        LogUtil.error(`renameFile failed: ${oldPath} -> ${newPath}, error: ${e.message}`);
        throw e as Error;
      }
    }
  }

  /**
   * 生成批量下载的临时 ZIP 文件路径
   * 格式：{sandboxRoot}/.batch_{timestamp}.zip
   */
  static getBatchZipPath(): string {
    const timestamp = Date.now();
    return `${FileUtils.sandboxRoot}/.batch_${timestamp}.zip`;
  }

  /**
   * 提取多个路径的公共父目录前缀
   * 用于批量下载时确定 ZIP 解压目标目录，确保文件保存在正确的父目录下
   *
   * @param paths 文件相对路径数组，如 ["documents/projectA", "documents/projectB"]
   * @returns 公共前缀，如 "documents"；无公共前缀时返回空字符串
   */
  static getCommonPrefix(paths: string[]): string {
    if (paths.length === 0) {
      return '';
    }
    // 将每个路径按 '/' 分割为段
    const segmentsList: string[][] = paths.map(p => p.split('/'));
    // 取最短路径的长度作为比较上限
    const minLen = Math.min(...segmentsList.map(s => s.length));
    const common: string[] = [];
    for (let i = 0; i < minLen; i++) {
      const seg = segmentsList[0][i];
      // 仅比较到倒数第二段（最后一段是文件/文件夹名，不作为公共前缀）
      if (i === minLen - 1) {
        break;
      }
      let allMatch = true;
      for (let j = 1; j < segmentsList.length; j++) {
        if (segmentsList[j][i] !== seg) {
          allMatch = false;
          break;
        }
      }
      if (allMatch) {
        common.push(seg);
      } else {
        break;
      }
    }
    return common.join('/');
  }

  /**
   * 解压 ZIP 文件到指定目录
   * 使用 @kit.BasicServicesKit 的 zlib.decompressFile
   * 解压后会保持 ZIP 内的目录结构
   *
   * @param zipPath ZIP 文件路径
   * @param destDir 解压目标目录
   */
  static extractZip(zipPath: string, destDir: string): Promise<void> {
    LogUtil.info(`extractZip: ${zipPath} -> ${destDir}`);
    return new Promise((resolve, reject) => {
      zip.decompressFile(zipPath, destDir, (err: BusinessError) => {
        if (err) {
          LogUtil.error(`extractZip failed: ${err.message}`);
          reject(new Error(`Extract failed: ${err.message}`));
        } else {
          LogUtil.info(`extractZip success`);
          resolve();
        }
      });
    });
  }
}
