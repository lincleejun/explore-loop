---
name: explore-loop
description: Run measured improvement experiments on any project (speed, accuracy, memory, size) - each change gets a contract with a target metric and the files it may touch, is measured in pairs against the baseline, and lands only through a gate; every attempt is logged. Scales from one quick experiment to a multi-round campaign with read-only investigators and independent review. Use when asked to optimize or tune something measurable, to "explore", "跑探索循环", "展开优化", "多轮实验", or to set up / resume / audit such a campaign.
---

# explore-loop

一个 CLI：本目录的 `./explore`（Python 3.11+，只用标准库）。源在 `outman.me` 仓库的 `skills/explore-loop/`，这里是安装的副本，不改副本。
它管三件事：**量得对不对、能不能落地、记没记账。** 想做什么实验、怎么实现，由你和所有者定。

## 一个实验（quick，默认）

```sh
explore init ~/wt/<名称> --repo <仓库> --measure '<打印指标行的命令>' --test '<测试命令>' [--build '<构建命令>']
cd ~/wt/<名称>            # 战役目录。之后的命令都在这里敲
explore aa                 # 校准一次：量出每个指标的噪声
explore new "去掉逐点的临时数组" --target "region year" --allow 'src/geo/*' --predict 0.23
#   → 实验编号、合同、候选的 worktree。在合同里写假设和不能变的东西，在 worktree 里实现并提交
explore land E001          # 范围 → 测试 → 不变量 → 成对测量 → 判定 → 快进合并 → 记账。不过就告诉你拦在哪
```

不知道下一步：`explore next`。看账本：`explore status`。不想落地：`explore close E001 --as 放弃|拒绝|改向 --why …`。

- **指标行**由测量命令打印：`PERF <名称> <数字> <s|ms>`，或 `METRIC <lower|higher|exact> <名称> <值> <单位>`（准确率用 higher，校验值用 exact）。
- **`init` 不碰主检出**：它在仓库里建两条分支、两个 worktree。`~/wt/<名称>/` 放合同、账本、测量日志（分支 `explore/<名称>-log`，随时提交）；
  `~/wt/<名称>-base/` 是基线（分支 `explore/<名称>-base`）。候选在 `~/wt/<名称>-E001/`。
- **worktree 必须干净才量**：构建和测试留下的文件要在仓库的 `.gitignore` 里。
- **`explore power`** 用校准的噪声告诉你：这套判定什么都没变时会误拦多少，真有 2 / 5 / 10 / 20% 的变化时能看出多少。看不出想要的幅度就加 `pairs` 或先降噪声。

## 判定规则和它的数据

基线和候选成对测量（每对随机谁先），默认 10 对。一个指标要**同时**满足两条才算变了：方向显著（精确符号检验，显著线按指标数做 Bonferroni 校正），
而且成对差的中位数超过门槛。目标的门槛是合同的 `min_gain`；其余指标的门槛是容忍度（`guard`%、`floor`、校准噪声三者取大）。
这是 criterion.rs 和 asv 的做法（显著性 + 最小幅度）；10 对起步来自 benchstat（"至少 10，最好 20"）和 Google Benchmark（少于 9 次会警告）。

模拟（15 个指标，`explore power` 可复现）：

| 单次测量的离散 | 对数 | 什么都没变时被误拦 | 目标快 5% 被看出 | 目标快 10% 被看出 | 护栏慢 10% 被拦住 |
|---|---|---|---|---|---|
| 3% | 10 | 0.0% | 29% | 91% | 89% |
| 3% | 20 | 0.0% | 80% | 100% | 99% |
| 8% | 20 | 0.0% | 7% | 47% | 0%（容忍度被噪声抬到约 19%） |

第一版规则（每边 4 个样本、85% 胜率线）在同样条件下：什么都没变时 16% 的落地被误拦，A/A 只有 17% 的概率通过。所以换掉了。
"证据不足"不等于"没有回归"：噪声大的指标当不了护栏，`explore aa` 会点名。

## 闸门还查什么

合同过闸门后没被改过（要改用 `--amend`，留痕）；校准对得上现在的测量命令、规则和环境；候选是干净的提交、包含当前基线、只改了 `allowed` 里的文件；
`locked` 路径没变；测试和每条不变量退出码 0；量完之后候选和基线都还是原来那个提交。同样的提交量过就复用，不能靠重量来碰运气（`--remeasure "理由"` 留痕）。
判定没过而所有者同意破例：`--owner-ok "<所有者的原话>"`，账本里标"破例"。被拦下的每一次也都进账本。

## 战役（多轮、多代理）

把 `explore.toml` 的 `strict` 设为 `true`：落地还需要一份针对这份代码的评审（`experiments/E###.review.md`，另一个模型写）。
流程、角色和可以直接派发的任务说明在 `campaign.md`。先填 `profile.md`：目标和重点问所有者，不要自己从"现成能量的东西"里挑。

## 工具管不了的

闸门防的是疏忽，不防作弊：

- 评审是谁写的、`--owner-ok` 的话是谁说的，工具不知道；两者都留痕，所有者验收时看 `explore status` 里的"破例"和战役分支的提交历史。
- 留出集挡不住读取：只能放在仓库外、只经 `explore holdout` 访问并记账。路径在 `explore.toml` 里，子代理读得到。
- `locked` 是落地时核对文件大小和修改时间，不是事前拦截，也不读内容。
- 只支持"一个仓库、候选是它的 worktree"。测量命令在各自的 worktree 里执行：候选改了测量工具，两边量的就不是一回事，这种改动单独做一个实验并重新校准。
- 筛选环境（模拟器、小输入、开发机）不是产品：落地前在 `profile.md` 写的验收环境里再量一次，量不了就在报告里写明。

## 改这个 skill

`./explore selftest`（判定规则，含纯噪声下的误拦率）和 `./test.sh`（玩具仓库里走完整流程，该拦的要拦，并打印理由）都要过。**不要用管道接它们**：管道会吞掉退出码。
