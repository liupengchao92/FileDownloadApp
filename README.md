# FileManagerApp

基于 HarmonyOS（Stage 模型，ArkTS）的远程文件浏览与下载工具。

## 简介

通过 HTTP 连接后端服务器，实现远程目录浏览、文件下载与批量下载功能。

- **Bundle**: `com.hm.filemanager`
- **目标 SDK**: 6.0.2(22)
- **兼容 SDK**: 5.0.0(12)
- **设备类型**: Phone

## 功能

- 远程目录浏览（面包屑导航、返回上级）
- 单文件下载（显示进度 / 完成 / 错误状态）
- 批量多选下载（服务端打包 ZIP，本地自动解压）
- 下拉刷新
- 下载失败自动重试（指数退避，最多 3 次）

## 架构

```
Index.ets (Page)
  ├── EntryAbility.ets
  ├── FileListViewModel      — 状态管理（文件列表、多选、下载状态）
  ├── FileRowComponent       — 列表行组件（图标、名称、大小、下载指示器）
  ├── DownloadManager        — 下载调度（队列、并发 3、重试、观察者模式）
  ├── ApiService             — HTTP 层（文件列表查询、单文件/批量下载）
  └── FileUtils              — 文件系统工具（沙箱路径、解压、格式化）
```

## 后端 API

服务端地址：`http://192.168.115.144:3000/api`

服务端源码：[FileManagerSystem](https://github.com/liupengchao92/FileManagerSystem)

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/files?path=...` | GET | 获取目录文件列表 |
| `/api/download/file?path=...` | GET | 下载单个文件 |
| `/api/download/batch?paths=...` | GET | 批量下载（返回 ZIP） |

## 构建

使用 **DevEco Studio** 打开项目根目录，同步 ohpm 依赖后运行。

- 构建系统：Hvigor
- 无运行时依赖，仅开发依赖：`@ohos/hypium`、`@ohos/hamock`
- Release 构建启用混淆（规则见 `entry/obfuscation-rules.txt`）

## 测试

- 本地单元测试：`entry/src/test/`（PC 运行，hypium）
- 插桩测试：`entry/src/ohosTest/`（需设备/模拟器）
