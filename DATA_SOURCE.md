# 数据来源与字段说明

## 来源

- 平台：维格表公开分享
- 分享地址：<https://vika.cn/share/shrwqEwPuTFYc2u3VufJ5>
- 读取方式：应用运行时请求公开分享页对应的 `dataPack` 数据
- 源码位置：`Sources/FeitianReport/App.swift` 中的 `sourceURL`

## 筛选规则

应用只统计商品名称为：

`飞天53%vol 500ml贵州茅台酒（带杯）`

且数量字段为：

- `2瓶`
- `4瓶`
- `6瓶`

## 使用字段

- 商品名称
- 数量
- 抢购时间
- 型号
- 品牌
- IP地址
- IP属地

设备和IP字段仅用于本地聚合图表。仓库不附带任何原始数据、IP列表、设备列表
或同步后的缓存文件。公开部署、截图或转发报表前，请自行检查是否需要隐藏
设备/IP信息。

## 同步实现

同步与解析逻辑位于：

`Sources/FeitianReport/App.swift`

同比预聚合逻辑位于：

`Sources/FeitianReport/ComparisonLogic.swift`

构建、安装和测试入口位于：

`Scripts/`
