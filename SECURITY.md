# Security

## English

Do not commit real API credentials.

Sensitive files include:

- `topstepx_config.json`
- API keys
- bearer tokens
- logs containing request headers or API responses
- built app bundles that may contain local modifications
- account screenshots or exported data that you do not want public

This repository includes only example configuration files. Real credentials should live in:

```text
~/Library/Application Support/TopstepXFloatPanel/topstepx_config.json
```

If you accidentally commit a real key, revoke it immediately in the official platform, rotate the credential, and remove it from git history before publishing again.

## 中文

不要提交真实 API 凭据。

敏感文件包括：

- `topstepx_config.json`
- API Key
- bearer token
- 包含请求头或 API 响应的日志
- 可能包含本地修改的 `.app` 打包产物
- 不希望公开的账户截图或导出数据

本仓库只应该包含示例配置。真实凭据应放在：

```text
~/Library/Application Support/TopstepXFloatPanel/topstepx_config.json
```

如果不小心提交了真实 Key，请立即在官方平台吊销并更换，再清理 git 历史后重新发布。

