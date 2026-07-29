# 飞天茅台抢购实时报表

一个原生 macOS SwiftUI 数据分析应用，用于统计公开分享表格中的飞天
53%vol 500ml 商品抢购记录，并按 2瓶、4瓶、6瓶展示时间分布。

![macOS](https://img.shields.io/badge/macOS-13%2B-black)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

## 功能

- 原生 SwiftUI + Charts，不依赖网页运行时
- 自动同步与自定义同步间隔
- 30秒至60分钟自定义时间分段
- 柱状图、圆形图、文字结论、捡漏分析、设备/IP统计
- 横向拖动、捏合缩放、鼠标精确时间与单数提示
- 2瓶、4瓶、6瓶每日及跨日汇总
- 时段同比/累计同比，点击文字切换
- 自动结论与一键复制
- 关闭窗口后进程退出

## 数据来源

数据来自维格表公开分享页：

- 分享页：<https://vika.cn/share/shrwqEwPuTFYc2u3VufJ5>
- 应用读取的公开 `dataPack` 接口写在
  [`Sources/FeitianReport/App.swift`](Sources/FeitianReport/App.swift) 顶部的
  `sourceURL` 常量中。

仓库**不包含、缓存或提交原始表格数据**。应用运行时直接读取公开分享源，
仅在内存中完成筛选和聚合。数据内容、可用性与准确性由数据源维护者负责。

更完整的字段和隐私说明见 [`DATA_SOURCE.md`](DATA_SOURCE.md)。

## 脚本

- [`Scripts/build_app.sh`](Scripts/build_app.sh)：编译并生成本地 `.app`
- [`Scripts/run_tests.sh`](Scripts/run_tests.sh)：运行同比计算和界面文案测试
- [`Scripts/install_desktop.sh`](Scripts/install_desktop.sh)：构建并安装到桌面

## 构建

要求：

- macOS 13 或更高版本
- Xcode Command Line Tools

```bash
git clone https://github.com/DJIPORUN/Feitian-Maotai-Report.git
cd feitian-maotai-report
./Scripts/run_tests.sh
./Scripts/build_app.sh
open ./build/飞天茅台实时报表.app
```

安装到桌面：

```bash
./Scripts/install_desktop.sh
```

## 项目结构

```text
Sources/FeitianReport/
  App.swift                 SwiftUI界面、数据同步与图表
  ComparisonLogic.swift     昨日时段/累计同比计算
Scripts/
  build_app.sh              App构建脚本
  install_desktop.sh        桌面安装脚本
  run_tests.sh              测试脚本
Tests/
  ComparisonLogicTests.swift
```

## 说明

本项目是独立的第三方数据可视化工具，与商品品牌方、维格表或数据源维护者
不存在隶属或官方合作关系。请遵守数据源条款并合理设置同步间隔。

## License

[MIT](LICENSE)
