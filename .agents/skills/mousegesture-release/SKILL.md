---
name: mousegesture-release
description: 在 MouseGesture 项目中响应“发布新版”“发个版本”等指令，自动更新版本和构建号、编写更新记录、推送提交与标签，等待 GitHub CI 完成 Universal 安装包和 Sparkle 更新源的正式发布。
---

# MouseGesture 发布新版

从当前仓库根目录执行。“发布新版”即授权完成以下步骤直到公开 Release 验收通过。打包和签名由 GitHub CI 完成；请求仅涉及发布时，在验收后结束。

1. **确定发布范围和基线。** 检查工作区、暂存区、当前分支及上游；获取 `origin/main` 和远端标签，用 `gh release view` 确认最近正式版。对照该标签到待发布提交的日志、差异，以及本次明确要发布的本地修改。只纳入本次发布的文件，保留无关工作。常规从最新 `main` 发布；落后时快进，分叉或候选改动归属不明时先厘清。
2. **确定版本，兼顾续跑。** 沿用用户指定的新版本；未指定时以最新稳定版递增 patch。若当前提交、版本文件、更新记录或已有标签表明本次发版已准备或推送，沿用该版本，补齐未完成步骤。比较标签解引用后的提交 SHA；同一标签已经公开且对应本次提交时直接验收。远端同名标签指向其他提交时，保留它，先核对是否有并发发布。仅当既无待发布差异，也无待完成的发布时结束。标签已推送但 CI 或 Release 尚未完成时，直接继续第 5、6 步。
3. **改版本、写更新记录。** `Resources/Info.plist` 的 `CFBundleShortVersionString` 使用不带 `v` 的版本，整数 `CFBundleVersion` 在上一次发布的构建号基础上加一并保持单调递增；已正确预置时不重复递增。按 `CHANGELOG.md` 现有格式在顶部写入唯一的 `## X.Y.Z · YYYY-MM-DD` 章节，使用本次发布日期和实际用户可见的变化。用 `plutil -lint Resources/Info.plist`、`python3 scripts/release-notes.py "v$version"` 验证格式和 CI 最终使用的正文。检查实际暂存差异与 `git diff --cached --check`；完整核心测试和双架构类型检查由 CI 的 `scripts/check.sh` 执行。
4. **推送发布提交和标签。** 使用中文提交信息；在确定的发布提交创建带说明的标签 `vX.Y.Z`。首次推送可用 `git push --atomic origin main "refs/tags/v$version"` 同步分支及标签。已经完成的提交、标签或推送直接复用。再核对远端分支及标签落在预期提交。保留既有标签历史，避免强推。
5. **跟踪标签触发的 CI。** 读取 `.github/workflows/ci.yml` 的实际流程。分支、标签同时推送会有两条 run，只有标签 run 会正式发布。用 `gh run list --workflow ci.yml --event push --commit "$sha" --json databaseId,headBranch,headSha,status,conclusion,url` 找到 `headBranch == vX.Y.Z` 且 SHA 匹配的记录；尚未出现就稍后重查。在该 run 上执行 `gh run watch "$id" --exit-status`，连接中断时重新查询同一 ID。检查 `check`、`package`、`release` 均成功。失败时读取对应 job 日志，确认草稿与附件状态；临时故障可对同一 run 重跑失败任务。需要修代码时保留旧标签，修复后用新版本及构建号；涉及冲突引用、签名密钥替换或发布权限时说明具体阻塞。
6. **验收实际更新源。** 用 `gh release view "$tag" --json tagName,isDraft,isPrerelease,assets,url` 和 `gh api "repos/{owner}/{repo}/releases/latest"` 核对公开正式版。对应版本的 Universal ZIP、DMG、`SHA256SUMS.txt`、`appcast.xml` 均应已上传且非空。从 plist 的 `SUFeedURL` 读取公开更新源，核对其中的构建号、展示版本、当前标签下的 Universal ZIP URL、长度及 Sparkle 签名。比对公开 XML 的 SHA-256 与该 Release 的摘要；CI 的 `scripts/sign-appcast.sh` 已验签更新源，并用内嵌公钥验证 ZIP。完成后报告版本、构建号、提交、CI 和 Release 链接，以及任何未通过的检查。
