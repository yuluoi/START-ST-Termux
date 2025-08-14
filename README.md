# Termux SillyTavern 启动器（⚠️自用）

这是一个为 Termux 定制的的 SillyTavern 启动脚本。仅用作备份。

## 主要功能
- 带有进程守护功能的快速启动
- 智能更新检查与操作
- 自动处理后台保活（唤醒锁和前台服务通知）
- 交互式菜单，支持单键和超时操作

## 使用方法
将此项目中的 `start-ST-termux` 文件复制到 Termux 主目录 (`~`) 下，然后确保 `~/.bashrc` 文件包含以下内容：
```bash
chmod +x ./start-ST-termux.sh
./start-ST-termux.sh
```

## 🚀 快速启动 (一键运行)

在 Termux 中执行以下单行命令即可直接启动本脚本：

```bash
curl -sL https://raw.githubusercontent.com/yuluoi/START-ST-Termux/refs/heads/main/start-ST-termux.sh | bash
```