# 生产源码补丁

`ninfer-4090-stable.patch` 把上游固定基线变成当前验证过的生产源码。

## 基线

```text
repo:    https://github.com/sergiuszm/ninfer-4090.git
branch:  rtx4090-port
commit:  7f47a62282b8e9d3c3b03bd6750d0bfe37e9bb66
```

不要用 `master`，也不要用上游最新 HEAD 直接打补丁。补丁是在上面的 commit 上
生成的；基线不一致时先停下来核对。

## 应用

```bash
git clone https://github.com/sergiuszm/ninfer-4090.git
cd ninfer-4090
git switch -c 4090-stable 7f47a62282b8e9d3c3b03bd6750d0bfe37e9bb66
git apply --3way /path/to/ninfer-4090-deploy/patches/ninfer-4090-stable.patch
```

检查：

```bash
git status --short
git apply --check --reverse /path/to/ninfer-4090-deploy/patches/ninfer-4090-stable.patch
```

## 范围

补丁包含 149 个文件，主要覆盖：

- K15 prompt lookup 的 CLI、缓冲、调度和测试；
- Codex Responses 的兼容字段；
- JSON `json_object` / `json_schema` 的 XGrammar 约束路径；
- 视觉输入；
- 多 lane / MTP3 的调度和采样；
- KV 分页 entitlement 预留；
- worker 异常原地恢复和错误日志；
- 相关测试；
- 裁剪后的 XGrammar 源码（Apache-2.0）。

补丁不包含：

- 模型权重；
- 编译产物；
- 原始 benchmark 日志；
- 本机绝对路径、IP、主机名、GPU UUID；
- 私有启动脚本或密钥。

## 验证

```bash
git apply --check --binary patches/ninfer-4090-stable.patch
grep 'patches/' checksums.txt | sha256sum -c -
```

完整构建和验收见 [`../docs/部署指南.md`](../docs/部署指南.md)。

## 注意

- 补丁中的 XGrammar 是上游 `3641b5c21e70a6c5515ad9eca24fcbee21ee6ad0` 的裁剪
  快照，许可见 [`../licenses/xgrammar-LICENSE`](../licenses/xgrammar-LICENSE)。
- 如果上游以后合并了同等改动，不要盲目重放本补丁；先做 `git apply --check` 和
  数值回归。
- 这个补丁固定的是源码能力，不保证不同编译器产生逐字节相同的二进制；生产验收
  以模型输出、健康检查和客户端任务为准。
