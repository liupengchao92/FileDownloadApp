# FileManagerApp

HarmonyOS 应用（Stage 模型，ArkTS）。Bundle：`com.hm.filemanager`。
目标 SDK 6.0.2(22)，兼容 SDK 5.0.0(12)。设备类型：仅 phone。

## 构建

- **构建系统**：Hvigor（非 npm/Gradle）—— 使用 **DevEco Studio** 进行构建/运行；无 CLI 构建脚本。
- **静态检查**：根目录 `code-linter.json5`，检查 `.ets` 文件，规则集包含 `@performance/recommended` + `@typescript-eslint/recommended` 及安全规则。
- **混淆**：Release 构建通过 `entry/obfuscation-rules.txt` 启用（属性/顶层/文件名/导出混淆）。

## 目录结构

```
AppScope/                        — 应用级清单（bundleName, version）
entry/
  src/main/ets/
    entryability/EntryAbility.ets — 主 UIAbility
    pages/Index.ets              — 唯一页面
    entrybackupability/          — 备份扩展能力
  src/test/                      — 本地单元测试（hypium，PC 运行）
  src/ohosTest/                  — 插桩测试（需设备/模拟器）
  src/mock/                      — mock-config.json5（空）
```

## 测试

- 框架：`@ohos/hypium`（`describe`/`it`/`expect`）+ `@ohos/hamock`。
- 两个级别：`src/test/`（本地，PC 运行）和 `src/ohosTest/`（需设备/模拟器）。
- 无 CLI 测试命令——使用 DevEco Studio 测试运行器。

## 语言与导入

- **ArkTS**（`.ets` 文件），非原生 TypeScript。使用 `@Entry`、`@Component`、`@State` 装饰器。
- 标准导入来源：`@kit.AbilityKit`、`@kit.PerformanceAnalysisKit`、`@kit.ArkUI`、`@kit.CoreFileKit`。
- 包管理器：**ohpm**（`oh-package.json5`）。

## 依赖

- 无运行时依赖。仅开发依赖：`@ohos/hypium@1.0.25`、`@ohos/hamock@1.0.0`。
- 无 CI、无 GitHub Actions。
- `.gitignore` 忽略 `oh_modules`、`node_modules`、`build`、`.hvigor`、`.idea`、`local.properties`。
