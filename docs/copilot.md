# Copilot Chat × Poe API 完整教程

本文说明如何在 GitHub Copilot Chat（VS Code Insiders）中通过 Poe API 使用 GPT-5.3 Spark。

**TL;DR**：直接运行 `bash setup_copilot.sh` 即可完成服务端 patch，本文是详解版本。

---

## 原理

### BYOK 机制

GitHub Copilot Chat 支持 BYOK（Bring Your Own Key）功能，通过 `github.copilot.chat.customOAIModels` 设置添加自定义 OpenAI 兼容模型。配置后 Copilot Chat 会直接向你指定的 URL 发送标准 `/v1/chat/completions` 请求，使用你提供的 API Key 进行认证。

### `top_p` 问题

Copilot Chat 默认在每个请求的 options 中附加 `top_p: 1`，Poe API 不接受该参数，会返回 400 错误。需要对服务器上的 `extension.js` 打 patch 移除它。

具体位置是 `pnn` 类的 `preparePostOptions` 方法：

```javascript
// 原始代码（有问题）
preparePostOptions(t){return{temperature:this.options.temperature,top_p:this.options.topP,...t,stream:!0}}

// patch 后（移除 top_p）
preparePostOptions(t){return{temperature:this.options.temperature,...t,stream:!0}}
```

### 为什么只能改服务器上的文件

`extension.js` 是 VS Code 服务端扩展的核心文件，实际运行在远程服务器上。本地 Mac 上的 VS Code Insiders 只是一个"远程 UI"——所有扩展逻辑都在服务器端执行，因此 patch 必须在服务器上进行。

### 关于 `extension.js` 的安全操作提示

`extension.js` 约 19MB，超过部分编辑器工具的写入上限（如 1MB）。**绝对不要**用文本编辑器或 IDE 的"编辑文件"功能直接修改它——文件会被静默截断，导致扩展完全损坏。

始终用 Python 脚本操作：

```bash
python3 - "$EXT_JS" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
# ... 做字符串替换 ...
with open(path, 'w') as f:
    f.write(content)
PYEOF
```

---

## 手动配置步骤

> 以下步骤已由 `setup_copilot.sh` 自动完成，手动操作供参考或排查问题。

### 第一步：配置 BYOK 模型（本地 Mac/PC 上）

打开 VS Code Insiders 的 User settings JSON：
`Cmd+Shift+P` → `Preferences: Open User Settings (JSON)`

添加：

```json
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
```

> **重要**：该设置**只在第一次被读取时生效**（会迁移到 VS Code 内部的 globalState），之后 settings.json 里的修改不再生效。若需修改模型配置，使用：  
> `Cmd+Shift+P` → **GitHub Copilot: Manage Custom Language Models**

保存后，Copilot Chat 会弹出输入框要求填写 API Key，输入 Poe 控制台里的 key 即可。  
在 [poe.com/api_key](https://poe.com/api_key) 获取。

### 第二步：打 patch 移除 `top_p`（服务器上）

SSH 登录服务器，执行：

```bash
EXT_JS=$(ls ~/.vscode-server-insiders/extensions/github.copilot-chat-*/dist/extension.js 2>/dev/null | tail -1)
echo "Target: $EXT_JS  ($(wc -c < "$EXT_JS") bytes)"

python3 - "$EXT_JS" << 'PYEOF'
import sys, os

path = sys.argv[1]
OLD = 'preparePostOptions(t){return{temperature:this.options.temperature,top_p:this.options.topP,...t,stream:!0}}'
NEW = 'preparePostOptions(t){return{temperature:this.options.temperature,...t,stream:!0}}'

with open(path) as f:
    content = f.read()

if OLD not in content:
    if NEW in content:
        print("Already patched.")
    else:
        print("ERROR: pattern not found. Extension may have updated.", file=__import__('sys').stderr)
        __import__('sys').exit(1)
else:
    with open(path, 'w') as f:
        f.write(content.replace(OLD, NEW, 1))
    print(f"Patch applied. New size: {os.path.getsize(path):,} bytes")
PYEOF
```

验证 patch 有效：

```bash
grep -c 'top_p:this.options.topP' "$EXT_JS" && echo "PATCH MISSING" || echo "Patch OK"
```

### 第三步：重启扩展宿主（本地 Mac/PC 上）

`Cmd+Shift+P` → **Developer: Restart Extension Host**

重启后在 Copilot Chat 的模型选择器里选择 `Poe gpt-5.3-codex-spark`。

---

## 扩展更新后的维护

Copilot Chat 扩展更新后，`extension.js` 会被替换，patch 会丢失。

**检查方式**：

```bash
EXT_JS=$(ls ~/.vscode-server-insiders/extensions/github.copilot-chat-*/dist/extension.js 2>/dev/null | tail -1)
grep -c 'top_p:this.options.topP' "$EXT_JS" && echo "PATCH MISSING - 请重新运行 bash setup_copilot.sh" || echo "Patch OK"
```

只需重新运行 `bash setup_copilot.sh`，脚本会自动检测并重新打 patch。

---

## 如果 extension.js 被意外截断怎么办

如果 `extension.js` 大小异常（小于 5MB），说明文件已损坏。`setup_copilot.sh` 会自动处理这种情况（从 Marketplace 重新下载并恢复），也可手动执行：

```bash
EXT_JS=$(ls ~/.vscode-server-insiders/extensions/github.copilot-chat-*/dist/extension.js 2>/dev/null | tail -1)
VERSION=$(basename "$(dirname "$(dirname "$EXT_JS")")" | sed 's/github\.copilot-chat-//')

python3 << PYEOF
import urllib.request, gzip, zipfile, io

version = "${VERSION}"
url = f"https://marketplace.visualstudio.com/_apis/public/gallery/publishers/GitHub/vsextensions/copilot-chat/{version}/vspackage"
print(f"Downloading {url}...")

with urllib.request.urlopen(url, timeout=300) as resp:
    data = resp.read()

# Marketplace vsix 有时是 gzip 包裹的 zip
if data[:2] == b'\x1f\x8b':
    data = gzip.decompress(data)

with zipfile.ZipFile(io.BytesIO(data)) as z:
    content = z.read('extension/dist/extension.js').decode('utf-8')

with open("${EXT_JS}", 'w') as f:
    f.write(content)
print(f"Restored: {len(content):,} bytes")
PYEOF
```

恢复后再运行 `bash setup_copilot.sh` 重新打 patch。

---

## 已知限制

- Poe API 仅支持 Chat Completions（`/v1/chat/completions`），不支持 OpenAI Responses API（`/v1/responses`）。Copilot Chat 的部分 agent 工具若依赖 Responses API 可能不可用。
- API Key 存储在 VS Code 的 globalState（加密），不在 settings.json 里，随扩展版本升级自动保留，无需重新输入。
