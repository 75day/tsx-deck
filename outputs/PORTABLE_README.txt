TSX Deck - 跨电脑直接使用说明（自用版本）

这个 outputs/ 文件夹现在可以作为“完整可移植包”使用。

=== 如何把一切东西都放在这个文件夹里 ===
1. 把你的真实配置文件命名为 topstepx_config.json （和 build_app.sh 同级）。
2. 把它放到这个 outputs/ 文件夹里。
3. 运行一次：
   ./build_app.sh
   构建脚本会检测到这个真实配置，并把它打包进 TSX Deck.app 里。

这样，整个 outputs/ 文件夹就包含了：
- 源代码 (topstepx_float_panel.swift)
- 构建脚本 (build_app.sh)
- 资源 (Resources/ 里的图标、声音、Info.plist 等)
- 你的真实配置（已打包进 .app）
- 构建好的 TSX Deck.app
- 裸二进制 TopstepXFloatPanel（可选用于测试）

=== 换电脑使用方法 ===
1. 把整个 outputs/ 文件夹完整复制到新电脑（U盘、硬盘、AirDrop 都行）。
2. 在新电脑上推荐操作：
   - 打开终端，进入这个文件夹：
     cd /你放的位置/outputs
   - 运行构建（推荐，这样签名最干净）：
     ./build_app.sh
   - 构建完成后双击生成的 TSX Deck.app 即可使用。

   或者直接双击文件夹里的 TSX Deck.app （第一次可能会弹出安全提示，右键 -> 打开 即可）。

3. 因为是自用电脑，配置已经打包在 .app 里面，打开就能用，不需要再手动放配置文件。

=== 注意事项 ===
- 构建需要新电脑有 Xcode Command Line Tools（第一次会提示安装）。
- Ad-hoc 签名在不同电脑上偶尔需要一次“允许”操作，这是正常现象。
- 如果以后修改了源代码或配置，再跑一次 ./build_app.sh 即可更新 .app。
- 这个文件夹里的 topstepx_config.example.json 是安全的示例，真实配置不要提交到 git。

准备好后：
- 把你的真实 topstepx_config.json 放到这个文件夹根目录
- 运行 ./build_app.sh
- 整个文件夹就可以直接复制到另一台自己的电脑上直接使用了。

=== 常见问题：图标变白（白色的通用 App 图标） ===
这是 macOS 的图标缓存问题（LaunchServices / Icon Services），**不是你的 App 坏了**。

常见于：
- 刚复制文件夹到新电脑
- 刚跑完 ./build_app.sh
- Ad-hoc 签名的 App（自用版本常见）

**在新电脑上的解决方法（按顺序试）：**

1. 在终端进入文件夹后执行：
   touch "TSX Deck.app"
   killall Dock

2. 在 Finder 里打开 outputs/ 文件夹，选中 TSX Deck.app，按空格预览，或右键 "显示简介"。

3. 如果还是白：
   - 把 TSX Deck.app 拖到桌面，再拖回来
   - 或者运行一次完整的 ./build_app.sh （推荐，重新签名通常能解决）

4. 极端情况：注销登录 或 重启电脑。

**为什么新电脑也会出现？**
因为你是从另一台电脑复制过去的，macOS 的缓存不认识这个签名过的 bundle。

**好消息**：
- 只要你按上面步骤操作一次，通常就能恢复。
- 以后每次在新电脑上跑 ./build_app.sh 后，图标基本都会正常。
- 这个现象在所有 ad-hoc 签名的 Mac App 上都很常见，不是这个项目的 bug。

构建脚本现在会在构建结束时自动 touch App，并提示你这个命令。

