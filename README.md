# explore-loop

A measured improvement loop for agents: profile the baseline, investigate in parallel, have a different agent review each proposal, then verify. `explore` refuses to open or land an experiment until those records exist; it measures the candidate against the baseline in pairs, decides *better / regression / not enough evidence*, lands only what passes, and logs every attempt.

探索循环的工具：每个基线先剖析、多个调查员并行提案、另一个代理审提案，这三步必须做过才能开实验和落地；量得对不对、能不能落地、记没记账也是它的事。

```sh
explore init ~/wt/demo --repo <仓库> --measure '<打印指标行的命令>' --test '<测试命令>' --rounds 10 --width 3   # 深度：几轮；宽度：每轮几个调查员
cd ~/wt/demo
explore aa                                  # 校准：每个指标的噪声
explore next                                # 每个新基线一轮：剖析 → 调查员并行提案 → 另一个代理审提案
explore new "<想法>" --target "<指标>" --by <调查员>   # 编号、一页记录、一个 worktree
explore land E001                           # 验证；过了合进基线，没过告诉你拦在哪
```

完整说明在 [`SKILL.md`](SKILL.md)：一轮怎么走、需要你给什么、怎么验证、判定规则的数据、工具管不了什么。

## 里面有什么

| 文件 | 是什么 |
|---|---|
| `explore` | 整个工具。一个 Python 文件，3.11+，只用标准库，不依赖任何代理框架 |
| `SKILL.md` | 给代理读的说明。带 Claude Code skill 的 frontmatter，正文是普通 Markdown |
| `templates/` | `explore init` 和 `explore new` 用的三个模板 |
| `test.sh` | 端到端自检：在临时仓库里走完整流程，该拦的要拦 |
| `codex.sh` | 让 Codex 只读地当调查员或评审（`[agents]` 里配了 `codex` 时用） |

## 安装

- **命令行**：`npm install -g explore-loop`（需要系统里有 Python 3.11+），或克隆后把 `explore` 放进 `PATH`。
- **Claude Code skill**：`git clone https://github.com/lincleejun/explore-loop ~/.claude/skills/explore-loop`。更新就 `git pull`。
- **pi**：`pi install git:github.com/lincleejun/explore-loop`，或 `pi install npm:explore-loop`（仓库本身是一个 pi package，`package.json` 里声明了这个 skill）。之后 `/skill:explore-loop`，或让模型自己按描述加载。
- **任何代理（Codex、pi、Cursor…）**：把 `explore` 链进 `PATH`（`ln -s $PWD/explore ~/.local/bin/explore`），再往项目的 `AGENTS.md` 里加两行：

  ```
  要验证一个改动是否真的让某个指标变好，用 `explore`。第一次用先运行 `explore guide` 读说明，之后用 `explore next` 看下一步。
  退出码：0 成了，1 被拦下（原因在输出里），2 测量作废、稍后重试。
  ```

  工具自己带说明（`explore guide`）、自己说下一步（`explore next`），代理不需要专门的插件。账本是 `ledger.jsonl`，一行一个 JSON，可以直接读。

## 自检

```sh
./explore selftest && ./test.sh
```

不要用管道接它们，管道会吞掉退出码。

思路来自 TabbyML 的 *Beating ClickBench SOTA with a team of agentic systems engineers*；判定规则参考了 benchstat、criterion.rs 和 asv。

MIT License.
