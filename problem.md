# 租盾

## 发布目标

只上架 **iOS App Store**。安卓不做市场发布，也不做对应合规与打包；
`android/` 目录保留，仅供本机调试用。网页版继续用于协议页与临时体验。

## iOS 上架待办

- [ ] 在 Mac 上跑真机确认本地通知会响（按下面「iOS 通知自检」走一遍）
- [ ] App Store Connect 建 App：Bundle ID `com.zudun.zudun`、主语言简体中文
- [ ] 隐私政策 URL 填
      `https://dmjz-h5.makcabxa02y.icu/dm_agreement.html?type=ZD_PRIVACY_PROTOC&dy=ios`
- [ ] 按 iPhone 尺寸补齐截图（`build/preview/` 里 4 张预览图可作为素材参考）
- [ ] 审核备注写清体验路径：不用账号，点「游客模式进入」即可体验全部功能
      （游客数据只存在本次会话里，退出即清空）
- [ ] 提交前确认服务端两个协议键有正文：`ZD_PRIVACY_PROTOC`、`ZD_REGISTER_PROTOC`
- [ ] （可选）App 级 `PrivacyInfo.xcprivacy`：当前所有插件都自带隐私清单，
      若收到 Apple 的 ITMS-91053 提示，再在 Xcode 里补一份

## iOS 通知自检

1. 设置 → 通知 → 租盾：确认「允许通知」是开的，「提醒」不是「无」
2. App 内：我的 → 提醒设置 → 打开开关 → 点「授权系统通知」→ 系统弹窗选「允许」
3. 点「发一条测试通知」：App 开着时也应看到横幅（前台展示已在代码里显式打开）
4. 状态那行会写「系统里已排好 N 条提醒」；若写「系统一条排期都没接下」，
   下面会直接给出原因，照着改即可

