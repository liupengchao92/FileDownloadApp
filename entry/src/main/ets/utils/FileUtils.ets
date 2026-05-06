import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { LogUtil } from './LogUtil';

export class FileUtils {
  private static sandboxRoot: string = '';

  static init(context: common.Context): void {
    FileUtils.sandboxRoot = `${context.filesDir}/ServerMirror`;
    LogUtil.info(`FileUtils initialized, sandboxRoot: ${FileUtils.sandboxRoot}`);
  }

  static getSandboxRoot(): string {
    return FileUtils.sandboxRoot;
  }

  static buildLocalPath(relativePath: string): string {
    const normalized = relativePath.replace(/\\/g, '/').replace(/^\/+/, '');
    const segments = normalized.split('/').filter(s => s !== '..');
    const safePath = segments.join('/');
    const fullPath = `${FileUtils.sandboxRoot}/${safePath}`;
    LogUtil.debug(`buildLocalPath: ${relativePath} -> ${fullPath}`);
    return fullPath;
  }

  static async ensureDir(filePath: string): Promise<void> {
    const dir = filePath.substring(0, filePath.lastIndexOf('/'));
    if (!dir) {
      return;
    }
    try {
      if (!fileIo.accessSync(dir)) {
        await fileIo.mkdir(dir, true);
      }
      LogUtil.debug(`ensureDir success: ${dir}`);
    } catch (e) {
      if (e.code !== 139000015) {
        LogUtil.error(`ensureDir failed: ${dir}, error: ${e.message}`);
        throw e as Error;
      }
    }
  }

  static async fileExists(filePath: string): Promise<boolean> {
    try {
      await fileIo.stat(filePath);
      return true;
    } catch {
      return false;
    }
  }

  static formatFileSize(bytes: number): string {
    if (bytes === 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    const size = bytes / Math.pow(1024, i);
    return `${size.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
  }

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

  static async checkStorageSpace(requiredBytes: number): Promise<boolean> {
    try {
      await fileIo.mkdir(FileUtils.sandboxRoot, true);
      return true;
    } catch {
      return true;
    }
  }

  static async removeTempFile(filePath: string): Promise<void> {
    try {
      await fileIo.unlink(filePath);
      LogUtil.debug(`removeTempFile: ${filePath}`);
    } catch {
      // ignore
    }
  }

  static async renameFile(oldPath: string, newPath: string): Promise<void> {
    try {
      await fileIo.moveFile(oldPath, newPath);
      LogUtil.debug(`renameFile success: ${oldPath} -> ${newPath}`);
    } catch {
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
}
