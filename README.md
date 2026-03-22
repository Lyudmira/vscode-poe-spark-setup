# Use GPT-5.3 Spark via Poe in VS Code

Use GPT-5.3 Spark through the Poe API inside VS Code. This repository provides two independent integration paths:

| Entry | Tool | Intended use |
|---|---|---|
| **Codex** | OpenAI ChatGPT extension in VS Code Insiders | Terminal-style AI assistant for code execution, file edits, and multi-step agent tasks |
| **Copilot Chat** | GitHub Copilot Chat in VS Code Insiders | In-editor chat assistant |

The two paths are independent and can be configured side by side.

---

## Prerequisites

- [ ] [VS Code](https://code.visualstudio.com/) Stable is installed and has connected to the remote server at least once
- [ ] [VS Code Insiders](https://code.visualstudio.com/insiders/) is installed and has connected to the remote server at least once
- [ ] For the Codex path: VS Code Insiders has the OpenAI ChatGPT extension installed (`openai.chatgpt`)
- [ ] For the Copilot Chat path: VS Code Insiders has GitHub Copilot and GitHub Copilot Chat installed
- [ ] A [Poe](https://poe.com) account is available; get your API key from [poe.com/api_key](https://poe.com/api_key)

> Tested environment: local Mac connected to a remote Linux server over SSH (x86_64).

---

## Quick Start

SSH into the server and run the matching script in this directory.

### Codex

```bash
bash setup_codex.sh
```

This script completes all server-side setup. After it finishes, add the prompted line to your local VS Code Insiders settings.json, then restart the Extension Host.

### Copilot Chat

```bash
bash setup_copilot.sh
```

This script applies the required server-side patches. After it finishes, add the model configuration in local VS Code Insiders settings.json, then enter your Poe API key on first use.

> Note: after GitHub Copilot Chat upgrades, the top_p patch is lost and you need to run `bash setup_copilot.sh` again.

---

## Project Structure

```
.
├── README.md              English overview
├── README_zhCN.md         Chinese overview
├── setup_codex.sh         One-shot Codex setup script on the server
├── setup_copilot.sh       One-shot Copilot Chat setup script on the server
└── docs/
    ├── codex.md           Full Codex internals and manual setup guide
    └── copilot.md         Full Copilot Chat internals and manual setup guide
```

---

## Known Limitations

> These are known limitations or unresolved issues. Review them before you start.

| Scenario | Limitation |
|---|---|
| **Codex web search** | Spark does not proactively call web search, and the Poe API does not expose the corresponding interface. Web search is effectively unavailable in Codex. |
| **Copilot tool use 400** | Long tasks can still hit 400 errors when context trimming leaves orphaned tool results. The patch helps, but is not always sufficient. |
| **Model stops mid-task** | The model may stop in the middle of a long task and require a manual follow-up such as `continue`. |
| **`xhigh` reasoning effort** | It usually costs much more time than the benefit justifies and is more likely to crash. In practice, `medium` or `high` is recommended. |
