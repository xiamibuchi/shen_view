# ShenView 文档

应用介绍与运行命令见 [项目 README](../README.md)。文档按用途分类：

| 分类 | 内容 |
| --- | --- |
| [功能使用](#功能使用) | 浏览、阅读、窗口和工具的实际行为 |
| [技术实现](#技术实现) | 解码、调度、缓存和压缩包 |
| [设计规范](#设计规范) | 界面规则、共享组件和品牌资源 |
| [开发与验证](#开发与验证) | 环境准备、质量检查、专项测试和 Windows 回归 |
| [发布资料](#发布资料) | 分发范围、许可维护和商店文案 |

## 功能使用

- [查看方式、缩放与阅读规则](guide/zoom-and-view-modes.md)
- [文件夹与目录导航](guide/folder-navigation.md)
- [网格总览](guide/grid-overview.md)
- [自动播放](guide/auto-play.md)
- [颜色拾取](guide/color-picker.md)
- [信息面板与直方图](guide/histogram.md)
- [打开、最近记录、窗口与文件操作](guide/window-and-file-operations.md)
- [实例模式](guide/multi-instance.md)

## 技术实现

- [项目结构](architecture/project-layout.md)：工程边界、脚本入口与依赖管理。

- [图片解码](architecture/image-decoding.md)：当前后端路由和回退。
- [调度、预加载与缓存](architecture/resources.md)：主图优先、缩略图策略和资源边界。
- [压缩包](architecture/archives.md)：条目会话、嵌套、固实包与磁盘缓存。
- [RAW 解码](architecture/raw-decoding.md)：主图显影、内嵌预览和亮度回归。
- [HDR 显示](architecture/hdr-rendering.md)：输入、原生显示、SDR 回退和验收边界。
- [SVG 渲染](architecture/svg-rendering.md)：resvg / WebView 分流、截图与失败保底。

## 设计规范

- [界面设计规范](design/spec.md)
- [品牌预览](design/preview.html) / [预览图片](design/preview.png)
- [品牌规范、资源与生成方式](../branding/README.md)

## 开发与验证

- [开发环境、配置排查与代码约束](development/getting-started.md)
- [验证入口与验收边界](development/validation.md)
- [Windows 真机回归](development/windows-regression.md)

## 发布资料

- [分发范围与待完成事项](release/distribution.md)
- [压缩包分发许可](release/archive-licensing.md)
- [开源许可维护](release/open-source-licenses.md)
- 应用商店文案：[简体中文](release/store-listing.zh-CN.md) / [English](release/store-listing.en-US.md)

## 维护方式

功能说明保留使用方法、容易误解的行为和限制。配置字段、枚举、运行默认值、完整键位与参数阈值
以源码和应用内设置为准，文档引用对应入口，不再复制清单或 JSON 示例。

技术说明保留跨模块机制、取舍和平台边界。测试命令集中在开发与验证目录，
样本生成和验收方法留在 testdata；不逐份复述测试用例。设计规则和品牌资源各维护一处。

已被实现替代的调研、一次性检查流水和失效截图链接不继续维护；需要追溯时查看 Git 历史。
尚未实现的交付范围标明状态，避免将方案写成已有能力。
