export class ObjectUtil {
  static cloneRecord<T>(source: Record<string, T>): Record<string, T> {
    const keys = Object.keys(source);
    const result: Record<string, T> = {};
    for (let i = 0; i < keys.length; i++) {
      result[keys[i]] = source[keys[i]];
    }
    return result;
  }

  static removeKey<T>(source: Record<string, T>, key: string): Record<string, T> {
    const keys = Object.keys(source);
    const result: Record<string, T> = {};
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] !== key) {
        result[keys[i]] = source[keys[i]];
      }
    }
    return result;
  }
}
