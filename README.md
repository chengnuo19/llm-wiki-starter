# Obsidian LLM Wiki Starter

一个 PowerShell 初始化器，用于创建以来源为依据、由 Obsidian 浏览并由 AI Agent 维护的本地知识库。

## 快速开始

在 PowerShell 中运行：

```powershell
$vault = Join-Path $env:USERPROFILE 'Documents\LLM Wiki'
.\New-LlmWiki.ps1 -Path $vault -SkipPlugins
```

脚本会拒绝覆盖已有文件，并创建 `raw/` 和 `wiki/` 目录、维护规则、起始指南、索引和活动日志。完成后，在 Obsidian 中打开目标文件夹即可。

## 可选：复制本机社区插件

默认不复制插件。若希望从已有 Vault 复制插件程序文件，请显式提供插件目录：

```powershell
$vault = Join-Path $env:USERPROFILE 'Documents\LLM Wiki'
$plugins = 'D:\Path\To\Vault\.obsidian\plugins'
.\New-LlmWiki.ps1 -Path $vault -PluginSourcePath $plugins
```

如果源 Vault 有 `community-plugins.json`，脚本只复制启用列表中的插件；若该文件不存在，则会复制所有带有效 `manifest.json` 的插件目录。插件文件会排除 `data.json` 和 `.git`。若启用了 QuickAdd，会复制最近的导出包；导入前应在 Obsidian 中检查其中的命令和模板。若不希望复制插件，请使用 `-SkipPlugins`。

其他选项：

```powershell
.\New-LlmWiki.ps1 -Path $vault -Name 'Research Wiki' -SkipPlugins -WhatIf
```

`-WhatIf` 只预览，不写入文件。模板位于 `template/`，可按需调整之后创建的新 Vault。
