# TSX Deck 中文说明

TSX Deck 是一个 macOS 原生 TopstepX / ProjectX Gateway API 悬浮交易面板，用于快速查看行情、账户状态、市价/限价下单、可选 TP/SL bracket、挂单管理、撤单、平仓和连接状态。

本项目不是 Topstep、TopstepX 或 ProjectX 官方项目，也没有获得官方背书。

**关键词：** TopstepX、ProjectX Gateway API、macOS 交易面板、期货交易、NQ、MNQ、ES、MES、市价单、限价单、OCO bracket、TP/SL、AppKit。

## 截图

<p align="center">
  <img src="docs/assets/tsx-deck-dark-market.png" alt="TSX Deck 深色模式市价单面板，显示实时期货行情、账户状态、working orders 和连接状态栏" width="24%">
  <img src="docs/assets/tsx-deck-dark-limit.png" alt="TSX Deck 深色模式限价单页面，包含一体化限价输入、数量控件和 TP SL 卡片" width="24%">
  <img src="docs/assets/tsx-deck-light-market.png" alt="TSX Deck 浅色模式市价单悬浮交易面板，包含紧凑原生 macOS 下单控件" width="24%">
  <img src="docs/assets/tsx-deck-light-limit.png" alt="TSX Deck 浅色模式限价单页面，包含 bracket 控件和 working orders 面板" width="24%">
</p>

## 适用场景

- 在 macOS 上使用紧凑的 always-on-top 原生悬浮窗进行快速期货下单。
- 查看 TopstepX / ProjectX 账户状态、当前持仓、挂单和 API 连接状态。
- 提交市价单、限价单，并按官方 Auto OCO Brackets 设置使用可选 TP/SL。
- 开源发布源码，同时把真实 API 凭据保留在本机配置文件中。

## 最新界面优化

- 优化 Market / Limit 分段切换控件，让 Order Ticket 更简洁、专业。
- 重排 Limit 下单区域，加入一体化限价输入、紧凑数量控件和更清晰的 TP / SL 卡片。
- 优化 Working Orders，增加数据来源 pill、居中加载/空状态，并保留滚动位置。
- 优化底部状态栏，把 API、Stream、Market 连接状态集中成更干净的健康状态条。
- 保持原生悬浮窗宽度稳定，同时让高度随当前下单模式和挂单列表自适应。

## 构建

```bash
cd outputs
chmod +x build_app.sh
./build_app.sh
open "TSX Deck.app"
```

构建脚本默认只打包安全的示例配置。如果你要在自己的多台 Mac 之间复制自用版本，可以把真实 `topstepx_config.json` 放在 `outputs/build_app.sh` 同级目录；脚本会把这个本机配置打包进生成的 App，同时 `.gitignore` 会阻止真实配置进入仓库。

## 配置

真实配置文件位置：

```text
~/Library/Application Support/TopstepXFloatPanel/topstepx_config.json
```

第一次使用：

```bash
mkdir -p "$HOME/Library/Application Support/TopstepXFloatPanel"
cp outputs/topstepx_config.example.json "$HOME/Library/Application Support/TopstepXFloatPanel/topstepx_config.json"
```

先保持 `"readOnly": true`。只有当你明确要发送真实订单时，才改成 `"readOnly": false`。

如果需要制作自用可携带版本，请看 `outputs/PORTABLE_README.txt`。不要提交真实配置文件，也不要提交包含真实凭据的 App bundle。

## 真实交易前必须确认

- ProjectX API 凭据已启用。
- 当前账户允许交易。Follower 账户可能不能直接下单。
- 普通市价/限价单不需要 Auto OCO Brackets。
- 如果要自动提交 TP/SL bracket，需要在 TopstepX / ProjectX 官方设置里启用 Auto OCO Brackets。
- 如果官方要求从 Position Brackets 切换到 Auto OCO Brackets，按官方页面操作，可能需要先空仓。
- 如果 App 显示 `Bracket mode mismatch`，优先检查官方 bracket 设置。

## 风险提示

期货交易风险极高。开启 live 模式后，本软件可以发送真实订单。交易前请自行确认账户、商品、数量、方向、订单类型、价格、TP/SL 和官方平台状态。

不要把真实 `topstepx_config.json`、API Key、账户密钥、包含 token 的日志或带本地配置的打包产物提交到 GitHub。

English documentation is available in [README.md](README.md).
