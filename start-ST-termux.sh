#!/bin/bash

# ===================================================================================
# --- [可修改区块] 全局变量定义 ---
# ===================================================================================
sillytavern_dir="$HOME/SillyTavern"
sillytavern_old_dir="$HOME/SillyTavern_old"
llm_proxy_dir="$HOME/-gemini-"
st_pid_file="$HOME/.sillytavern_runner.pid"
llm_pid_file="$HOME/.llm-proxy/logs/llm-proxy.pid"
llm_startup_log="$HOME/.llm-proxy/logs/startup.log"
config_file="$HOME/.st_launcher_config"
proxy_url="https://ghfast.top"
install_script_url="https://raw.githubusercontent.com/rzline/st-cr-ins.sh/main/install.sh"
install_script_name="install.sh"
termux_api_apk_url="https://github.com/termux/termux-api/releases"
menu_timeout=10 # [可修改] 主菜单无操作时的自动选择倒计时(秒)。

# --- [区块] 配置管理 ---
load_config() {
    enable_notification_keepalive="true"; enable_auto_start="true"
    if [ -f "$config_file" ]; then source "$config_file"; fi
    save_config
}
save_config() {
    echo "enable_notification_keepalive=$enable_notification_keepalive" > "$config_file"
    echo "enable_auto_start=$enable_auto_start" >> "$config_file"
}

# --- [区块] 通用工具函数 ---
err() { echo; echo "❌ 错误: $1" >&2; read -n 1 -p "按任意键继续..."; }
cleanup() {
    rm -f "$st_pid_file"
    if [ "$enable_notification_keepalive" = true ]; then
        command -v termux-notification-remove >/dev/null && termux-notification-remove 1001
    fi
}

# --- [区块] LLM 代理服务启停 ---
start_llm_proxy() {
    local start_script_path="$llm_proxy_dir/dist/手机安卓一键脚本/666/start-termux.sh"
    echo "正在尝试启动 LLM 代理服务..."
    if [ ! -d "$llm_proxy_dir" ]; then err "LLM代理服务目录 '$llm_proxy_dir' 不存在！"; return 1; fi
    if [ ! -f "$start_script_path" ]; then err "启动脚本 '$start_script_path' 未找到！"; return 1; fi
    rm -f "$llm_pid_file"; > "$llm_startup_log"
    echo "在后台启动服务进程，并将所有输出写入日志..."
    (cd "$(dirname "$start_script_path")" && chmod +x start-termux.sh && ./start-termux.sh start) > "$llm_startup_log" 2>&1 &
    echo -n "正在等待服务初始化 (最长20秒) "; local timeout=20
    while [ $timeout -gt 0 ]; do
        if [ -f "$llm_pid_file" ] && kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then
            echo; echo "✅ 服务成功启动！PID: $(cat "$llm_pid_file")。已在后台静默运行。"; sleep 2; return 0
        fi
        echo -n "."; sleep 1; timeout=$((timeout - 1))
    done
    err "服务在20秒内未能成功启动！请检查启动日志: $llm_startup_log"; return 1
}
stop_llm_proxy() {
    echo "正在尝试停止 LLM 代理服务..."
    if [ ! -f "$llm_pid_file" ]; then err "找不到PID文件。服务可能已经停止。"; return 1; fi
    local pid; pid=$(cat "$llm_pid_file")
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ℹ️ PID文件存在，但进程($pid)未运行。"; rm -f "$llm_pid_file"; echo "✅ 已清理陈旧的PID文件。"; sleep 2; return 0
    fi
    echo "正在停止进程 PID: $pid..."; kill "$pid"; local countdown=5
    while [ $countdown -gt 0 ]; do
        if ! kill -0 "$pid" 2>/dev/null; then echo "✅ 服务已成功停止。"; rm -f "$llm_pid_file"; sleep 2; return 0; fi
        sleep 1; countdown=$((countdown - 1))
    done
    echo "服务未能优雅地停止，正在强制终止..."; kill -9 "$pid"; sleep 1; rm -f "$llm_pid_file"
    echo "✅ 服务已被强制停止。"; sleep 2; return 0
}

# --- [区块] SillyTavern 安装与更新 ---
use_proxy() { local country; country=$(curl -s --connect-timeout 5 ipinfo.io/country 2>/dev/null); if [[ "$country" == "CN" ]]; then read -rp "检测到大陆IP，是否使用代理加速 (Y/n)? " yn; [[ "$yn" =~ ^[Nn]$ ]] && return 1 || return 0; fi; return 1; }
get_st_local_ver() { command -v jq >/dev/null && [ -f "$sillytavern_dir/package.json" ] && jq -r .version "$sillytavern_dir/package.json" || echo "未知"; }
get_st_latest_ver() { command -v jq >/dev/null && curl -s --connect-timeout 5 "https://api.github.com/repos/SillyTavern/SillyTavern/releases/latest" | jq -r .tag_name || echo "获取失败"; }
update_st_incremental() {
    if [ ! -d "$sillytavern_dir/.git" ]; then err "错误：找不到 .git 目录，无法增量更新。"; return 1; fi
    echo "正在执行增量更新 (git pull)..."; (cd "$sillytavern_dir" && git pull) || { err "Git 更新失败！"; return 1; }
    echo "正在更新 npm 依赖..."; (cd "$sillytavern_dir" && npm install) || { err "npm 依赖安装失败！"; return 1; }; echo "✅ 增量更新完成！"
}

# --- [【核心修复】采用 proven, working data migration logic from hoping喵 script] ---
install_st_fresh() {
    local repo_url="https://github.com/SillyTavern/SillyTavern"; if use_proxy; then repo_url="$proxy_url/$repo_url"; fi
    local temp_new_dir="$HOME/SillyTavern_new"; echo "正在克隆全新的 SillyTavern 到临时目录..."; rm -rf "$temp_new_dir"
    git clone --depth 1 --branch release "$repo_url" "$temp_new_dir" || { err "Git 克隆失败！"; rm -rf "$temp_new_dir"; return 1; }
    echo "正在安装 npm 依赖..."; (cd "$temp_new_dir" && npm install) || { err "npm 依赖安装失败！"; rm -rf "$temp_new_dir"; return 1; }
    
    if [ -d "$sillytavern_dir" ]; then
        echo "正在迁移您的用户数据 (characters, chats, settings...)"
        
        # 忠实地、完整地移植 hoping喵 的数据迁移逻辑
        if [ -d "$sillytavern_dir/data/default-user" ]; then
            cp -r "$sillytavern_dir/data/default-user/characters/." "$temp_new_dir/public/characters/"
            cp -r "$sillytavern_dir/data/default-user/chats/." "$temp_new_dir/public/chats/"
            cp -r "$sillytavern_dir/data/default-user/worlds/." "$temp_new_dir/public/worlds/"
            cp -r "$sillytavern_dir/data/default-user/groups/." "$temp_new_dir/public/groups/"
            cp -r "$sillytavern_dir/data/default-user/group chats/." "$temp_new_dir/public/group chats/"
            cp -r "$sillytavern_dir/data/default-user/OpenAI Settings/." "$temp_new_dir/public/OpenAI Settings/"
            cp -r "$sillytavern_dir/data/default-user/User Avatars/." "$temp_new_dir/public/User Avatars/"
            cp -r "$sillytavern_dir/data/default-user/backgrounds/." "$temp_new_dir/public/backgrounds/"
            cp -r "$sillytavern_dir/data/default-user/settings.json" "$temp_new_dir/public/settings.json"
        else
            cp -r "$sillytavern_dir/public/characters/." "$temp_new_dir/public/characters/"
            cp -r "$sillytavern_dir/public/chats/." "$temp_new_dir/public/chats/"
            cp -r "$sillytavern_dir/public/worlds/." "$temp_new_dir/public/worlds/"
            cp -r "$sillytavern_dir/public/groups/." "$temp_new_dir/public/groups/"
            cp -r "$sillytavern_dir/public/group chats/." "$temp_new_dir/public/group chats/"
            cp -r "$sillytavern_dir/public/OpenAI Settings/." "$temp_new_dir/public/OpenAI Settings/"
            cp -r "$sillytavern_dir/public/User Avatars/." "$temp_new_dir/public/User Avatars/"
            cp -r "$sillytavern_dir/public/backgrounds/." "$temp_new_dir/public/backgrounds/"
            cp -r "$sillytavern_dir/public/settings.json" "$temp_new_dir/public/settings.json"
        fi
        
        echo "✅ 数据迁移完成。正在备份旧版本程序文件到 $sillytavern_old_dir..."
        rm -rf "$sillytavern_old_dir"; mv "$sillytavern_dir" "$sillytavern_old_dir"
    fi
    
    mv "$temp_new_dir" "$sillytavern_dir"; echo "✅ 全新安装/更新完成！"
}

version_rollback() {
    if [ ! -d "$sillytavern_old_dir" ]; then err "错误：未找到可用于回退的旧版本。"; return; fi
    read -n 1 -p "警告：这将用旧版本覆盖当前版本，是否确认 (y/n)? " confirm; echo
    if [ "$confirm" != "y" ]; then echo "已取消。"; sleep 1; return; fi
    echo "正在回退版本..."; mv "$sillytavern_dir" "$HOME/SillyTavern_temp"; mv "$sillytavern_old_dir" "$sillytavern_dir"
    mv "$HOME/SillyTavern_temp" "$sillytavern_old_dir"; echo "✅ 版本回退成功！"; sleep 2
}
update_submenu() {
    while true; do
        clear; echo "========================================="; echo "         SillyTavern 安装与更新          "; echo "========================================="
        local_ver=$(get_st_local_ver); latest_ver=$(get_st_latest_ver)
        echo; echo "  当前版本: $local_ver"; echo "  最新版本: $latest_ver"; echo "-----------------------------------------"
        echo; echo "   [1] 增量更新 (推荐，速度快)"; echo; echo "   [2] 全新更新 (强制覆盖，并保留数据)"; echo; echo "   [3] 版本回退 (恢复到上一个版本)"; echo; echo "   [0] 返回主菜单"; echo; echo "========================================="
        read -n 1 -p "请按键选择: " choice; echo
        case "$choice" in
            1) clear; update_st_incremental; echo; read -n 1 -p "操作完成！按任意键返回...";;
            2) 
                read -n 1 -p "警告：这将重新下载并覆盖程序文件，是否确认 (y/n)? " confirm; echo
                if [ "$confirm" == "y" ]; then clear; install_st_fresh; echo; read -n 1 -p "操作完成！按任意键返回..."; fi
                ;;
            3) clear; version_rollback;;
            0) break;;
            *) err "无效选择...";;
        esac
    done
}

# --- [区块] 其他子菜单 ---
additional_features_submenu() { while true; do clear; echo "========================================="; echo "                附加功能                 "; echo "========================================="; echo; echo "   [1] 📦 软件包管理"; echo; echo "   [2] 🚀 Termux 环境初始化"; echo; echo "   [3] 🔔 通知保活设置 (当前: $enable_notification_keepalive)"; echo; echo "   [4] ⚡️ 跨会话自启设置 (当前: $enable_auto_start)"; echo; echo "   [5] ⚙️  进入(可选的)原版脚本菜单"; echo; echo "   [0] ↩️  返回主菜单"; echo; echo "========================================="; read -n 1 -p "请按键选择 [1-5, 0]: " sub_choice; echo; case "$sub_choice" in 1) package_selection_submenu;; 2) termux_setup;; 3) toggle_notification_submenu;; 4) toggle_auto_start_submenu;; 5) if [ ! -f "$install_script_name" ]; then clear; echo "========================================="; echo "      ⚠️ $install_script_name 脚本不存在"; echo "========================================="; echo; echo "   [1] 立即下载"; echo; echo "   [2] 暂不下载"; echo; echo "========================================="; read -n 1 -p "请按键选择 [1-2]: " choice; echo; if [ "$choice" == "1" ]; then echo "正在下载 $install_script_name..."; curl -s -O "$install_script_url" && chmod +x "$install_script_name"; if [ $? -eq 0 ]; then echo "下载成功！正在进入..."; sleep 1; clear; ./"$install_script_name"; exit 0; else err "下载失败！"; fi; fi; else echo "选择 [5]，正在进入原版脚本菜单..."; sleep 1; clear; ./"$install_script_name"; exit 0; fi;; 0) break;; *) err "输入错误！请重新选择。";; esac; done; }
toggle_notification_submenu() { clear; echo "========================================="; echo "           通知保活功能设置            "; echo "========================================="; echo; echo "  此功能通过创建一个常驻通知来增强后台保活。"; echo "  当前状态: $enable_notification_keepalive"; echo; echo "========================================="; read -p "请输入 'true' 或 'false' 来修改设置: " new_status; if [ "$new_status" == "true" ] || [ "$new_status" == "false" ]; then enable_notification_keepalive="$new_status"; save_config; echo "✅ 设置已更新为 [$new_status] 并已保存。"; else echo "无效输入，设置未改变。"; fi; sleep 2; }
toggle_auto_start_submenu() { clear; echo "========================================="; echo "         跨会话自动启动设置            "; echo "========================================="; echo; echo "  此功能用于在检测到SillyTavern已运行时，"; echo "  自动在新会话中启动LLM代理服务。"; echo "  当前状态: $enable_auto_start"; echo; echo "========================================="; read -p "请输入 'true' 或 'false' 来修改设置: " new_status; if [ "$new_status" == "true" ] || [ "$new_status" == "false" ]; then enable_auto_start="$new_status"; save_config; echo "✅ 设置已更新为 [$new_status] 并已保存。"; else echo "无效输入，设置未改变。"; fi; sleep 2; }
display_service_status() { local st_status_text="\033[0;31m未启动\033[0m"; local llm_status_text="\033[0;31m未启动\033[0m"; if [ "$st_is_running" = true ]; then st_status_text="\033[0;32m已启动\033[0m"; fi; if [ "$llm_is_running" = true ]; then llm_status_text="\033[0;32m已启动\033[0m"; fi; echo "========================================="; echo "服务运行状态:"; echo -e "  SillyTavern:   $st_status_text"; echo -e "  LLM代理服务:  $llm_status_text"; echo "========================================="; }
package_manager_submenu() { local pkg_name=$1; local cmd_to_check=$2; local is_core=$3; while true; do clear; echo "========================================="; echo "          软件包管理: $pkg_name          "; echo "========================================="; echo; if [ "$is_core" = true ]; then echo "   [ ⚠️ 必要 ] 此软件包是运行的核心依赖。"; else echo "   [ ✨ 可选 ] 此软件包提供额外功能。"; fi; echo; echo "   [1] 安装此软件包 (命令行)"; echo; echo "   [2] 卸载此软件包 (命令行)"; echo; if [ "$pkg_name" == "termux-api" ]; then echo "   [D] 在浏览器中打开配套APP下载页面"; echo; fi; echo "   [0] 返回上一级"; echo; echo "========================================="; read -n 1 -p "请按键选择: " action_choice; echo; case "$action_choice" in 1) if command -v "$cmd_to_check" >/dev/null; then echo "✅ 软件包 $pkg_name 似乎已经安装。"; sleep 2; else read -n 1 -p "准备安装 $pkg_name ，是否确认 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then pkg install "$pkg_name" -y; echo "安装完成！"; sleep 2; else echo "已取消安装。"; sleep 1; fi; fi;; 2) if ! command -v "$cmd_to_check" >/dev/null; then echo "ℹ️ 软件包 $pkg_name 尚未安装。"; sleep 2; else if [ "$is_core" = true ]; then echo "警告：这是一个核心软件包，卸载可能导致程序无法运行！"; fi; read -n 1 -p "准备卸载 $pkg_name ，是否确认 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then pkg uninstall "$pkg_name" -y; echo "卸载完成！"; sleep 2; else echo "已取消卸载。"; sleep 1; fi; fi;; "d"|"D") if [ "$pkg_name" == "termux-api" ]; then if command -v termux-open-url >/dev/null; then echo "正在浏览器中打开下载页面..."; termux-open-url "$termux_api_apk_url"; sleep 2; else echo "错误: termux-open-url 命令不可用！请先安装 termux-api 命令行包。"; sleep 3; fi; else echo "无效选择..."; sleep 1; fi;; 0) break;; *) echo "无效选择..."; sleep 1;; esac; done; }
package_selection_submenu() { while true; do clear; echo "========================================="; echo "           必要软件包管理              "; echo "========================================="; echo; echo "   [1] git (版本控制)       - ⚠️ 必要"; echo; echo "   [2] curl (网络下载)      - ⚠️ 必要"; echo; echo "   [3] nodejs-lts (运行环境) - ⚠️ 必要"; echo; echo "   [4] jq (版本显示)        - ✨ 可选"; echo; echo "   [5] termux-api (后台保活)  - ✨ 可选"; echo; echo "   [0] 返回主菜单"; echo; echo "========================================="; read -n 1 -p "请按键选择要管理的软件包 [1-5, 0]: " pkg_choice; echo; case "$pkg_choice" in 1) package_manager_submenu "git" "git" true;; 2) package_manager_submenu "curl" "curl" true;; 3) package_manager_submenu "nodejs-lts" "node" true;; 4) package_manager_submenu "jq" "jq" false;; 5) package_manager_submenu "termux-api" "termux-wake-lock" false;; 0) break;; *) echo "无效选择..."; sleep 1; continue;; esac; done; }
termux_setup() { clear; echo "========================================="; echo "       欢迎使用 Termux 环境初始化        "; echo "========================================="; echo; echo "本向导将为您更新系统并安装所有核心依赖。"; echo "这是一个一次性操作，可以确保脚本稳定运行。"; echo; read -n 1 -p "是否立即开始 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then echo; echo "--- [步骤 1/2] 正在更新 Termux 基础包 ---"; yes | pkg upgrade; echo "--- [步骤 2/2] 正在安装核心软件包 ---"; apt update && apt install git curl nodejs-lts -y; echo "✅ 环境初始化完成！"; sleep 2; else echo; echo "已取消初始化。"; sleep 2; fi; }

# ===================================================================================
# --- [区块] 脚本主程序入口 ---
# ===================================================================================
load_config
trap cleanup EXIT

st_is_running=false
if [ -f "$st_pid_file" ] && kill -0 "$(cat "$st_pid_file")" 2>/dev/null; then st_is_running=true; else rm -f "$st_pid_file"; fi
if [ "$enable_auto_start" = true ] && [ "$st_is_running" = true ]; then
    llm_is_running=false
    if [ -f "$llm_pid_file" ] && kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then llm_is_running=true; fi
    if [ "$llm_is_running" = false ]; then
        st_pid=$(cat "$st_pid_file"); clear; echo "✅ 检测到 SillyTavern (PID: $st_pid) 正在运行。"; echo "🚀 根据预设逻辑，将自动启动 LLM 代理服务..."; start_llm_proxy; echo "自动启动任务完成。正在进入主菜单..."; sleep 1
    fi
fi

while true; do
    st_is_running=false; if [ -f "$st_pid_file" ] && kill -0 "$(cat "$st_pid_file")" 2>/dev/null; then st_is_running=true; fi
    llm_is_running=false; if [ -f "$llm_pid_file" ] && kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then llm_is_running=true; fi
    clear
    keepalive_status_text="(带唤醒锁)"; if [ "$enable_notification_keepalive" = true ]; then keepalive_status_text="(唤醒锁+通知)"; fi
    llm_action_text=""; if [ "$llm_is_running" = true ]; then llm_action_text="🛑 停止LLM代理服务"; else llm_action_text="📤 启动LLM代理服务"; fi

    echo "========================================="; echo "       欢迎使用 Termux 启动脚本        "; echo "========================================="
    echo; echo "   [1] 🟢 启动 SillyTavern $keepalive_status_text"; echo; echo "   [2] $llm_action_text"; echo; echo "   [3] 🔄 (首次)安装 / 检查更新 SillyTavern"; echo; echo "   [4] 🛠️  附加功能"; echo; echo "   [0] ❌ 退出到 Termux 命令行";
    display_service_status
    
    choice="";
    if [ "$st_is_running" = true ]; then read -n 1 -p "请按键选择 [1-4, 0]: " choice; echo
    else
        prompt_text="请按键选择 [1-4, 0] "; final_text="秒后自动选1): ";
        for i in $(seq $menu_timeout -1 1); do printf "\r%s(%2d%s" "$prompt_text" "$i" "$final_text"; read -n 1 -t 1 choice; if [ -n "$choice" ]; then break; fi; done
        printf "\r\033[K"; choice=${choice:-1}
    fi

    case "$choice" in
        1)
            if [ "$st_is_running" = true ]; then err "SillyTavern 已在运行中！"; continue; fi
            if [ ! -f "$sillytavern_dir/server.js" ]; then err "SillyTavern 尚未安装，请用选项[3]安装。"; continue; fi
            echo "选择 [1]，正在启动 SillyTavern...";
            if command -v termux-wake-lock >/dev/null; then termux-wake-lock; fi
            if [ "$enable_notification_keepalive" = true ]; then if command -v termux-notification >/dev/null; then termux-notification --id 1001 --title "SillyTavern 正在运行" --content "服务已启动" --ongoing; fi; fi
            sleep 1; (cd "$sillytavern_dir" && node server.js) &
            st_pid=$!; echo "$st_pid" > "$st_pid_file"; echo "SillyTavern 已启动 (PID: $st_pid)，按任意键可返回菜单（服务将在后台继续运行）。"; read -n 1; if ! kill -0 "$st_pid" 2>/dev/null; then cleanup; fi; continue
            ;;
        2) if [ "$llm_is_running" = true ]; then stop_llm_proxy; else start_llm_proxy; fi;;
        3) update_submenu;;
        4) additional_features_submenu;;
        0) echo "选择 [0]，已退回到 Termux 命令行。"; pkill -f "termux-wake-lock" &> /dev/null; break;;
        *) err "输入错误！请重新选择。";;
    esac
done