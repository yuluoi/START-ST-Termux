#!/bin/bash

# ===================================================================================
# --- [可修改区块] 全局变量定义 ---
# 此处定义了脚本中会用到的所有路径、URL和可配置参数。
# ===================================================================================

# --- 核心程序路径 ---
sillytavern_dir="$HOME/SillyTavern"                    # [可修改] SillyTavern的主程序目录路径。
llm_proxy_dir="$HOME/-gemini-"                         # [可修改] LLM代理服务的主程序目录路径。

# --- 状态与配置文件路径 ---
st_pid_file="$HOME/.sillytavern_runner.pid"            # SillyTavern的PID文件路径，用于状态检测。不建议修改。
llm_pid_file="$HOME/.llm-proxy/logs/llm-proxy.pid"     # LLM代理的PID文件路径，由其自身创建。不建议修改。
llm_startup_log="$HOME/.llm-proxy/logs/startup.log"    # LLM代理的启动日志文件路径。不建议修改。
config_file="$HOME/.st_launcher_config"                # 本启动器脚本的配置文件路径。不建议修改。

# --- 网络与URL ---
proxy_url="https://ghfast.top"                         # [可修改] 访问GitHub时使用的代理/镜像地址。
install_script_url="https://raw.githubusercontent.com/rzline/st-cr-ins.sh/main/install.sh" # [可修改] 备用安装脚本的下载地址。
install_script_name="install.sh"                       # [可修改] 备用安装脚本在本地保存的名称。
termux_api_apk_url="https://github.com/termux/termux-api/releases" # [可修改] Termux:API 配套APP的下载页面地址。

# --- 行为参数 ---
menu_timeout=10 # [可修改] 主菜单无操作时的自动选择倒计时(秒)。范围: 建议5-30。设置为0可禁用。


# --- [功能区块] 配置管理 ---
# 这两个函数负责加载和保存在`.st_launcher_config`文件中的用户设置。
load_config() {
    enable_notification_keepalive="true"; enable_auto_start="true"
    if [ -f "$config_file" ]; then source "$config_file"; fi
    save_config
}
save_config() {
    echo "enable_notification_keepalive=$enable_notification_keepalive" > "$config_file"
    echo "enable_auto_start=$enable_auto_start" >> "$config_file"
}

# --- [功能区块] 通用工具函数 ---
# err: 显示标准化的错误信息并等待用户确认。
err() { echo; echo "❌ 错误: $1" >&2; read -n 1 -p "按任意键继续..."; }
# cleanup: 脚本退出时执行的清理操作，如移除状态文件和通知。
cleanup() {
    rm -f "$st_pid_file"
    if [ "$enable_notification_keepalive" = true ]; then
        command -v termux-notification-remove >/dev/null && termux-notification-remove 1001
    fi
}

# --- [功能区块] 监控式启动LLM代理服务 ---
# 本函数负责以静默、后台的方式启动LLM代理。
# 它会监控启动过程，直到确认服务成功运行(PID文件被创建)或超时失败。
start_llm_proxy() {
    local start_script_path="$llm_proxy_dir/dist/手机安卓一键脚本/666/start-termux.sh"
    echo "正在尝试启动 LLM 代理服务..."
    if [ ! -d "$llm_proxy_dir" ]; then err "LLM代理服务目录 '$llm_proxy_dir' 不存在！"; return 1; fi
    if [ ! -f "$start_script_path" ]; then err "启动脚本 '$start_script_path' 未找到！"; return 1; fi

    rm -f "$llm_pid_file"
    > "$llm_startup_log"

    echo "在后台启动服务进程，并将所有输出写入日志..."
    (cd "$(dirname "$start_script_path")" && chmod +x start-termux.sh && ./start-termux.sh start) > "$llm_startup_log" 2>&1 &

    echo -n "正在等待服务初始化 (最长20秒) "
    local timeout=20 # [可修改] 等待服务初始化的最长秒数。如果您的设备启动服务较慢，可适当增加此值，例如 30 或 40。
    while [ $timeout -gt 0 ]; do
        if [ -f "$llm_pid_file" ] && kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then
            echo
            echo "✅ 服务成功启动！PID: $(cat "$llm_pid_file")。已在后台静默运行。"
            sleep 2
            return 0
        fi
        echo -n "."
        sleep 1
        timeout=$((timeout - 1))
    done

    err "服务在20秒内未能成功启动！请检查启动日志: $llm_startup_log"
    return 1
}

# --- [功能区块] 停止LLM代理服务 ---
# 本函数负责停止正在运行的LLM代理服务。
# 它会先尝试优雅停止，如果失败则强制停止，并清理PID文件。
stop_llm_proxy() {
    echo "正在尝试停止 LLM 代理服务..."
    if [ ! -f "$llm_pid_file" ]; then
        err "找不到PID文件。服务可能已经停止或异常退出。"
        return 1
    fi

    local pid
    pid=$(cat "$llm_pid_file")
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ℹ️ PID文件存在，但进程($pid)未运行。可能是陈旧文件。"
        rm -f "$llm_pid_file"
        echo "✅ 已清理陈旧的PID文件。"
        sleep 2
        return 0
    fi

    echo "正在停止进程 PID: $pid..."
    kill "$pid"
    local countdown=5 # [可修改] 尝试优雅停止时等待的秒数。
    while [ $countdown -gt 0 ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "✅ 服务已成功停止。"
            rm -f "$llm_pid_file"
            sleep 2
            return 0
        fi
        sleep 1
        countdown=$((countdown - 1))
    done

    echo "服务未能优雅地停止，正在强制终止..."
    kill -9 "$pid"
    sleep 1
    rm -f "$llm_pid_file"
    echo "✅ 服务已被强制停止。"
    sleep 2
    return 0
}


# --- [功能区块] 各类设置与管理子菜单 ---
# 以下函数分别对应“附加功能”子菜单中的各个选项，用于修改设置或管理软件包等。
toggle_notification_submenu() {
    clear; echo "========================================="; echo "           通知保活功能设置            "; echo "========================================="; echo
    echo "  此功能通过创建一个常驻通知来增强后台保活。"; echo "  当前状态: $enable_notification_keepalive"; echo; echo "========================================="
    read -p "请输入 'true' 或 'false' 来修改设置: " new_status
    if [ "$new_status" == "true" ] || [ "$new_status" == "false" ]; then
        enable_notification_keepalive="$new_status"; save_config; echo "✅ 设置已更新为 [$new_status] 并已保存。"
    else echo "无效输入，设置未改变。"; fi; sleep 2
}
toggle_auto_start_submenu() {
    clear; echo "========================================="; echo "         跨会话自动启动设置            "; echo "========================================="; echo
    echo "  此功能用于在检测到SillyTavern已运行时，"; echo "  自动在新会话中启动LLM代理服务。"; echo "  当前状态: $enable_auto_start"; echo; echo "========================================="
    read -p "请输入 'true' 或 'false' 来修改设置: " new_status
    if [ "$new_status" == "true" ] || [ "$new_status" == "false" ]; then
        enable_auto_start="$new_status"; save_config; echo "✅ 设置已更新为 [$new_status] 并已保存。"
    else echo "无效输入，设置未改变。"; fi; sleep 2
}
display_service_status() {
    local st_status_text="\033[0;31m未启动\033[0m"
    local llm_status_text="\033[0;31m未启动\033[0m"

    if [ "$st_is_running" = true ]; then
        st_status_text="\033[0;32m已启动\033[0m"
    fi
    if [ "$llm_is_running" = true ]; then
        llm_status_text="\033[0;32m已启动\033[0m"
    fi

    echo "========================================="
    echo "服务运行状态:"
    echo -e "  SillyTavern:   $st_status_text"
    echo -e "  LLM代理服务:  $llm_status_text"
    echo "========================================="
}
package_manager_submenu() { local pkg_name=$1; local cmd_to_check=$2; local is_core=$3; while true; do clear; echo "========================================="; echo "          软件包管理: $pkg_name          "; echo "========================================="; echo; if [ "$is_core" = true ]; then echo "   [ ⚠️ 必要 ] 此软件包是运行的核心依赖。"; else echo "   [ ✨ 可选 ] 此软件包提供额外功能。"; fi; echo; echo "   [1] 安装此软件包 (命令行)"; echo; echo "   [2] 卸载此软件包 (命令行)"; echo; if [ "$pkg_name" == "termux-api" ]; then echo "   [D] 在浏览器中打开配套APP下载页面"; echo; fi; echo "   [0] 返回上一级"; echo; echo "========================================="; read -n 1 -p "请按键选择: " action_choice; echo; case "$action_choice" in 1) if command -v "$cmd_to_check" >/dev/null; then echo "✅ 软件包 $pkg_name 似乎已经安装。"; sleep 2; else read -n 1 -p "准备安装 $pkg_name ，是否确认 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then pkg install "$pkg_name" -y; echo "安装完成！"; sleep 2; else echo "已取消安装。"; sleep 1; fi; fi;; 2) if ! command -v "$cmd_to_check" >/dev/null; then echo "ℹ️ 软件包 $pkg_name 尚未安装。"; sleep 2; else if [ "$is_core" = true ]; then echo "警告：这是一个核心软件包，卸载可能导致程序无法运行！"; fi; read -n 1 -p "准备卸载 $pkg_name ，是否确认 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then pkg uninstall "$pkg_name" -y; echo "卸载完成！"; sleep 2; else echo "已取消卸载。"; sleep 1; fi; fi;; "d"|"D") if [ "$pkg_name" == "termux-api" ]; then if command -v termux-open-url >/dev/null; then echo "正在浏览器中打开下载页面..."; termux-open-url "$termux_api_apk_url"; sleep 2; else echo "错误: termux-open-url 命令不可用！请先安装 termux-api 命令行包。"; sleep 3; fi; else echo "无效选择..."; sleep 1; fi;; 0) break;; *) echo "无效选择..."; sleep 1;; esac; done; }
package_selection_submenu() { while true; do clear; echo "========================================="; echo "           必要软件包管理              "; echo "========================================="; echo; echo "   [1] git (版本控制)       - ⚠️ 必要"; echo; echo "   [2] curl (网络下载)      - ⚠️ 必要"; echo; echo "   [3] nodejs-lts (运行环境) - ⚠️ 必要"; echo; echo "   [4] jq (版本显示)        - ✨ 可选"; echo; echo "   [5] termux-api (后台保活)  - ✨ 可选"; echo; echo "   [0] 返回主菜单"; echo; echo "========================================="; read -n 1 -p "请按键选择要管理的软件包 [1-5, 0]: " pkg_choice; echo; case "$pkg_choice" in 1) package_manager_submenu "git" "git" true;; 2) package_manager_submenu "curl" "curl" true;; 3) package_manager_submenu "nodejs-lts" "node" true;; 4) package_manager_submenu "jq" "jq" false;; 5) package_manager_submenu "termux-api" "termux-wake-lock" false;; 0) break;; *) echo "无效选择..."; sleep 1; continue;; esac; done; }
termux_setup() { clear; echo "========================================="; echo "       欢迎使用 Termux 环境初始化        "; echo "========================================="; echo; echo "本向导将为您更新系统并安装所有核心依赖。"; echo "这是一个一次性操作，可以确保脚本稳定运行。"; echo; read -n 1 -p "是否立即开始 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then echo; echo "--- [步骤 1/2] 正在更新 Termux 基础包 ---"; yes | pkg upgrade; echo "--- [步骤 2/2] 正在安装核心软件包 ---"; apt update && apt install git curl nodejs-lts -y; echo "✅ 环境初始化完成！"; sleep 2; else echo; echo "已取消初始化。"; sleep 2; fi; }
use_proxy() { local country; country=$(curl -s --connect-timeout 5 ipinfo.io/country 2>/dev/null); if [[ "$country" == "CN" ]]; then read -rp "检测到大陆IP，是否使用代理加速 (Y/n)? " yn; [[ "$yn" =~ ^[Nn]$ ]] && return 1 || return 0; fi; return 1; }
install_or_update_st_standalone() { local repo_url="https://github.com/SillyTavern/SillyTavern"; if use_proxy; then repo_url="$proxy_url/$repo_url"; fi; if [ -d "$sillytavern_dir/.git" ]; then echo "正在更新 SillyTavern..."; (cd "$sillytavern_dir" && git pull) || { err "Git 更新失败！"; return 1; }; else echo "正在首次安装 SillyTavern..."; git clone --depth 1 --branch release "$repo_url" "$sillytavern_dir" || { err "Git 克隆失败！"; return 1; }; fi; echo "正在安装/更新 npm 依赖..."; (cd "$sillytavern_dir" && npm install) || { err "npm 依赖安装失败！"; return 1; }; echo "✅ SillyTavern 安装/更新完成！"; }
get_st_local_ver() { command -v jq >/dev/null && [ -f "$sillytavern_dir/package.json" ] && jq -r .version "$sillytavern_dir/package.json" || echo "未知"; }
get_st_latest_ver() { command -v jq >/dev/null && curl -s --connect-timeout 5 "https://api.github.com/repos/SillyTavern/SillyTavern/releases/latest" | jq -r .tag_name || echo "获取失败"; }
update_submenu() { clear; echo "========================================="; echo "          正在检查 SillyTavern 版本...         "; echo "========================================="; local_ver=$(get_st_local_ver); latest_ver=$(get_st_latest_ver); echo; echo "  当前版本: $local_ver"; echo "  最新版本: $latest_ver"; echo; if [ -z "$latest_ver" ] || [ "$latest_ver" == "获取失败" ]; then echo "  ❌ 未能获取最新版本信息..."; echo; echo "========================================="; read -n 1 -p "按任意键返回..."; return; fi; if [ "$local_ver" == "$latest_ver" ] && [ "$local_ver" != "未知" ]; then echo "  ✅ 已是最新版本。"; echo; echo "========================================="; read -n 1 -p "按任意键返回..."; return; fi; prompt_text="发现新版本！"; [ "$local_ver" == "未知" ] && prompt_text="SillyTavern 尚未安装或无法检查版本(可能未安装jq)。"; echo "  $prompt_text"; echo "========================================="; echo; echo "   [1] 立即下载/更新"; echo; echo "   [2] 暂不操作"; echo; echo "========================================="; read -n 1 -p "请按键选择 [1-2]: " choice; echo; if [ "$choice" == "1" ]; then clear; install_or_update_st_standalone; echo; read -n 1 -p "操作完成！按任意键返回..."; fi; }
additional_features_submenu() {
    while true; do
        clear; echo "========================================="; echo "                附加功能                 "; echo "========================================="; echo
        echo "   [1] 📦 软件包管理"; echo; echo "   [2] 🚀 Termux 环境初始化"; echo; echo "   [3] 🔔 通知保活设置 (当前: $enable_notification_keepalive)"; echo; echo "   [4] ⚡️ 跨会话自启设置 (当前: $enable_auto_start)"; echo; echo "   [5] ⚙️  进入(可选的)原版脚本菜单"; echo; echo "   [0] ↩️  返回主菜单"; echo; echo "========================================="
        read -n 1 -p "请按键选择 [1-5, 0]: " sub_choice; echo
        case "$sub_choice" in
            1) package_selection_submenu;;
            2) termux_setup;;
            3) toggle_notification_submenu;;
            4) toggle_auto_start_submenu;;
            5)
                if [ ! -f "$install_script_name" ]; then
                    clear; echo "========================================="; echo "      ⚠️ $install_script_name 脚本不存在"; echo "========================================="; echo; echo "   [1] 立即下载"; echo; echo "   [2] 暂不下载"; echo; echo "========================================="
                    read -n 1 -p "请按键选择 [1-2]: " choice; echo
                    if [ "$choice" == "1" ]; then
                        echo "正在下载 $install_script_name..."; curl -s -O "$install_script_url" && chmod +x "$install_script_name"
                        if [ $? -eq 0 ]; then echo "下载成功！正在进入..."; sleep 1; clear; ./"$install_script_name"; exit 0; else err "下载失败！"; fi
                    fi
                else echo "选择 [5]，正在进入原版脚本菜单..."; sleep 1; clear; ./"$install_script_name"; exit 0; fi
                ;;
            0) break;;
            *) err "输入错误！请重新选择。";;
        esac
    done
}


# ===================================================================================
# --- [功能区块] 脚本主程序入口 ---
# 从这里开始，是脚本的主要执行流程。
# ===================================================================================
load_config
trap cleanup EXIT

# --- [功能区块] 前置任务：跨会话自动启动 ---
# 如果开启了此功能，并且检测到SillyTavern已在运行而LLM代理未运行，
# 脚本会在这里自动尝试启动LLM代理，然后继续进入主菜单。
st_is_running=false
if [ -f "$st_pid_file" ]; then
    if kill -0 "$(cat "$st_pid_file")" 2>/dev/null; then
        st_is_running=true
    else
        rm -f "$st_pid_file"
    fi
fi
if [ "$enable_auto_start" = true ] && [ "$st_is_running" = true ]; then
    llm_is_running=false
    if [ -f "$llm_pid_file" ]; then
        if kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then
            llm_is_running=true
        fi
    fi
    if [ "$llm_is_running" = false ]; then
        st_pid=$(cat "$st_pid_file")
        clear
        echo "✅ 检测到 SillyTavern (PID: $st_pid) 正在运行。"
        echo "🚀 根据预设逻辑，将自动启动 LLM 代理服务..."
        start_llm_proxy
        echo "自动启动任务完成。正在进入主菜单..."
        sleep 1
    fi
fi


# --- [功能区块] 主菜单循环 ---
# 这是脚本的核心交互部分。它会持续显示菜单，等待用户输入，并执行相应操作。
# 每次操作结束后，都会回到这里，刷新状态并重新显示菜单。
while true; do
    # 每次循环开始时都重新检查所有服务的运行状态。
    st_is_running=false
    if [ -f "$st_pid_file" ] && kill -0 "$(cat "$st_pid_file")" 2>/dev/null; then st_is_running=true; fi
    llm_is_running=false
    if [ -f "$llm_pid_file" ] && kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then llm_is_running=true; fi
    
    clear
    keepalive_status_text="(带唤醒锁)"; if [ "$enable_notification_keepalive" = true ]; then keepalive_status_text="(唤醒锁+通知)"; fi
    
    # --- [功能区块] 动态生成菜单选项 ---
    # 根据LLM代理的运行状态，决定菜单项[2]显示为“启动”还是“停止”。
    llm_action_text=""
    if [ "$llm_is_running" = true ]; then
        llm_action_text="🛑 停止LLM代理服务"
    else
        llm_action_text="📤 启动LLM代理服务"
    fi

    # 显示主菜单界面
    echo "========================================="; echo "       欢迎使用 Termux 启动脚本        "; echo "========================================="
    echo; echo "   [1] 🟢 启动 SillyTavern $keepalive_status_text"; echo; echo "   [2] $llm_action_text"; echo; echo "   [3] 🔄 (首次)安装 / 检查更新 SillyTavern"; echo; echo "   [4] 🛠️  附加功能"; echo; echo "   [0] ❌ 退出到 Termux 命令行";
    
    display_service_status
    
    # --- [功能区块] 用户输入处理 (带倒计时) ---
    # 如果SillyTavern未运行，则提供倒计时自动选择功能；否则，仅等待用户输入。
    choice=""
    if [ "$st_is_running" = true ]; then
        read -n 1 -p "请按键选择 [1-4, 0]: " choice; echo
    else
        prompt_text="请按键选择 [1-4, 0] "
        final_text="秒后自动选1): "
        for i in $(seq $menu_timeout -1 1); do
            printf "\r%s(%2d%s" "$prompt_text" "$i" "$final_text"
            read -n 1 -t 1 choice
            if [ -n "$choice" ]; then break; fi
        done
        printf "\r\033[K"
        choice=${choice:-1}
    fi

    # 根据用户的选择，执行相应的操作。
    case "$choice" in
        1)
            if [ "$st_is_running" = true ]; then err "SillyTavern 已在运行中！"; continue; fi
            if [ ! -f "$sillytavern_dir/server.js" ]; then err "SillyTavern 尚未安装，请用选项[3]安装。"; continue; fi
            echo "选择 [1]，正在启动 SillyTavern...";
            if command -v termux-wake-lock >/dev/null; then termux-wake-lock; fi
            if [ "$enable_notification_keepalive" = true ]; then if command -v termux-notification >/dev/null; then termux-notification --id 1001 --title "SillyTavern 正在运行" --content "服务已启动" --ongoing; fi; fi
            sleep 1; (cd "$sillytavern_dir" && node server.js) &
            st_pid=$!; echo "$st_pid" > "$st_pid_file"; echo "SillyTavern 已启动 (PID: $st_pid)，状态文件已创建。"; wait "$st_pid"; err "SillyTavern 已停止！"
            break
            ;;
        2) 
            # 根据LLM代理的运行状态，智能地调用启动或停止函数。
            if [ "$llm_is_running" = true ]; then
                stop_llm_proxy
            else
                start_llm_proxy
            fi
            ;;
        3) update_submenu;;
        4) additional_features_submenu;;
        0) echo "选择 [0]，已退回到 Termux 命令行。"; pkill -f "termux-wake-lock" &> /dev/null; break;;
        *) err "输入错误！请重新选择。";;
    esac
done