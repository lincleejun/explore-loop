# explore-loop

Verify improvement ideas by measurement. You (or an agent) bring the idea; `explore` measures the candidate against the baseline in pairs, decides *better / regression / not enough evidence*, lands only what passes, and logs every attempt.

验证改进想法的工具：想法、理由、证据是人或模型的事，量得对不对、能不能落地、记没记账是它的事。

```sh
explore init ~/wt/demo --repo <仓库> --measure '<打印指标行的命令>' --test '<测试命令>'
cd ~/wt/demo
explore aa                                  # 校准：每个指标的噪声
explore new "<想法>" --target "<指标>"      # 编号、一页记录、一个 worktree
explore land E001                           # 验证；过了合进基线，没过告诉你拦在哪
```

完整说明在 [`SKILL.md`](SKILL.md)：需要你给什么、怎么验证、判定规则的数据、工具管不了什么。

## 里面有什么

| 文件 | 是什么 |
|---|---|
| `explore` | 整个工具。一个 Python 文件，3.11+，只用标准库，不依赖任何代理框架 |
| `SKILL.md` | 给代理读的说明。带 Claude Code skill 的 frontmatter，正文是普通 Markdown |
| `templates/` | `explore init` 和 `explore new` 用的三个模板 |
| `test.sh` | 端到端自检：在临时仓库里走完整流程，该拦的要拦 |
| `codex.sh` | 可选：让 Codex 只读地评审一个仓库 |

## 安装

- **命令行**：克隆，把 `explore` 放进 `PATH`（或直接用路径调用）。
- **Claude Code skill**：`git clone <本仓库> ~/.claude/skills/explore-loop`。更新就 `git pull`。
- **别的代理**：工具本身与代理无关。适配只需要把 `SKILL.md` 的正文放到那个代理读得到的地方，并让它能执行 `explore`。

## 自检

```sh
./explore selftest && ./test.sh
```

不要用管道接它们，管道会吞掉退出码。

思路来自 TabbyML 的 *Beating ClickBench SOTA with a team of agentic systems engineers*；判定规则参考了 benchstat、criterion.rs 和 asv。
