---
name: explore-loop
description: Run a measured improvement campaign on any project (speed, accuracy, memory, size) as a loop of small experiments - read-only investigators propose, a contract fixes the prediction and the files that may change, isolated implementers build, an independent reviewer and a landing gate decide, every result goes in a ledger. Use when asked to optimize or tune something measurable over many rounds, to "explore", "跑探索循环", "展开优化", "多轮实验", or to set up / resume / audit such a campaign.
---

# explore-loop

一个 CLI：本目录的 `./explore`（Python 3.11+，只用标准库）。从 skill 加载时显示的 "Base directory" 运行。
源在 `outman.me` 仓库的 `skills/explore-loop/`，这里是安装的副本：改源、推送，再在各机器上 `git pull && scripts/install.sh`。不改副本。

出处：TabbyML《Beating ClickBench SOTA with a team of agentic systems engineers》。流程在 `workflow.md`，派活的说明在 `roles.md`。

## 分工

| 谁定 | 定什么 |
|---|---|
| 所有者 | 目标、重点、不做什么、停止条件；破例；战役分支并不并回主分支 |
| `explore`（工具） | 能不能量、能不能比、能不能落地。负责人也绕不过 |
| 评审（另一个模型） | 合同写得对不对；补丁有没有测试没覆盖的行为变化 |
| 负责人（主会话） | 派活、写合同、整理账本。不写产品代码，不直接合并 |

## 开一场战役

战役目录放在目标项目的仓库里并提交（例如 `<仓库>/explore/<名称>/`），这样合同、账本、证据都跟着项目走。

1. `explore init <仓库>/explore/<名称>`，然后填 `explore.toml`（命令、不变量、锁定路径、数据集）和 `profile.md`（目标、重点、约束表）。
   目标和重点问所有者，不要自己从"现成能量的东西"里挑。
2. 建战役分支和基线 worktree（`git worktree add <路径> -b explore/base <起点>`）。
3. `explore doctor --snapshot`，再 `explore aa`。**A/A 不过就先修测量**：加遍数、设 `floor`、清掉机器上的别的负载。
   `doctor` 把每条约束标成 `ok` 或 `仅文字`：仅文字的那些没人拦，告诉所有者。
4. 照 `workflow.md` 一轮一轮跑，每个角色的说明照抄 `roles.md`。

## 每个实验必经的三步

```sh
explore check experiments/E007.md rounds/R02/proposals-*.md   # 合同、提案、评审结尾的 json 块合不合格
explore land E007 <候选 worktree> --dry-run                  # 验证员交回前自己先过一遍
explore land E007 <候选 worktree>                            # 全过才快进合并，并写账本
```

`land` 依次核对：做过 A/A → 候选包含当前基线 → 只改了合同 `allowed` 里的文件 → `locked` 路径没变 → 测试 → 每条不变量 →
评审针对的就是这个提交且没有挡合并的发现 → 重新构建并交替测量，合同的目标指标全部"变好"、其余无回归。
没过判定规则而所有者同意破例：`--owner-ok "<所有者的原话>"`，账本里记为破例。其余几项没有破例。
不落地的实验用 `explore close E007 --as 放弃|拒绝|改向 --why …`。`explore status` 是账本，带每个实验的预测对实测。

## 工具管不了的（照做，并写进报告）

- **留出集挡不住读取。** 没有沙箱时只能做到：放在仓库之外、只经 `explore holdout` 访问、每次记账并在重复使用时警告。
- **只读靠事后发现。** `locked` 是落地时核对指纹，不是事前拦截。要事前拦，用文件权限或目标仓库自己的钩子。
- **筛选环境不是产品。** 模拟器、小图、开发机上的结论，落地前在档案写的验收环境里再量一次；量不了就在报告里写明。
- **性能不交给 CI 判。** CI 只跑测试。
- 还没做成代码、只在模板里的：缓存失效键、结果按"提交 + 配置 + 数据"寻址、不可逆动作白名单、报告生成。

## 自检

`./explore selftest`（判定规则）和 `./test.sh`（玩具仓库里把闸门该放的放、该拦的拦走一遍）。改了 `explore` 两个都要过。
