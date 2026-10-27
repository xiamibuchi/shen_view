# 照片元数据样本

设备样本来自 [ianare/exif-samples](https://github.com/ianare/exif-samples/tree/f0462fcc42f7bad484fe637389b734612d97041f)。文件按上游字节保存，只更名，没有重编码或补写元数据。上游可能已处理部分字段，因此这些样本用于设备文件兼容性回归，不作为厂商全部输出或绝对颜色参考。

上游 [贡献许可说明](https://github.com/ianare/exif-samples/blob/f0462fcc42f7bad484fe637389b734612d97041f/README.rst) 将用户贡献的图片按 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) 发布。以下保留作者、原始位置和提交记录。

| 本地文件 | 作者与原始文件 |
| --- | --- |
| iphone_13_pro_max.heic | Anand Mahesh（[manand881](https://github.com/manand881)），[原始文件](https://github.com/ianare/exif-samples/blob/f0462fcc42f7bad484fe637389b734612d97041f/heic/mobile/iphone_13_pro_max.HEIC)，[贡献记录](https://github.com/ianare/exif-samples/commit/f0462fcc42f7bad484fe637389b734612d97041f) |
| nokia_8_3.heif | Antti Ketola（[alketola](https://github.com/alketola)），[原始文件](https://github.com/ianare/exif-samples/blob/f0462fcc42f7bad484fe637389b734612d97041f/heic/mobile/HMD_Nokia_8.3_5G.heif)，[贡献记录](https://github.com/ianare/exif-samples/commit/4aaa6e257ee57a4a87f06fe8647b78e65f3964ba) |
| nokia_8_3.jpg | Antti Ketola（[alketola](https://github.com/alketola)），[原始文件](https://github.com/ianare/exif-samples/blob/f0462fcc42f7bad484fe637389b734612d97041f/jpg/mobile/HMD_Nokia_8.3_5G.jpg)，同一贡献记录 |

SHA-256：

```text
e760c80eed310e4f27c092d5487693ca8e104e7cc01d25ba4828deb28f679676  iphone_13_pro_max.heic
c2820b3e4e0368c6f031b28b62945658a97446895cb446dfc37acdcf7109e0f5  nokia_8_3.heif
9be023624ccd5846beeb5b02d9b571251ef5bd8ed820389a430d114029f58eda  nokia_8_3.jpg
```

`display_p3.icc` 是自有标准 Display P3 矩阵／sRGB TRC 配置，按 CC0 提供。它由 Little CMS 生成，不来自显示器配置。生成命令：构建 `viewer_color_profile_test` 后运行 `viewer_color_profile_test --fixtures apps/viewer/testdata/photo_metadata`。

元数据断言见 `test/photo_metadata_test.dart`，APNG 的实际像素与透明度断言见 `test/apng_color_profile_test.dart`。曝光、时间与色彩名称用独立工具交叉核对；GPS 直接核对原始 TIFF 有理数，不使用会重复数组首项的 ImageMagick 属性字符串作为基准。既有 Nikon、Sony RAW 原片的来源见 [RAW 样本说明](../formats/RAW.md)。这些用例不代表覆盖所有机型、MakerNotes 或特殊色彩配置。
