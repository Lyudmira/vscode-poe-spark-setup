#!/bin/bash
# setup_codex.sh - 在 VS Code Insiders 的 Codex 中配置 Poe API
# 用法：bash setup_codex.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}▶${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║      Codex × Poe API 配置向导            ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 1. 检查 VS Code Insiders Server ──────────────────────────────
info "检查 VS Code Insiders Server..."
if [ ! -d "$HOME/.vscode-server-insiders" ]; then
    error "未找到 ~/.vscode-server-insiders\n请先用 VS Code Insiders 连接本服务器并安装 OpenAI ChatGPT 扩展后重试。"
fi
ok "VS Code Insiders Server 已安装"

# ── 2. 查找 Codex 二进制 ─────────────────────────────────────────
info "查找 Codex 二进制..."
CODEX_BIN=$(ls "$HOME/.vscode-server-insiders/extensions/openai.chatgpt-"*/bin/linux-x86_64/codex 2>/dev/null | tail -1)
# 支持其他架构（arm64 等）
if [ -z "$CODEX_BIN" ]; then
    CODEX_BIN=$(ls "$HOME/.vscode-server-insiders/extensions/openai.chatgpt-"*/bin/*/codex 2>/dev/null | tail -1)
fi
if [ -z "$CODEX_BIN" ]; then
    error "未找到 Codex 二进制。\n请在 VS Code Insiders 中安装 OpenAI ChatGPT 扩展后重试。"
fi
ok "Codex 二进制：$CODEX_BIN"

# ── 3. 创建独立数据目录 ──────────────────────────────────────────
info "创建 ~/.codex-insiders/ 目录..."
mkdir -p "$HOME/.codex-insiders"
ok "目录已就绪"

# ── 4. 写入 config.toml ──────────────────────────────────────────
info "写入 ~/.codex-insiders/config.toml..."
cat > "$HOME/.codex-insiders/config.toml" << 'TOML'
model = "gpt-5.3-codex-spark"
model_reasoning_effort = "high"
model_provider = "poe"

[model_providers.poe]
name = "Poe"
base_url = "https://api.poe.com/v1"
env_key = "POE_API_KEY"
TOML
ok "config.toml 已写入"

# ── 5. 创建包装脚本 ──────────────────────────────────────────────
info "创建 ~/.local/bin/codex-insiders 包装脚本..."
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/codex-insiders" << 'SCRIPT'
#!/bin/sh
# 为 VS Code Insiders 的 Codex 设置独立数据目录（与 VS Code Stable 隔离）
export CODEX_HOME="$HOME/.codex-insiders"

CODEX_BIN=$(ls "$HOME/.vscode-server-insiders/extensions/openai.chatgpt-"*/bin/linux-x86_64/codex 2>/dev/null | tail -1)
[ -z "$CODEX_BIN" ] && CODEX_BIN=$(ls "$HOME/.vscode-server-insiders/extensions/openai.chatgpt-"*/bin/*/codex 2>/dev/null | tail -1)

if [ -z "$CODEX_BIN" ]; then
    echo "codex-insiders: codex binary not found" >&2
    exit 1
fi
exec "$CODEX_BIN" "$@"
SCRIPT
chmod +x "$HOME/.local/bin/codex-insiders"
ok "包装脚本已创建：~/.local/bin/codex-insiders"

# ── 6. 验证包装脚本 ──────────────────────────────────────────────
if version=$("$HOME/.local/bin/codex-insiders" --version 2>&1); then
    ok "包装脚本验证通过：$version"
else
    warn "包装脚本已创建，但暂时无法验证版本（连接 VS Code Insiders 后会正常工作）"
fi

# ── 7. 存储 Poe API Key ──────────────────────────────────────────
echo ""
info "存储 Poe API Key..."
echo "  在 https://poe.com/api_key 获取你的 API Key"
echo ""
read -r -p "  请输入 Poe API Key: " POE_KEY
[ -z "$POE_KEY" ] && error "未输入 API Key，已退出。"

echo "$POE_KEY" | CODEX_HOME="$HOME/.codex-insiders" "$CODEX_BIN" login --with-api-key
ok "API Key 已加密存储至 ~/.codex-insiders/auth.json"

# ── 8. 验证登录状态 ──────────────────────────────────────────────
LOGIN_STATUS=$(CODEX_HOME="$HOME/.codex-insiders" "$CODEX_BIN" login status 2>&1)
ok "登录状态：$LOGIN_STATUS"

# ── 9. 打印手动步骤 ──────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}最后一步（在本地 Mac/PC 上操作）：${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. 打开 VS Code Insiders User settings JSON："
echo "   Cmd+Shift+P → Preferences: Open User Settings (JSON)"
echo ""
echo "2. 添加以下配置："
echo ""
echo -e "   ${GREEN}\"chatgpt.cliExecutable\": \"$HOME/.local/bin/codex-insiders\"${NC}"
echo ""
echo "3. 重启扩展宿主："
echo "   Cmd+Shift+P → Developer: Restart Extension Host"
echo ""
echo -e "${GREEN}✓ 服务端配置完成！完成上述步骤后即可在 VS Code Insiders 中使用 GPT-5.3 Spark。${NC}"
echo ""
