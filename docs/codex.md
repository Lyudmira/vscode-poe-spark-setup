# Codex × Poe API 完整教程

本文说明如何在 VS Code Insiders 的 Codex（`openai.chatgpt` 扩展）中通过 Poe API 使用 GPT-5.3 Spark，并与 VS Code Stable 的 Codex 账号隔离互不干扰。

**TL;DR**：直接运行 `bash setup_codex.sh` 即可完成全部服务端配置，本文是详解版本。

---

## 为什么需要两个独立实例

如果你同时打开 VS Code Stable 和 VS Code Insiders，都连接到同一台远程服务器，默认情况下两者会**共享同一个 Codex 认证数据库**：

```
~/.codex/state_5.sqlite
```

在 Insiders 里登录会立刻覆盖 Stable 的登录状态，反之亦然。

可以用以下命令验证：

```bash
pgrep -af "codex app-server"
# 会看到两行，一行路径含 vscode-server，一行含 vscode-server-insiders
# 但两个进程打开的数据库文件是同一个
```

---

## 解决原理：`CODEX_HOME` 环境变量

Codex 二进制内置了 `CODEX_HOME` 支持（来自扩展源码）：

```javascript
return process.env.CODEX_HOME ?? path.join(os.homedir(), ".codex")
```

设置 `CODEX_HOME` 后，Codex 会使用该目录存储所有数据（认证、配置、历史），与默认的 `~/.codex/` 完全隔离。

**难点**：`codex app-server` 是扩展的 Node.js 宿主进程 spawn 出来的子进程，无法通过 `~/.bashrc`、`~/.profile`、`remote.env` 等常规方式注入环境变量（详见文末[附录](#附录为什么常规环境变量注入方法不起作用)）。

**解决方法**：利用 `chatgpt.cliExecutable` 设置——它允许指定一个自定义脚本替代内置 codex 二进制。在脚本里 `export CODEX_HOME`，再 `exec` 真正的二进制，就能把环境变量注入进去。

---

## 手动配置步骤

> 以下步骤已由 `setup_codex.sh` 自动完成，手动操作供参考或排查问题。

### 第一步：创建独立数据目录（服务器上）

```bash
mkdir -p ~/.codex-insiders

# 可选：复制现有模型配置（config.toml 只含设置，不含认证 token，复制是安全的）
# cp ~/.codex/config.toml ~/.codex-insiders/config.toml
```

### 第二步：写入 `~/.codex-insiders/config.toml`

```toml
model = "gpt-5.3-codex-spark"
model_reasoning_effort = "high"
model_provider = "poe"

[model_providers.poe]
name = "Poe"
base_url = "https://api.poe.com/v1"
env_key = "POE_API_KEY"
```

字段说明：
- `model_provider = "poe"`：告诉 Codex 使用名为 `poe` 的 provider
- `base_url`：Poe 的 OpenAI 兼容端点
- `env_key`：备用方案（若未用 `login --with-api-key`，Codex 会读该环境变量作为 Bearer token）

> **注意**：不要添加 `personality = "pragmatic"`。Codex CLI 在处理内部小模型（`gpt-5.1-codex-mini`）的人格指令时存在 bug，`model_messages` 字段缺失时会导致 SIGSEGV 崩溃。

### 第三步：创建包装脚本（服务器上）

```bash
mkdir -p ~/.local/bin

cat > ~/.local/bin/codex-insiders << 'EOF'
#!/bin/sh
# 为 VS Code Insiders 的 Codex 设置独立的数据目录
export CODEX_HOME="$HOME/.codex-insiders"

# glob 写法：扩展版本更新后此脚本无需修改
CODEX_BIN=$(ls "$HOME/.vscode-server-insiders/extensions/openai.chatgpt-"*/bin/linux-x86_64/codex 2>/dev/null | tail -1)
[ -z "$CODEX_BIN" ] && CODEX_BIN=$(ls "$HOME/.vscode-server-insiders/extensions/openai.chatgpt-"*/bin/*/codex 2>/dev/null | tail -1)

if [ -z "$CODEX_BIN" ]; then
    echo "codex-insiders: codex binary not found" >&2
    exit 1
fi
exec "$CODEX_BIN" "$@"
EOF

chmod +x ~/.local/bin/codex-insiders
```

验证：

```bash
~/.local/bin/codex-insiders --version
# 应输出类似：codex-cli 0.108.0-alpha.12
```

**脚本说明**：
- `exec "$CODEX_BIN" "$@"` 替换当前进程，参数（包括 `app-server --analytics-default-enabled`）原封不动传入
- `tail -1` 取字母序最后一个版本（通常是最新版）
- Windows/其他架构用户把 `linux-x86_64` 改为对应平台（`ls ~/.vscode-server-insiders/extensions/openai.chatgpt-*/bin/` 查看可用目录）

### 第四步：存储 Poe API Key（服务器上）

```bash
CODEX_BIN=$(ls ~/.vscode-server-insiders/extensions/openai.chatgpt-*/bin/linux-x86_64/codex 2>/dev/null | tail -1)
echo "YOUR_POE_API_KEY" | CODEX_HOME=~/.codex-insiders "$CODEX_BIN" login --with-api-key
```

Key 会被加密存储在 `~/.codex-insiders/auth.json`，包装脚本无需修改。

验证存储成功：

```bash
CODEX_HOME=~/.codex-insiders "$CODEX_BIN" login status
# 预期：Logged in using an API key - YOUR_***_KEY
```

### 第五步：在本地 VS Code Insiders 设置中指定包装脚本

> `chatgpt.cliExecutable` 的 scope 是 `application`，**只从本地客户端的 User settings 读取**，与服务端无关。

打开本地 VS Code Insiders 的 User settings JSON：
`Cmd+Shift+P` → `Preferences: Open User Settings (JSON)`

添加：

```json
"chatgpt.cliExecutable": "/data/users/mia/.local/bin/codex-insiders"
```

> 路径改为你在服务器上创建包装脚本的实际绝对路径。

**注意**：不要在 VS Code Stable 的 settings 里添加这行，Stable 继续用默认二进制和 `~/.codex/`。

### 第六步：重启扩展宿主

`Cmd+Shift+P` → **Developer: Restart Extension Host**

（只重启扩展进程，不断开 SSH 连接，安全。）

---

## 验证隔离成功

重启后在服务器上运行：

```bash
pgrep -af "codex app-server"
# 应看到两行：
# - 一行路径含 vscode-server（Stable）
# - 一行路径含 vscode-server-insiders（Insiders）

# 检查 Insiders 进程的 CODEX_HOME
INSIDERS_PID=$(pgrep -f "vscode-server-insiders.*codex app-server")
cat /proc/$INSIDERS_PID/environ | tr '\0' '\n' | grep CODEX_HOME
# 应输出：CODEX_HOME=/data/users/mia/.codex-insiders

# 检查两个进程各自打开的数据库
STABLE_PID=$(pgrep -f "vscode-server/extensions.*codex app-server")
echo "=== Stable ===" && ls -la /proc/$STABLE_PID/fd 2>/dev/null | grep "\.codex"
echo "=== Insiders ===" && ls -la /proc/$INSIDERS_PID/fd 2>/dev/null | grep "\.codex"
# Stable: ~/.codex/state_5.sqlite
# Insiders: ~/.codex-insiders/state_5.sqlite
```

---

## 状态总结

| | VS Code Stable | VS Code Insiders |
|---|---|---|
| 启动方式 | 直接调用原始 codex 二进制 | 包装脚本 → 原始 codex 二进制 |
| `CODEX_HOME` | 未设置（默认 `~/.codex/`） | `~/.codex-insiders/` |
| 认证数据库 | `~/.codex/state_5.sqlite` | `~/.codex-insiders/state_5.sqlite` |
| 模型配置 | `~/.codex/config.toml` | `~/.codex-insiders/config.toml` |
| 登录状态独立 | ✅ | ✅ |

---

## 日常维护

**Codex 扩展更新后**：包装脚本使用 glob 查找二进制，自动适配，无需任何操作。

**更换 Poe API Key**：

```bash
CODEX_BIN=$(ls ~/.vscode-server-insiders/extensions/openai.chatgpt-*/bin/linux-x86_64/codex 2>/dev/null | tail -1)
echo "NEW_POE_API_KEY" | CODEX_HOME=~/.codex-insiders "$CODEX_BIN" login --with-api-key
```

**同时给 Stable 也配置独立账号**（如需要三个独立实例）：  
对 VS Code Stable 重复同样流程，创建 `~/.codex-stable/`、`~/.local/bin/codex-stable`，在 Stable 的本地 User settings 里设置 `chatgpt.cliExecutable`。

---

## 附录：为什么常规环境变量注入方法不起作用

### `~/.bashrc`

```bash
if [[ "${VSCODE_GIT_ASKPASS_MAIN:-}" == *"vscode-server-insiders"* ]]; then
    export CODEX_HOME="$HOME/.codex-insiders"
fi
```

**失败原因**：`~/.bashrc` 开头通常有 `case $- in *i*)` 判断，对非交互式 shell 直接 `return`。VS Code 的扩展宿主进程以非交互式方式启动，这段代码从未被执行。

### `~/.profile`

**失败原因**：`~/.profile` 由 login shell 执行，但 VS Code 远程服务端的扩展宿主进程不是 login shell（通过 `bash -c` 或直接 `node` 启动）。

### `remote.env`

```json
"remote.env": { "CODEX_HOME": "/data/users/mia/.codex-insiders" }
```

**失败原因**：`remote.env` 需要**完整重启 VS Code Server**（`Kill VS Code Server`）才生效，`Reload Window` 和 `Restart Extension Host` 均不够。即便重启后，经实测 `/proc/<pid>/environ` 显示扩展宿主进程也未收到该变量，疑似 VS Code 服务端对 `remote.env` 的实现存在时序问题。

### Machine settings 中的 `chatgpt.cliExecutable`

```json
// ~/.vscode-server-insiders/data/Machine/settings.json
{ "chatgpt.cliExecutable": "/data/users/mia/.local/bin/codex-insiders" }
```

**失败原因**：`chatgpt.cliExecutable` 的 scope 是 `application`。VS Code 规范规定 `application` scope 的设置只从**本地客户端**的 User settings 读取，服务端 Machine settings 里的同名项被完全忽略。
