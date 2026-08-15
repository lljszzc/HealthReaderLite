# 贡献指南

感谢你愿意为 HealthReaderLite 贡献！这是一个很小的工具，请保持它"轻"。

## 开发环境

- macOS 15+（推荐 macOS 26）
- Xcode 16+/Swift 6+（命令行 `swift build` 即可，无需打开 Xcode 工程）

```bash
git clone <你的 fork 地址>
cd HealthReaderLite
./Scripts/build_app.sh          # 编译 + 打包 + 签名
open build/HealthReaderLite.app # 运行
```

## 常用命令

```bash
swift build                                       # 调试构建
swift build -c release --scratch-path .build-release \
  --cache-path .spm/cache --config-path .spm/config \
  --security-path .spm/security                   # release 构建
.build-release/release/HealthReaderLite --selftest # 跑全部自测（提交前必跑）
```

> 提示：`swift build` 原生会向系统临时/缓存目录写入；在受限沙箱环境中会被拒绝，正常终端执行即可。

## 提交规范

- 尽量小步提交，一条提交做一件事
- Commit message 用中文或英文均可，建议带前缀：`feat:` `fix:` `perf:` `refactor:` `test:` `docs:`
- 提交前检查：
  1. `swift build` 无 error/warning
  2. `--selftest` 全部通过
  3. 没有把 `.build*`、`.spm/`、`Scripts/out/`、`build/` 等生成物提交进来
  4. 没有遗留调试输出（`print` 只在 `SelfTest` 与 `--xxx-test` 模式中出现）

## 新增功能自测约定

- 解析器/工具类新功能：在 `Sources/HealthReaderLite/SelfTest.swift` 中补充 `check`/`requireEqual` 断言
- 网络相关：提供 `--fetch-test <url>` / `--extract-test <url>` 的冒烟验证入口
- GUI 细节：无法自动化断言的部分，请在 PR 描述中说明手动验证步骤

## 隐私与克制（重要）

- 本项目**零第三方依赖、零遥测**是核心卖点，PR 不要引入网络 SDK / 统计库
- 涉及网络请求的新逻辑，请确认请求最小化且无数据回传
- Docker、大型依赖、引入构建链复杂化的改动需要充分讨论

## PR 流程

1. Fork 本仓库，创建特性分支
2. 提交并推送到你的 fork
3. 发起 Pull Request，描述改动内容与验证方式
4. 保持小步：一次 PR 聚焦一个主题，便于 review

## License

贡献即表示你同意你的代码以 MIT 许可证发布（见 [LICENSE](./LICENSE)）。