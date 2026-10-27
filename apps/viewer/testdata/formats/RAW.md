# RAW 测试图片

| 文件 | 类型与正确性断言 |
| --- | --- |
| raw_canon_white_paper.cr2 | 仓库原 sample.cr2，真实 Canon 拍摄的玩具与白纸。检查白纸 sRGB 通道 0.65–0.99、线性值 >0.4、SDR 与线性转 sRGB 一致；真实窗口检查比例、亮度、自动 HDR 开关及 SDR 底图 |
| raw_nikon_d2h.nef | Nikon D2H，12-bit 有损压缩 NEF，真实色卡。检查六阶灰度递减、近中性色偏范围、白/黑卡亮度及 RGB 原色色块关系；另查比例、有限浮点值和 alpha |
| raw_sony_a7s.arw | Sony ILCE-7S，14-bit 压缩 ARW，APS-C 裁切风景。检查比例、有效有限浮点及 alpha；目前只作显影兼容性/几何验证，没有独立的绝对颜色参考 |
| raw_bayer_no_preview.dng | 自有 256×192 无嵌入预览 Bayer DNG。检查 CFA 显影、颜色关系、渐变、16-bit 输出、线性高光/负分量和缩略图比例，不能用预览图冒充显影 |
| raw_bayer_rotated.dng | 同一传感器数据，EXIF 方向 6。逐分量核对旋转坐标 |
| raw_bayer_underexposed.dng | 同一自有色卡降低两档传感器曝光，保留黑位。检查有用亮度、颜色关系及 SDR/HDR 非裁切分量的曝光一致性 |
| raw_bayer_black.dng | 自有纯黑传感器，所有 CFA 值等于 BlackLevel。SDR 与线性 RGB 必须全零，不能错误拉伸到白色 |

用例：`test/raw_developer_test.dart`、`test/format_fixture_catalog_test.dart`、`integration_test/raw_display_test.dart`。生成自有 DNG：`dart run tool/generate_raw_fixture.dart`。来源不同的真实相机照片不能用统一白纸亮度阈值替代场景预期。

## 新增真实相机样本来源

2026-10-20 从 [raw.pixls.us 样本库](https://raw.pixls.us/) 下载，库内对应条目均标为 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)，文件未修改，只更名。下载后逐一核对库中公布的 SHA-256。保留以下来源与校验，便于追溯；不要将其他许可条目混入本组。

- NEF：[条目 5227 原始文件](https://raw.pixls.us/getfile.php/5227/nice/Nikon%20-%20D2H%20-%2012bit%2012bit%20compressed%20%28Lossy%20%28type%201%29%29%20%283%3A2%29.NEF)，原名 D2H_3957.NEF，色卡场景。SHA-256：`155edb938f884ea7372ce98d4ff5f965c3e413b43b95bc9923da6e92082cf914`。
- ARW：[条目 1582 原始文件](https://raw.pixls.us/getfile.php/1582/nice/Sony%20-%20ILCE-7S%20-%2014bit%2014bit%20compressed%20%283%3A2%29.ARW)，原名 DSC04126.ARW。SHA-256：`a35ebb2fbec929daa5beb20d1ce5c15a8aac7b1a7a231455387f3df8a7442e07`。

CR2 为既有仓库资产，本次只更名，不将其来源或许可追认为 CC0。当前覆盖 CR2、NEF、ARW、DNG 四种真实 RAW 容器；没有用改扩展名的 DNG 假装其他厂商格式，也不据此宣称覆盖所有机型。
