# 通过 Poe 订阅尝鲜 GPT-5.3 Spark

在 VS Code 开发环境中，通过 Poe API 使用 GPT-5.3 Spark 模型。本项目提供两种独立的接入方式：

| 入口 | 工具 | 定位 |
|---|---|---|
| **Codex** | VS Code Insiders 的 OpenAI ChatGPT 扩展 | 终端交互式 AI 助手（代码执行、文件编辑、多步骤 agent） |
| **Copilot Chat** | VS Code Insiders 的 GitHub Copilot Chat | 编辑器内聊天助手 |

两种方式互相独立，可以同时配置。

---

## 前置条件（需手动安装，脚本无法代劳）

- [ ] [VS Code](https://code.visualstudio.com/)（Stable）已安装，并至少连接过远程服务器一次
- [ ] [VS Code Insiders](https://code.visualstudio.com/insiders/) 已安装，并至少连接过远程服务器一次
- [ ] **Codex 入口**：VS Code Insiders 已安装 **OpenAI ChatGPT** 扩展（`openai.chatgpt`）
- [ ] **Copilot Chat 入口**：VS Code Insiders 已安装 **GitHub Copilot** + **GitHub Copilot Chat** 扩展
- [ ] [Poe](https://poe.com) 账号（需订阅），API Key 在 [poe.com/api_key](https://poe.com/api_key) 获取

> **测试环境**：本地 Mac 通过 SSH 连接远程 Linux 服务器（x86_64）。

---

## 快速开始

SSH 登录服务器后，在本目录运行对应脚本：

### Codex 入口

```bash
bash setup_codex.sh
```

脚本会自动完成服务端的全部配置。完成后按提示在本地 VS Code Insiders 的 `settings.json` 里添加一行，然后重启 Extension Host。

### Copilot Chat 入口

```bash
bash setup_copilot.sh
```

脚本会自动完成服务端 patch。完成后按提示在本地 VS Code Insiders 的 `settings.json` 里添加模型配置，第一次使用时输入 Poe API Key。

---

## 项目结构

```
.
├── README.md              本文件
├── setup_codex.sh         Codex 入口一站式脚本（在服务器上运行）
├── setup_copilot.sh       Copilot Chat 入口一站式脚本（在服务器上运行）
└── docs/
    ├── codex.md           Codex 完整原理与手动配置教程
    └── copilot.md         Copilot Chat 完整原理与手动配置教程
```

---

## 已知限制

- Poe API 仅支持 Chat Completions（`/v1/chat/completions`）格式，不支持 OpenAI Responses API（`/v1/responses`）。Codex 内置的 `web_search_preview` 工具因此在 Poe 下不可用。
- **Copilot Chat 扩展更新后**，`extension.js` 会被替换，需重新运行 `setup_copilot.sh`。
- **Codex 扩展更新后**，包装脚本会自动适配（使用 glob 查找最新版本），无需重新运行。
