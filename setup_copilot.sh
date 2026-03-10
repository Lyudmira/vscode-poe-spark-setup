#!/bin/bash
# setup_copilot.sh - 为 GitHub Copilot Chat 打 patch 以支持 Poe API
# 用法：bash setup_copilot.sh

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}▶${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Copilot Chat × Poe API 配置向导        ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 1. 检查 VS Code Insiders Server ──────────────────────────────
info "检查 VS Code Insiders Server..."
if [ ! -d "$HOME/.vscode-server-insiders" ]; then
    error "未找到 ~/.vscode-server-insiders\n请先用 VS Code Insiders 连接本服务器并安装 GitHub Copilot Chat 扩展后重试。"
fi
ok "VS Code Insiders Server 已安装"

# ── 2. 查找 Copilot Chat extension.js ────────────────────────────
info "查找 Copilot Chat 扩展..."
EXT_JS=$(ls "$HOME/.vscode-server-insiders/extensions/github.copilot-chat-"*/dist/extension.js 2>/dev/null | tail -1)
if [ -z "$EXT_JS" ]; then
    error "未找到 Copilot Chat 扩展。\n请在 VS Code Insiders 中安装 GitHub Copilot Chat 扩展后重试。"
fi
ok "找到扩展：$EXT_JS"

EXT_SIZE=$(wc -c < "$EXT_JS")
ok "文件大小：$(( EXT_SIZE / 1024 / 1024 )) MB (${EXT_SIZE} bytes)"

# ── 3. 用 Python 检查完整性并应用 patch ──────────────────────────
info "Patch 1/2：移除 Poe 不支持的 top_p 参数..."

python3 - "$EXT_JS" << 'PYEOF'
import sys, os, re

ext_js = sys.argv[1]
size = os.path.getsize(ext_js)

OLD = 'preparePostOptions(t){return{temperature:this.options.temperature,top_p:this.options.topP,...t,stream:!0}}'
NEW = 'preparePostOptions(t){return{temperature:this.options.temperature,...t,stream:!0}}'

def read_restore_from_marketplace(ext_js):
    """文件损坏时从 Marketplace 下载原始版本"""
    import urllib.request, gzip, zipfile, io

    m = re.search(r'github\.copilot-chat-([\d.]+)', ext_js)
    if not m:
        print("✗ 无法解析扩展版本号", file=sys.stderr)
        sys.exit(1)
    version = m.group(1)
    print(f"  扩展版本：{version}")

    url = (f"https://marketplace.visualstudio.com/_apis/public/gallery/publishers/"
           f"GitHub/vsextensions/copilot-chat/{version}/vspackage")
    print(f"  下载中（约 20MB，请稍候）：{url}")

    with urllib.request.urlopen(url, timeout=300) as resp:
        data = resp.read()

    # Marketplace 下载的 vsix 有时是 gzip 包裹的 zip
    if data[:2] == b'\x1f\x8b':
        data = gzip.decompress(data)

    with zipfile.ZipFile(io.BytesIO(data)) as z:
        content = z.read('extension/dist/extension.js').decode('utf-8')

    print(f"  恢复完成，大小：{len(content):,} 字节")
    return content

# 文件过小说明被截断，需要从 Marketplace 恢复
if size < 5_000_000:
    print(f"⚠  文件过小（{size:,} bytes），疑似损坏，尝试从 Marketplace 恢复...")
    content = read_restore_from_marketplace(ext_js)
else:
    with open(ext_js, 'r') as f:
        content = f.read()

# 检查是否已打过 patch
if OLD not in content:
    if NEW in content:
        print("✓ Patch 已应用，无需重复操作。")
        sys.exit(0)
    else:
        print("✗ 未找到目标字符串，当前扩展版本可能已更新，patch 需要重新适配。", file=sys.stderr)
        sys.exit(1)

# 应用 patch
content = content.replace(OLD, NEW, 1)
with open(ext_js, 'w') as f:
    f.write(content)

final_size = os.path.getsize(ext_js)
print(f"✓ Patch 已应用")
print(f"  文件大小：{final_size:,} 字节")

# 验证
with open(ext_js, 'r') as f:
    verify = f.read()
assert OLD not in verify, "验证失败：OLD 仍存在"
assert NEW in verify,     "验证失败：NEW 未找到"
print("✓ 验证通过")
PYEOF

ok "Patch 1/2 成功（top_p 已移除）"

# ── 4. Patch 2：过滤孤立 tool result 消息 ────────────────────────
info "Patch 2/2：过滤孤立 tool result 消息（防止 Poe API 400 错误）..."

python3 - "$EXT_JS" << 'PYEOF'
import sys, os

ext_js = sys.argv[1]

OLD = 'async makeChatRequest2(t,r){let a={...t,ignoreStatefulMarker:!1},o=await super.makeChatRequest2(a,r);return l0i(o)}'
NEW = 'async makeChatRequest2(t,r){let msgs=t.messages||[],ids=new Set;for(let m of msgs)(m.role===2||m.role==="assistant")&&m.toolCalls&&m.toolCalls.forEach(c=>ids.add(c.id));let cleaned=msgs.filter(m=>!(m.role===3||m.role==="tool")||ids.has(m.toolCallId));let a={...t,ignoreStatefulMarker:!1,messages:cleaned},o=await super.makeChatRequest2(a,r);return l0i(o)}'

with open(ext_js) as f:
    content = f.read()

if OLD not in content:
    if NEW in content:
        print('✓ Patch 2 已应用，无需重复操作。')
        sys.exit(0)
    else:
        print('✗ 未找到目标字符串（Patch 2），当前扩展版本可能已更新。', file=sys.stderr)
        sys.exit(1)

content = content.replace(OLD, NEW, 1)
with open(ext_js, 'w') as f:
    f.write(content)

final_size = os.path.getsize(ext_js)
print(f'✓ Patch 2 已应用，文件大小：{final_size:,} 字节')

with open(ext_js) as f:
    verify = f.read()
assert OLD not in verify, '验证失败：OLD 仍存在'
assert NEW in verify,     '验证失败：NEW 未找到'
print('✓ 验证通过')
PYEOF

ok "Patch 2/2 成功（孤立 tool result 已过滤）"

# ── 5. 打印手动步骤 ──────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}剩余步骤（在本地 Mac/PC 上操作）：${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. 打开 VS Code Insiders User settings JSON："
echo "   Cmd+Shift+P → Preferences: Open User Settings (JSON)"
echo ""
echo "2. 添加以下配置（首次添加，之后通过 UI 修改）："
echo ""
cat << 'JSON'
    "github.copilot.chat.customOAIModels": {
        "gpt-5.3-codex-spark": {
            "name": "Poe gpt-5.3-codex-spark",
            "url": "https://api.poe.com/v1",
            "toolCalling": true,
            "vision": false,
            "maxInputTokens": 128000,
            "maxOutputTokens": 16384
        }
    }
JSON
echo ""
echo "   ⚠  该配置只在第一次被读取（迁移到 VS Code 内部状态），之后通过以下方式修改："
echo "   Cmd+Shift+P → GitHub Copilot: Manage Custom Language Models"
echo ""
echo "3. 保存后 Copilot Chat 会弹出对话框要求输入 API Key，填入你的 Poe API Key。"
echo "   在 https://poe.com/api_key 获取"
echo ""
echo "4. 重启扩展宿主："
echo "   Cmd+Shift+P → Developer: Restart Extension Host"
echo ""
echo "5. 在 Copilot Chat 的模型选择器中选择 Poe gpt-5.3-codex-spark。"
echo ""
echo -e "${GREEN}✓ 服务端 Patch 完成！${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}维护提示：${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Copilot Chat 扩展更新后 patch 会丢失，检查方式："
echo ""
echo "  EXT_JS=\$(ls ~/.vscode-server-insiders/extensions/github.copilot-chat-*/dist/extension.js 2>/dev/null | tail -1)"
echo "  grep -c 'top_p:this.options.topP' \"\$EXT_JS\" && echo 'Patch 1 MISSING' || echo 'Patch 1 OK'"
echo "  grep -c 'let msgs=t.messages' \"\$EXT_JS\" || echo 'Patch 2 MISSING'  # 输出0表示未找到即丢失"
echo "  # 若任一 MISSING，重新运行：bash setup_copilot.sh"
echo ""
