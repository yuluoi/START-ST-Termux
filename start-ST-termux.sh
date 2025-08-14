#!/bin/bash

if ! command -v jq > /dev/null; then
    echo "正在安装版本检查工具 jq..."
    pkg install jq -y
fi

sillytavern_dir="SillyTavern"

if ! pgrep -f "termux-wake-lock" > /dev/null; then
    echo "💡 Termux后台唤醒锁已自动启动。"
    termux-wake-lock &
fi

if [ ! -f "install.sh" ]; then
    echo "正在下载主安装脚本 install.sh..."
    curl -s -O https://raw.githubusercontent.com/rzline/st-cr-ins.sh/main/install.sh && chmod +x install.sh
fi

if [ ! -d "$sillytavern_dir" ]; then
    echo "检测到 SillyTavern 尚未安装，正在执行首次安装..."
    ./install.sh -is
fi

get_st_local_ver() {
    [ -f "$sillytavern_dir/package.json" ] && jq -r .version "$sillytavern_dir/package.json" || echo "未安装"
}

get_st_latest_ver() {
    curl -s "https://api.github.com/repos/SillyTavern/SillyTavern/releases/latest" | jq -r .tag_name
}

update_submenu() {
    clear
    echo "========================================="
    echo "          正在检查 SillyTavern 版本...         "
    echo "========================================="
    
    local_ver=$(get_st_local_ver)
    latest_ver=$(get_st_latest_ver)

    echo
    echo "  当前版本: $local_ver"
    echo "  最新版本: $latest_ver"
    echo

    if [ "$local_ver" == "$latest_ver" ]; then
        echo "  ✅ 已是最新版本，无需更新。"
        echo
        echo "========================================="
        read -n 1 -p "按任意键返回主菜单..."
        return
    fi

    echo "  发现新版本！"
    echo "========================================="
    echo
    echo "   [1] 立即更新"
    echo
    echo "   [2] 暂不更新，返回主菜单"
    echo
    echo "========================================="
    
    read -n 1 -p "请选择 [1-2]: " update_choice
    echo

    case "$update_choice" in
        1)
            echo "正在执行更新..."
            clear
            ./install.sh -is
            echo "更新完成！按任意键返回主菜单..."
            read -n 1
            ;;
        2)
            echo "已取消更新，正在返回主菜单..."
            sleep 1
            ;;
        *)
            echo "无效选择，正在返回主菜单..."
            sleep 1
            ;;
    esac
}

cleanup() {
    termux-notification-remove 1001
}

while true; do
    clear
    echo "========================================="
    echo "       欢迎使用 Termux 启动脚本        "
    echo "========================================="
    echo
    echo "   [1] 🟢 启动 SillyTavern"
    echo
    echo "   [2] 🔄 检查更新"
    echo
    echo "   [3] ❌ 退出到 Termux 命令行"
    echo
    echo "   [4] ⚙️  进入原版脚本菜单"
    echo
    echo "========================================="

    read -n 1 -t 8 -p "请按键选择 [1-4] (8秒后自动选1): " choice
    echo

    case "${choice:-1}" in
        1)
            echo "选择 [1]，正在启动 SillyTavern..."
            termux-notification --id 1001 --title "SillyTavern 正在运行" --content "服务已启动，保持此通知可防止进程被杀" --ongoing
            
            sleep 1
            ./install.sh -ss
            
            cleanup
            break
            ;;
        2)
            update_submenu
            ;;
        3)
            echo "选择 [3]，已退回到 Termux 命令行。"
            cleanup
            break
            ;;
        4)
            echo "选择 [4]，正在进入原版脚本菜单..."
            sleep 1
            clear
            ./install.sh
            break
            ;;
        *)
            echo "输入错误！请重新选择。"
            sleep 2
            ;;
    esac
done