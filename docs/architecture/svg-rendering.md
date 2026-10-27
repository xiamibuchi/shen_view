# SVG 渲染与回退

## 渲染分流

先解析原始 XML/CSS，再判断主图后端；不能用已替换变量或删除字体的预览内容判断。
普通图形、文字、滤镜和裁剪使用 resvg；内嵌字体、CSS 变量、动画、foreignObject
及需浏览器兼容的内容使用 Windows WebView2 或 macOS WKWebView。

每个窗口只保留一个可复用 WebView，供活动主图使用。双页和连续阅读的其他页使用位图，
离开复杂 SVG 后空闲释放。缩略图先用近似预览，主图就绪后更新为一次性截图，
不创建额外浏览器，也不持续截取动画。UI 品牌和信息图标预先生成 PNG，见
[品牌资源](../../branding/README.md)。

## 缩放与截图

SVG 位于固定固有尺寸的 srcdoc iframe，保留原始 viewBox 与偏移。
窗口、DPI 和缩放只调整外层合成表面，不重载文档，避免 vw/vh、媒体查询与内嵌字体重新排版。
状态栏比例由查看器统一计算，WebView 清晰度另受表面预算限制，超过预算仍保持正确显示比例。

等待字体与绘制就绪后截图，缩小并通知已挂载缩略图更新。取色可另取当前帧。
尚未打开的近似预览可能不准确，动画缩略图仅表示捕获时的一帧。
会话互斥和文档复用见 [WebView 会话](../../apps/viewer/lib/src/application/svg_webview_session.dart)。

## 失败保底

运行环境缺失、原生创建失败、加载超时或浏览器进程失效时，依次尝试当前版本截图、
resvg 静态图，再显示原有错误与重试入口。等待更高清静态图时保留已显示的近似预览。
静态图真正显示后才发出降级 warning，单独截图失败不触发主图降级。

失败会释放原生视图与会话等待状态，重新加载后可再次尝试。
所有加载和截图核对资源版本及代次，过期结果不得恢复失败视图或覆盖下一张图。
Windows 插件缺少进程退出回调时使用活动主图健康检查，不截图也不新增 WebView。

## 边界

文档、截图、编码输入、解压大小、节点数和渲染表面都有上限。缓存与静态输出见
[资源层](../../apps/viewer/lib/src/application/svg_resources.dart)，浏览器表面限制见
[主图视图](../../apps/viewer/lib/src/presentation/svg_live_image.dart)；Flutter 缓存与 WebView 进程内存另计。
压缩包使用逻辑身份隔离截图版本，避免临时解压路径变化造成误复用。

CSP、iframe 沙箱和资源清理共同禁止文件脚本、事件处理器、外部资源、弹窗与权限请求，
允许内嵌 data 字体、位图及片段引用。外部字体需要先内嵌。
gzip 读取不代表完整 SVGZ 文件发现与系统关联；SVG 动画不接入栅格动图时间轴。
macOS 构建和 WKWebView 运行仍需实机验证。

## 构建与运行

resvg CLI 的版本和下载校验由 third_party/dependencies.lock.json 锁定，apps/viewer/tool/install_svg_codecs.dart 负责安装，Windows 与 macOS 构建阶段自动打包。
单独运行测试前可先执行以下命令，架构按实际目标调整：

~~~powershell
cd apps/viewer
dart run tool/install_svg_codecs.dart --arch x64
~~~

SHENVIEW_RESVG 可指定独立 resvg。Windows 需 WebView2 Runtime，缺失时使用静态保底；
安装后重新加载可恢复复杂效果。macOS 使用系统 WKWebView。
插件 CMake 兼容 hook 仅作用于对应目录，上游修复后可移除，不修改 Pub 缓存。
原生测试命令见 [验证入口](../development/validation.md)，样本见 [SVG 输入](../../apps/viewer/testdata/svg)。
