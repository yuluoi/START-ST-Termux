#!/bin/bash

# ===================================================================================
# --- [可修改区块] 全局变量定义 ---
# ===================================================================================
sillytavern_dir="$HOME/SillyTavern"
sillytavern_old_dir="$HOME/SillyTavern_old"
st_pid_file="$HOME/.sillytavern_runner.pid"
gcli_pid_file="$HOME/.gcli2api.pid"
build_pid_file="$HOME/.dark-server.pid"
# gcli2api 日志文件路径 (Termux 根目录)
gcli_log_file="$HOME/gcli2api_log.txt"
config_file="$HOME/.st_launcher_config"
password_alias_file="$HOME/.st_launcher_alias"
notify_file="$HOME/.st_launcher_notify"
script_path=$(readlink -f "$0")
script_name=$(basename "$0")
BASHRC_START_TAG="# <<< START MANAGED BLOCK BY $script_name >>>"
BASHRC_END_TAG="# <<< END MANAGED BLOCK BY $script_name >>>"
proxy_url="https://ghfast.top"
termux_api_apk_url="https://github.com/termux/termux-api/releases"
menu_timeout=10
enable_menu_timeout="true"

# 各独立模块路径 (已指向 START-ST-Termux 文件夹)
update_script="$HOME/START-ST-Termux/st_launcher_update.sh"
proxy_script="$HOME/START-ST-Termux/st_launcher_proxy.sh"
addons_script="$HOME/START-ST-Termux/st_launcher_addons.sh"

# 全局状态变量初始化
st_is_running=false
gcli_is_running=false
monitor_pid=""
keepalive_pid=""

# --- [区块] 配置管理 ---
load_config() {
    enable_notification_keepalive="true"
    enable_password_start="false"
    enable_menu_timeout="true"
    enable_linked_start="false"
    linked_proxy_service="none"
    enable_silent_start="false"
    silent_start_service="none"

    if [ -f "$config_file" ]; then source "$config_file"; fi
    save_config
}
save_config() {
    echo "enable_notification_keepalive=$enable_notification_keepalive" > "$config_file"
    echo "enable_password_start=$enable_password_start" >> "$config_file"
    echo "enable_menu_timeout=$enable_menu_timeout" >> "$config_file"
    echo "enable_linked_start=$enable_linked_start" >> "$config_file"
    echo "linked_proxy_service=$linked_proxy_service" >> "$config_file"
    echo "enable_silent_start=$enable_silent_start" >> "$config_file"
    echo "silent_start_service=$silent_start_service" >> "$config_file"
}

# --- [区块] 通用工具函数 ---
err() { echo; echo "❌ 错误: $1" >&2; read -n 1 -p "按任意键继续..."; }

cleanup() {
    rm -f "$st_pid_file"
    rm -f "$notify_file"
    if [ "$enable_notification_keepalive" = true ]; then
        command -v termux-notification-remove >/dev/null && termux-notification-remove 1001
    fi
    if [ -n "$monitor_pid" ]; then kill "$monitor_pid" 2>/dev/null; fi
    if [ -n "$keepalive_pid" ]; then kill "$keepalive_pid" 2>/dev/null; fi
}
trap cleanup EXIT

# --- [重写] Gcli 状态检测专用函数 ---
check_gcli_status() {
    if curl -s --connect-timeout 1 http://127.0.0.1:7861/ >/dev/null; then
        return 0
    else
        return 1
    fi
}

# --- [UI 核心] 统一顶部状态栏与轮询机制 ---
draw_top_header() {
    local st_status="\033[0;31m未启动\033[0m"
    local gcli_status="\033[0;31m未启动\033[0m"
    if [ "$st_is_running" = true ]; then st_status="\033[0;32m已启动\033[0m"; fi
    if [ "$gcli_is_running" = true ]; then gcli_status="\033[0;32m已启动\033[0m"; fi

    echo "========================================="
    echo " 📊 全局服务运行状态"
    echo -e " ST: $st_status  |  Gcli: $gcli_status"
    echo "========================================="
    echo
}

update_header_dynamic() {
    local st_status="\033[0;31m未启动\033[0m"
    local gcli_status="\033[0;31m未启动\033[0m"
    if [ "$st_is_running" = true ]; then st_status="\033[0;32m已启动\033[0m"; fi
    if [ "$gcli_is_running" = true ]; then gcli_status="\033[0;32m已启动\033[0m"; fi

    local header="\033[s\033[1;1H=========================================\n 📊 全局服务运行状态\n ST: $st_status  |  Gcli: $gcli_status\033[K\n=========================================\033[u"
    printf "%b" "$header"
}

poll_status() {
    local need_redraw=false
    
    if [ "$st_is_running" = true ]; then
        if ! kill -0 "$(cat "$st_pid_file" 2>/dev/null)" 2>/dev/null; then
            st_is_running=false
            need_redraw=true
        fi
    fi

    if [ -f "$notify_file" ]; then 
        local notif=$(cat "$notify_file" 2>/dev/null)
        rm -f "$notify_file"
        if [ "$notif" == "SUCCESS_GCLI" ]; then
            gcli_is_running=true
            need_redraw=true
        elif [ "$notif" == "FAIL_GCLI" ]; then
            gcli_is_running=false
            need_redraw=true
        fi
    fi
    
    if [ "$need_redraw" = true ]; then
        update_header_dynamic
    fi
}

prompt_with_poll() {
    local prompt_text="$1"
    local var_name="$2"
    local _p_choice=""
    printf "%s" "$prompt_text"
    while true; do
        read -t 1 -n 1 _p_choice
        local read_ret=$?
        poll_status
        if [ $read_ret -eq 0 ] && [ -n "$_p_choice" ]; then
            printf -v "$var_name" "%s" "$_p_choice"
            echo
            break
        fi
    done
}

# ===================================================================================
# --- [区块] 服务管理核心函数 (Gcli / Build) ---
# ===================================================================================

start_gcli_proxy() {
    local mode=$1 
    if check_gcli_status; then echo "✅ Gcli2api服务已在运行，跳过启动。"; return 0; fi

    echo "正在后台启动 gcli2api..."
    if [ -d "$HOME/gcli2api" ]; then
        local original_dir=$(pwd)
        cd "$HOME/gcli2api" || { echo "无法进入目录"; sleep 2; return 1; }

        pkill -f "bash termux-start.sh" >/dev/null 2>&1
        if command -v pm2 >/dev/null; then pm2 delete web >/dev/null 2>&1; fi
        sleep 0.5
        
        : > "$gcli_log_file"
        nohup bash termux-start.sh < /dev/null > "$gcli_log_file" 2>&1 &
        local new_pid=$!
        
        local check_interval=2
        local max_checks=30 
        local return_success_code=10
        local success_sleep_time=3
        
        if [ "$mode" == "linked" ]; then
            check_interval=2
            max_checks=30 
            return_success_code=0 
            success_sleep_time=0  
        fi

        echo "启动命令已发送 (PID: $new_pid)。"
        echo "================ 日志输出 (按任意键停止查看，服务不中断) ================"
        
        tail -f "$gcli_log_file" &
        local tail_pid=$!
        local check_count=0
        local detected_port=false
        local should_return_main=false
        
        while [ $check_count -lt $max_checks ]; do
            read -t $check_interval -n 1 -s -r key_input
            if [ $? -eq 0 ]; then
                kill "$tail_pid" 2>/dev/null; wait "$tail_pid" 2>/dev/null
                echo -e "\n已手动退出日志查看。"
                break
            fi
            
            if curl -s --connect-timeout 1 http://127.0.0.1:7861/ >/dev/null; then
                kill "$tail_pid" 2>/dev/null; wait "$tail_pid" 2>/dev/null
                echo -e "\n\033[1;32mgcli2api代理成功启动，正在运行中\033[0m"
                detected_port=true
                if [ $success_sleep_time -gt 0 ]; then sleep $success_sleep_time; fi
                if [ "$mode" == "verbose" ]; then should_return_main=true; fi
                break 
            fi
            check_count=$((check_count + 1))
        done
        
        kill "$tail_pid" 2>/dev/null; wait "$tail_pid" 2>/dev/null
        
        if [ "$detected_port" = false ]; then
            if [ $check_count -ge $max_checks ]; then echo -e "\n\033[1;31mgcli2api代理启动过程中可能遇到问题(或超时)，请查看详细日志\033[0m"; fi
            if [ "$mode" == "linked" ]; then
                echo "❌ [关联启动] 端口检测超时，终止后续操作。"
                if command -v pm2 >/dev/null; then pm2 delete web >/dev/null 2>&1; fi
                kill "$new_pid" 2>/dev/null; rm -f "$gcli_pid_file"; cd "$original_dir"
                return 1
            fi
        fi
        
        echo -e "\n=========================================================================="
        
        local is_success=false
        if kill -0 "$new_pid" 2>/dev/null; then
            echo "$new_pid" > "$gcli_pid_file"
            is_success=true
        elif grep -q "PM2" "$gcli_log_file" || grep -q "online" "$gcli_log_file" || grep -q "Done" "$gcli_log_file"; then
            echo "PM2_WEB" > "$gcli_pid_file"
            is_success=true
        fi

        cd "$original_dir"

        if [ "$is_success" = true ]; then
            if [ "$should_return_main" = true ]; then return $return_success_code; else return 0; fi
        else
            echo "❌ 启动失败！进程已退出且未检测到PM2成功标志。"
            echo "--- 日志最后 10 行 ---"
            tail -n 10 "$gcli_log_file"
            echo "---------------------"
            rm -f "$gcli_pid_file"
            return 1
        fi
    else
        echo "❌ 未找到 gcli2api 文件夹，请确认是否已安装。"
        return 1
    fi
}

stop_gcli_proxy() {
    echo "正在停止 gcli2api 服务..."
    if [ -f "$gcli_pid_file" ]; then
        local pid_content=$(cat "$gcli_pid_file")
        if [ "$pid_content" == "PM2_WEB" ]; then
            if command -v pm2 >/dev/null; then
                echo "检测到 PM2 进程，正在执行 pm2 delete web..."
                pm2 delete web >/dev/null 2>&1
                pm2 kill >/dev/null 2>&1
            else
                echo "警告：未找到 pm2 命令，无法优雅停止。"
            fi
        else
            kill "$pid_content" 2>/dev/null
        fi
        rm -f "$gcli_pid_file"
    fi
    pkill -f "bash termux-start.sh" >/dev/null 2>&1
    echo "✅ Gcli2api服务已停止。"
}

start_build_proxy_bg() {
    if [ -f "dark-server.js" ]; then
        echo "正在后台启动 Build (dark-server)..."
        nohup node dark-server.js > /dev/null 2>&1 &
        local new_pid=$!
        echo "$new_pid" > "$build_pid_file"
        echo "✅ Build反代已后台启动 (PID: $new_pid)"
        sleep 1
        return 0
    else
        echo "❌ 当前目录下未找到 dark-server.js，无法启动。"
        return 1
    fi
}

silent_start_gcli_bg() {
    if check_gcli_status; then return 0; fi

    if [ -d "$HOME/gcli2api" ]; then
        cd "$HOME/gcli2api" || return 1
        pkill -f "bash termux-start.sh" >/dev/null 2>&1
        if command -v pm2 >/dev/null; then pm2 delete web >/dev/null 2>&1; fi
        sleep 0.5
        
        : > "$gcli_log_file"
        nohup bash termux-start.sh < /dev/null > "$gcli_log_file" 2>&1 &
        local new_pid=$!
        
        local check_count=0
        local max_checks=60
        local detected_port=false
        
        while [ $check_count -lt $max_checks ]; do
            sleep 1
            if curl -s --connect-timeout 1 http://127.0.0.1:7861/ >/dev/null; then
                detected_port=true
                break
            fi
            check_count=$((check_count + 1))
        done
        
        if [ "$detected_port" = false ]; then
            echo "FAIL_GCLI" > "$notify_file"
            rm -f "$gcli_pid_file"
            return 1
        else
            if kill -0 "$new_pid" 2>/dev/null; then
                echo "$new_pid" > "$gcli_pid_file"
            elif grep -q "PM2" "$gcli_log_file" || grep -q "online" "$gcli_log_file" || grep -q "Done" "$gcli_log_file"; then
                echo "PM2_WEB" > "$gcli_pid_file"
            fi
            echo "SUCCESS_GCLI" > "$notify_file"
            return 0
        fi
    else
        echo "FAIL_GCLI" > "$notify_file"
        return 1
    fi
}

process_silent_start() {
    if [ "$enable_silent_start" == "true" ] && [ "$silent_start_service" != "none" ]; then
        rm -f "$notify_file"
        case "$silent_start_service" in
            "gcli") silent_start_gcli_bg & ;;
        esac
    fi
}

monitor_gcli_silent() {
    # ==========================================================
    # [连接测试功能] 
    # 此处用于监控无感启动下的 gcli2api 状态。
    # 如果之后 gcli2api 的连接测试网址变更，请修改下方的 target_url 变量
    # ==========================================================
    local target_url="http://127.0.0.1:7861/"
    
    while true; do
        sleep 60
        if curl -s --connect-timeout 2 "$target_url" >/dev/null; then
            echo -e "\033[0;32m✓✓✓\033[0m"
        else
            echo -e "\033[0;31m×××\033[0m"
            # 尝试在后台重新唤起
            silent_start_gcli_bg &
        fi
    done
}

console_keepalive() {
    # ==========================================================
    # [终端保活功能]
    # 每隔 30 秒输出一个暗色字符，防止 Termux 前台长时间无输出被系统休眠清理
    # ==========================================================
    while true; do
        sleep 30
        echo -ne "\033[1;30m❃\033[0m"
    done
}

process_linked_start() {
    if [ "$enable_linked_start" == "true" ] && [ "$linked_proxy_service" != "none" ]; then
        echo "🔗 正在关联启动服务: $linked_proxy_service ..."
        local start_result=0
        case "$linked_proxy_service" in
            "gcli") start_gcli_proxy "linked"; start_result=$? ;;
            "build") start_build_proxy_bg; start_result=$? ;;
        esac

        if [ $start_result -ne 0 ]; then
            err "⚠️ 关联服务启动失败或超时！按任意键将继续尝试启动 SillyTavern (可能无法连接)..."
        else
            echo "⏳ 端口检测通过，等待 2 秒..."
            sleep 2
        fi
        echo "-----------------------------------------"
    fi
}

# ===================================================================================
# --- [动态加载独立模块] ---
# ===================================================================================
if [ -f "$update_script" ]; then source "$update_script"; else update_submenu() { clear; draw_top_header; err "未找到安装模块: $update_script"; }; fi
if [ -f "$proxy_script" ]; then source "$proxy_script"; else proxy_service_submenu() { clear; draw_top_header; err "未找到代理模块: $proxy_script"; }; fi
if [ -f "$addons_script" ]; then source "$addons_script"; else additional_features_submenu() { clear; draw_top_header; err "未找到附加模块: $addons_script"; }; fi

# ===================================================================================
# --- [区块] 脚本主程序入口 ---
# ===================================================================================
load_config
process_silent_start

while true; do
    st_is_running=false
    if [ -f "$st_pid_file" ] && kill -0 "$(cat "$st_pid_file")" 2>/dev/null; then st_is_running=true; fi
    gcli_is_running=false
    if check_gcli_status; then gcli_is_running=true; fi

    clear
    draw_top_header
    
    keepalive_status_text="(带唤醒锁)"
    if [ "$enable_notification_keepalive" = true ]; then keepalive_status_text="(唤醒锁+通知)"; fi
    
    echo "========================================="
    echo "        欢迎使用 Termux 启动脚本         "
    echo "========================================="
    echo
    echo "   [1] 🟢 启动 SillyTavern (仅本机)"
    echo
    echo "   [2] 🛎️  代理服务"
    echo
    echo "   [3] 🔄 (首次)安装 / 检查更新 SillyTavern"
    echo
    echo "   [4] 🛠️  附加功能"
    echo
    echo "   [5] 🟢 启动 SillyTavern (局域网)"
    echo
    echo "   [0] ❌ 退出到 Termux 命令行"
    echo "========================================="
    
    choice=""
    
    if [ "$st_is_running" = true ]; then
        prompt_with_poll "请按键选择 [1-5, 0]: " choice
    else
        if [ "$enable_menu_timeout" = true ]; then
            prompt_text="请按键选择 [1-5, 0] "
            final_text="秒后自动选1): "
            for i in $(seq $menu_timeout -1 1); do
                printf "\r\033[K%s(%2d%s" "$prompt_text" "$i" "$final_text"
                read -n 1 -t 1 choice
                ret_code=$?
                poll_status
                if [ $ret_code -eq 0 ] && [ -n "$choice" ]; then echo; break; fi
            done
            if [ -z "$choice" ]; then
                printf "\r\033[K"
                choice=1
            fi
        else
            prompt_with_poll "请按键选择 [1-5, 0]: " choice
        fi
    fi
    
    case "$choice" in
        1)
            if [ "$st_is_running" = true ]; then err "SillyTavern 已在运行中！"; continue; fi
            if [ ! -f "$sillytavern_dir/server.js" ]; then err "SillyTavern 尚未安装，请用选项[3]安装。"; continue; fi
            
            process_linked_start

            echo "选择 [1]，正在启动 SillyTavern..."
            if command -v termux-wake-lock >/dev/null; then termux-wake-lock; fi
            if [ "$enable_notification_keepalive" = true ]; then
                if command -v termux-notification >/dev/null; then
                    termux-notification --id 1001 --title "SillyTavern 正在运行" --content "服务已启动" --ongoing
                fi
            fi
            sleep 1
            
            (cd "$sillytavern_dir" && node server.js) &
            st_pid=$!
            echo "$st_pid" > "$st_pid_file"
            echo
            echo ">> SillyTavern 启动成功 (PID: $st_pid)"
            echo "--------------------------------------------------------"
            
            if [ "$enable_silent_start" == "true" ] && [ "$silent_start_service" == "gcli" ]; then
                monitor_gcli_silent &
                monitor_pid=$!
            fi
            
            # 开启控制台防清理保活输出
            console_keepalive &
            keepalive_pid=$!

            wait "$st_pid"
            if [ -n "$monitor_pid" ]; then kill "$monitor_pid" 2>/dev/null; fi
            if [ -n "$keepalive_pid" ]; then kill "$keepalive_pid" 2>/dev/null; fi
            break
            ;;
        2)
            proxy_service_submenu
            ;;
        3)
            update_submenu
            ;;
        4)
            additional_features_submenu
            ;;
        5)
            if [ "$st_is_running" = true ]; then err "SillyTavern 已在运行中！"; continue; fi
            if [ ! -f "$sillytavern_dir/server.js" ]; then err "SillyTavern 尚未安装，请用选项[3]安装。"; continue; fi
            
            process_linked_start

            echo "选择 [5]，正在启动 SillyTavern (局域网)..."
            if command -v termux-wake-lock >/dev/null; then termux-wake-lock; fi
            if [ "$enable_notification_keepalive" = true ]; then
                if command -v termux-notification >/dev/null; then
                    termux-notification --id 1001 --title "SillyTavern 正在运行 (局域网)" --content "服务已启动" --ongoing
                fi
            fi
            sleep 1
            
            (cd "$sillytavern_dir" && node server.js --listen) &
            st_pid=$!
            echo "$st_pid" > "$st_pid_file"
            echo
            echo ">> SillyTavern 局域网模式启动成功 (PID: $st_pid)"
            echo "--------------------------------------------------------"
            
            if [ "$enable_silent_start" == "true" ] && [ "$silent_start_service" == "gcli" ]; then
                monitor_gcli_silent &
                monitor_pid=$!
            fi
            
            # 开启控制台防清理保活输出
            console_keepalive &
            keepalive_pid=$!

            wait "$st_pid"
            if [ -n "$monitor_pid" ]; then kill "$monitor_pid" 2>/dev/null; fi
            if [ -n "$keepalive_pid" ]; then kill "$keepalive_pid" 2>/dev/null; fi
            break
            ;;
        0)
            echo "选择 [0]，已退回到 Termux 命令行。"
            pkill -f "termux-wake-lock" &> /dev/null
            break
            ;;
        *)
            err "输入错误！请重新选择。"
            ;;
    esac
done