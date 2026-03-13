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

# 全局状态变量初始化
st_is_running=false
gcli_is_running=false

# --- [区块] 配置管理 ---
load_config() {
    # 默认值
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

    # 利用 ANSI 瞬间覆写前 4 行而不影响下方输入
    local header="\033[s\033[1;1H=========================================\n 📊 全局服务运行状态\n ST: $st_status  |  Gcli: $gcli_status\033[K\n=========================================\033[u"
    printf "%b" "$header"
}

poll_status() {
    local need_redraw=false
    
    # 检测 ST 存活
    if [ "$st_is_running" = true ]; then
        if ! kill -0 "$(cat "$st_pid_file" 2>/dev/null)" 2>/dev/null; then
            st_is_running=false
            need_redraw=true
        fi
    fi

    # 检测后台无感启动通知
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

# 菜单通用非阻塞读取输入函数 (已修复变量作用域丢失的Bug)
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
            # 安全地将结果赋值给外部变量
            printf -v "$var_name" "%s" "$_p_choice"
            echo
            break
        fi
    done
}


# --- [区块] .bashrc 管理函数 ---
update_bashrc() {
    local action=$1
    local alias_name=$2
    local bashrc_file="$HOME/.bashrc"
    local function_name="run_st_launcher"
    touch "$bashrc_file"
    sed -i "\|$BASHRC_START_TAG|,\|$BASHRC_END_TAG|d" "$bashrc_file"
    sed -i -e 's|^#\s*cp ~/START-ST-Termux/start-ST-termux.sh ~/||g' -e 's|^cp ~/START-ST-Termux/start-ST-termux.sh ~/||g' -e 's|^#\s*chmod +x ~/start-ST-termux.sh||g' -e 's|^chmod +x ~/start-ST-termux.sh||g' -e 's|^#\s*~/start-ST-termux.sh||g' -e 's|^~/start-ST-termux.sh||g' "$bashrc_file"
    sed -i '/^[[:space:]]*$/d' "$bashrc_file"
    if [ -s "$bashrc_file" ] && [ -n "$(tail -c1 "$bashrc_file")" ]; then echo "" >> "$bashrc_file"; fi
    if [ "$action" == "disable_password" ]; then
        cat <<'EOF' >> "$bashrc_file"

cp ~/START-ST-Termux/start-ST-termux.sh ~/

chmod +x ~/start-ST-termux.sh
~/start-ST-termux.sh

EOF
    else 
        {
        echo "$BASHRC_START_TAG"
        cat <<'FUNC_EOF'
run_st_launcher() {
    cp ~/START-ST-Termux/start-ST-termux.sh ~/ &>/dev/null
    chmod +x ~/start-ST-termux.sh
    ~/start-ST-termux.sh
}
FUNC_EOF
        echo "alias $alias_name='$function_name'"
        echo "$BASHRC_END_TAG"
        } >> "$bashrc_file"
    fi
}

# ===================================================================================
# --- [区块] 服务管理函数 (Gcli / Build) ---
# ===================================================================================

# 1. Gcli2api 代理
start_gcli_proxy() {
    local mode=$1 
    
    if check_gcli_status; then
        echo "✅ Gcli2api服务已在运行，跳过启动。"
        return 0
    fi

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
                kill "$tail_pid" 2>/dev/null
                wait "$tail_pid" 2>/dev/null
                echo -e "\n已手动退出日志查看。"
                break
            fi
            
            if curl -s --connect-timeout 1 http://127.0.0.1:7861/ >/dev/null; then
                kill "$tail_pid" 2>/dev/null
                wait "$tail_pid" 2>/dev/null
                echo -e "\n\033[1;32mgcli2api代理成功启动，正在运行中\033[0m"
                detected_port=true
                
                if [ $success_sleep_time -gt 0 ]; then
                    sleep $success_sleep_time
                fi
                
                if [ "$mode" == "verbose" ]; then
                    should_return_main=true
                fi
                break 
            fi
            check_count=$((check_count + 1))
        done
        
        kill "$tail_pid" 2>/dev/null
        wait "$tail_pid" 2>/dev/null
        
        if [ "$detected_port" = false ]; then
            if [ $check_count -ge $max_checks ]; then
                echo -e "\n\033[1;31mgcli2api代理启动过程中可能遇到问题(或超时)，请查看详细日志\033[0m"
            fi
            if [ "$mode" == "linked" ]; then
                echo "❌ [关联启动] 端口检测超时，终止后续操作。"
                if command -v pm2 >/dev/null; then pm2 delete web >/dev/null 2>&1; fi
                kill "$new_pid" 2>/dev/null
                rm -f "$gcli_pid_file"
                cd "$original_dir"
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
            if [ "$should_return_main" = true ]; then
                return $return_success_code
            else
                return 0
            fi
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

# 2. Build (Dark Server) 代理
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

# --- 无感启动专用后台启动函数 ---
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

process_linked_start() {
    if [ "$enable_linked_start" == "true" ] && [ "$linked_proxy_service" != "none" ]; then
        echo "🔗 正在关联启动服务: $linked_proxy_service ..."
        local start_result=0
        
        case "$linked_proxy_service" in
            "gcli")
                start_gcli_proxy "linked"
                start_result=$?
                ;;
            "build")
                start_build_proxy_bg
                start_result=$?
                ;;
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


# --- [区块] 安装更新、子菜单功能 ---
use_proxy() { local country; country=$(curl -s --connect-timeout 5 ipinfo.io/country 2>/dev/null); if [[ "$country" == "CN" ]]; then read -rp "检测到大陆IP，是否使用代理加速 (Y/n)? " yn; [[ "$yn" =~ ^[Nn]$ ]] && return 1 || return 0; fi; return 1; }
get_st_local_ver() { command -v jq >/dev/null && [ -f "$sillytavern_dir/package.json" ] && jq -r .version "$sillytavern_dir/package.json" || echo "未知"; }
get_st_latest_ver() { command -v jq >/dev/null && curl -s --connect-timeout 5 "https://api.github.com/repos/SillyTavern/SillyTavern/releases/latest" | jq -r .tag_name || echo "获取失败"; }

update_st_incremental() {
    if [ ! -d "$sillytavern_dir/.git" ]; then err "错误：找不到 .git 目录，无法增量更新。"; return 1; fi
    echo "正在创建当前版本的备份..."; rm -rf "$sillytavern_old_dir"; cp -r "$sillytavern_dir" "$sillytavern_old_dir" || { err "创建备份失败！"; return 1; }
    echo "正在重置本地仓库..."; (cd "$sillytavern_dir" && git reset --hard origin/release) || { err "Git 重置失败！"; return 1; }
    echo "正在执行增量更新..."; (cd "$sillytavern_dir" && git pull) || { err "Git 更新失败！"; return 1; }
    echo "正在更新 npm 依赖..."; (cd "$sillytavern_dir" && npm install) || { err "npm 依赖安装失败！"; return 1; }
    echo "✅ 增量更新完成！"
}

install_st_fresh() {
    local repo_url="https://github.com/SillyTavern/SillyTavern"; if use_proxy; then repo_url="$proxy_url/$repo_url"; fi; local temp_new_dir="$HOME/SillyTavern_new"; echo "正在克隆全新的 SillyTavern 到临时目录..."; rm -rf "$temp_new_dir"; git clone --depth 1 --branch release "$repo_url" "$temp_new_dir" || { err "Git 克隆失败！"; rm -rf "$temp_new_dir"; return 1; }; echo "正在安装 npm 依赖..."; (cd "$temp_new_dir" && npm install) || { err "npm 依赖安装失败！"; rm -rf "$temp_new_dir"; return 1; }; if [ -d "$sillytavern_dir" ]; then echo "正在迁移用户数据..."; if [ -d "$sillytavern_dir/data/default-user" ]; then cp -r "$sillytavern_dir/data/default-user/characters/." "$temp_new_dir/public/characters/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/chats/." "$temp_new_dir/public/chats/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/worlds/." "$temp_new_dir/public/worlds/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/groups/." "$temp_new_dir/public/groups/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/group chats/." "$temp_new_dir/public/group chats/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/OpenAI Settings/." "$temp_new_dir/public/OpenAI Settings/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/User Avatars/." "$temp_new_dir/public/User Avatars/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/backgrounds/." "$temp_new_dir/public/backgrounds/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/settings.json" "$temp_new_dir/public/settings.json" 2>/dev/null; else cp -r "$sillytavern_dir/public/characters/." "$temp_new_dir/public/characters/" 2>/dev/null; cp -r "$sillytavern_dir/public/chats/." "$temp_new_dir/public/chats/" 2>/dev/null; cp -r "$sillytavern_dir/public/worlds/." "$temp_new_dir/public/worlds/" 2>/dev/null; cp -r "$sillytavern_dir/public/groups/." "$temp_new_dir/public/groups/" 2>/dev/null; cp -r "$sillytavern_dir/public/group chats/." "$temp_new_dir/public/group chats/" 2>/dev/null; cp -r "$sillytavern_dir/public/OpenAI Settings/." "$temp_new_dir/public/OpenAI Settings/" 2>/dev/null; cp -r "$sillytavern_dir/public/User Avatars/." "$temp_new_dir/public/User Avatars/" 2>/dev/null; cp -r "$sillytavern_dir/public/backgrounds/." "$temp_new_dir/public/backgrounds/" 2>/dev/null; cp -r "$sillytavern_dir/public/settings.json" "$temp_new_dir/public/settings.json" 2>/dev/null; fi; echo "✅ 数据迁移完成。正在备份旧版本程序文件到 $sillytavern_old_dir..."; rm -rf "$sillytavern_old_dir"; mv "$sillytavern_dir" "$sillytavern_old_dir"; fi; mv "$temp_new_dir" "$sillytavern_dir"; echo "✅ 全新安装/更新完成！";
}

version_rollback() {
    if [ ! -d "$sillytavern_old_dir" ]; then err "错误：未找到可用于回退的旧版本。"; return; fi; read -n 1 -p "警告：这将用旧版本覆盖当前版本，是否确认 (y/n)? " confirm; echo; if [ "$confirm" != "y" ]; then echo "已取消。"; sleep 1; return; fi; echo "正在回退版本..."; mv "$sillytavern_dir" "$HOME/SillyTavern_temp"; mv "$sillytavern_old_dir" "$sillytavern_dir"; mv "$HOME/SillyTavern_temp" "$sillytavern_old_dir"; echo "✅ 版本回退成功！"; sleep 2;
}

update_submenu() { 
    while true; do 
        clear
        draw_top_header
        echo "========================================="
        echo "         SillyTavern 安装与更新          "
        echo "========================================="
        local_ver=$(get_st_local_ver)
        latest_ver=$(get_st_latest_ver)
        echo
        echo "  当前版本: $local_ver"
        echo "  最新版本: $latest_ver"
        echo "-----------------------------------------"
        echo
        echo "   [1] 增量更新 (推荐，速度快)"
        echo
        echo "   [2] 全新更新 (强制覆盖，并保留数据)"
        echo
        echo "   [3] 版本回退 (恢复到上一个版本)"
        echo
        echo "   [0] 返回主菜单"
        echo
        echo "========================================="
        
        prompt_with_poll "请按键选择: " choice
        
        case "$choice" in 
            1) clear; update_st_incremental; echo; read -n 1 -p "操作完成！按任意键返回...";; 
            2) read -n 1 -p "警告：这将重新下载并覆盖程序文件，是否确认 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then clear; install_st_fresh; echo; read -n 1 -p "操作完成！按任意键返回..."; fi;; 
            3) clear; version_rollback;; 
            0) break;; 
            *) err "无效选择...";; 
        esac
    done 
}

# --- [区块] 其他子菜单 ---

silent_start_submenu() {
    while true; do
        clear
        draw_top_header
        local status_text="关闭"
        if [ "$enable_silent_start" == "true" ]; then status_text="开启"; fi
        
        local current_selection_text="无"
        case "$silent_start_service" in
            "gcli") current_selection_text="gcli2api代理";;
        esac

        echo "========================================="
        echo "            👻 无感启动设置            "
        echo "========================================="
        echo
        echo "  开启后，脚本启动时将在后台自动运行指定项目。"
        echo
        echo "  当前状态: $status_text"
        echo "========================================="
        echo "   [1] 选择无感启动项目 (当前已选: $current_selection_text)"
        echo "   [2] 关闭无感启动"
        echo "   [0] 返回上级目录"
        echo "========================================="
        
        prompt_with_poll "请按键选择: " choice

        case "$choice" in
            1)
                clear
                echo "请选择要无感启动的服务 (单选):"
                echo " [1] gcli2api代理"
                echo " [2] (等待后续加入)"
                echo " [0] 取消"
                read -n 1 -p "选择: " sel
                case "$sel" in
                    1) 
                        if [ "$linked_proxy_service" == "gcli" ] && [ "$enable_linked_start" == "true" ]; then
                            echo
                            echo "⚠️ 冲突检测: [gcli2api代理] 已在 关联启动 中开启。"
                            echo " 1. 关闭关联启动并开启无感启动"
                            echo " 2. 关闭无感启动并开启关联启动"
                            echo " 3. 返回上一步"
                            read -n 1 -p "请选择: " conflict_choice
                            case "$conflict_choice" in
                                1)
                                    enable_linked_start="false"
                                    linked_proxy_service="none"
                                    silent_start_service="gcli"
                                    enable_silent_start="true"
                                    save_config
                                    echo; echo "✅ 已选择: gcli2api代理 (无感启动开启，已自动关闭关联启动)"
                                    sleep 2
                                    ;;
                                2)
                                    enable_silent_start="false"
                                    silent_start_service="none"
                                    save_config
                                    echo; echo "✅ 保持关联启动 (已关闭无感启动)"
                                    sleep 1.5
                                    ;;
                                3|*)
                                    echo; echo "已返回"
                                    sleep 0.5
                                    ;;
                            esac
                        else
                            silent_start_service="gcli"; enable_silent_start="true"; save_config; echo; echo "✅ 已选择: gcli2api代理"; sleep 1;
                        fi
                        ;;
                    2) echo; echo "敬请期待"; sleep 1;;
                    0) echo; echo "取消"; sleep 0.5;;
                    *) echo; echo "无效选择"; sleep 0.5;;
                esac
                ;;
            2)
                enable_silent_start="false"
                silent_start_service="none"
                save_config
                echo "✅ 已关闭无感启动。"
                sleep 1
                ;;
            0)
                break
                ;;
            *)
                echo "无效输入"
                sleep 0.5
                ;;
        esac
    done
}

linked_start_submenu() {
    while true; do
        clear
        draw_top_header
        local status_text="关闭"
        if [ "$enable_linked_start" == "true" ]; then status_text="开启"; fi
        
        local current_selection_text="无"
        case "$linked_proxy_service" in
            "build") current_selection_text="Build反代";;
            "gcli") current_selection_text="Gcli2api代理";;
        esac

        echo "========================================="
        echo "            🔗 关联启动设置            "
        echo "========================================="
        echo
        echo "  当此功能开启时，启动 SillyTavern 会"
        echo "  自动启动你选择的关联服务。"
        echo
        echo "  当前状态: $status_text"
        echo "========================================="
        echo "   [1] 选择关联项目 (当前已选: $current_selection_text)"
        echo "   [2] 关闭关联启动"
        echo "   [0] 返回上级目录"
        echo "========================================="
        
        prompt_with_poll "请按键选择: " choice

        case "$choice" in
            1)
                clear
                echo "请选择要关联启动的服务 (单选):"
                echo " [1] Build反代 (dark-server)"
                echo " [2] Gcli2api代理"
                echo " [0] 取消"
                read -n 1 -p "选择: " sel
                case "$sel" in
                    1) linked_proxy_service="build"; enable_linked_start="true"; save_config; echo; echo "✅ 已关联: Build反代"; sleep 1;;
                    2) 
                        if [ "$silent_start_service" == "gcli" ] && [ "$enable_silent_start" == "true" ]; then
                            echo
                            echo "⚠️ 冲突检测: [gcli2api代理] 已在 无感启动 中开启。"
                            echo " 1. 关闭关联启动并开启无感启动"
                            echo " 2. 关闭无感启动并开启关联启动"
                            echo " 3. 返回上一步"
                            read -n 1 -p "请选择: " conflict_choice
                            case "$conflict_choice" in
                                1)
                                    enable_linked_start="false"
                                    linked_proxy_service="none"
                                    save_config
                                    echo; echo "✅ 保持无感启动 (已关闭关联启动)"
                                    sleep 1.5
                                    ;;
                                2)
                                    enable_silent_start="false"
                                    silent_start_service="none"
                                    linked_proxy_service="gcli"
                                    enable_linked_start="true"
                                    save_config
                                    echo; echo "✅ 已关联: gcli2api代理 (关联启动开启，已自动关闭无感启动)"
                                    sleep 2
                                    ;;
                                3|*)
                                    echo; echo "已返回"
                                    sleep 0.5
                                    ;;
                            esac
                        else
                            linked_proxy_service="gcli"; enable_linked_start="true"; save_config; echo; echo "✅ 已关联: Gcli2api代理"; sleep 1;
                        fi
                        ;;
                    0) echo; echo "取消"; sleep 0.5;;
                    *) echo; echo "无效选择"; sleep 0.5;;
                esac
                ;;
            2)
                enable_linked_start="false"
                linked_proxy_service="none"
                save_config
                echo "✅ 已关闭关联启动。"
                sleep 1
                ;;
            0)
                break
                ;;
            *)
                echo "无效输入"
                sleep 0.5
                ;;
        esac
    done
}

toggle_password_start_submenu() {
    clear
    draw_top_header
    echo "========================================="
    echo "         🔐 命令行密码启动设置         "
    echo "========================================="
    echo
    echo "  此功能通过设置一个命令行'密码'(别名)来"
    echo "  启动本脚本，以实现隐藏效果。"
    echo "  开启后，Termux启动时将不再显示菜单。"
    
    if [ "$enable_password_start" = true ]; then
        local current_alias; if [ -f "$password_alias_file" ]; then current_alias=$(cat "$password_alias_file"); fi
        echo "  当前状态: 开启 (启动密码: $current_alias)"
        echo "========================================="
        echo "   [1] ✏️  修改启动密码"
        echo "   [2] ❌ 关闭密码启动 (恢复自动运行)"
        echo "   [0] ↩️  返回"
        echo "========================================="
        prompt_with_poll "请选择操作: " choice
        case "$choice" in
            1)
                local new_alias
                read -p "请输入新的启动密码 (仅限字母和数字): " new_alias
                if [[ ! "$new_alias" =~ ^[a-zA-Z0-9]+$ ]]; then err "密码格式错误！只能包含字母和数字。"; return; fi
                update_bashrc "enable_password" "$new_alias"
                echo -n "$new_alias" > "$password_alias_file"
                echo "✅ 启动密码已修改为 '$new_alias'。"; echo "请重启Termux使新密码生效。"; sleep 3
                ;;
            2) 
                enable_password_start="false"; save_config
                update_bashrc "disable_password"
                rm -f "$password_alias_file"
                echo "✅ 密码启动功能已关闭，已恢复原始自启动方式。"; echo "下次启动Termux将直接显示菜单。"; sleep 3
                ;;
            0) return;;
            *) err "无效选择...";;
        esac
    else
        echo "  当前状态: 关闭 (Termux启动时自动运行)"
        echo "========================================="
        read -n 1 -p "是否要 开启 密码启动功能 (y/n)? " confirm; echo
        if [ "$confirm" == "y" ]; then
            local new_alias
            read -p "请输入启动密码 (仅限字母和数字): " new_alias
            if [[ ! "$new_alias" =~ ^[a-zA-Z0-9]+$ ]]; then err "密码格式错误！只能包含字母和数字。"; return; fi
            enable_password_start="true"; save_config
            update_bashrc "enable_password" "$new_alias"
            echo -n "$new_alias" > "$password_alias_file"
            echo "✅ 密码启动功能已开启，密码为 '$new_alias'。"; echo "请重启Termux以使功能生效。"; sleep 3
        else
            echo "操作已取消。"; sleep 1
        fi
    fi
}
toggle_menu_timeout_submenu() {
    clear
    draw_top_header
    echo "========================================="
    echo "            主菜单倒计时设置             "
    echo "========================================="
    echo
    echo "  此功能用于开启或关闭主菜单在未启动"
    echo "  SillyTavern 时的10秒自动选择功能。"
    echo "  当前状态: $enable_menu_timeout"
    echo "========================================="
    read -p "请输入 'true' (开启) 或 'false' (关闭): " new_status
    if [ "$new_status" == "true" ] || [ "$new_status" == "false" ]; then
        enable_menu_timeout="$new_status"; save_config
        echo "✅ 设置已更新为 [$new_status] 并已保存。"
    else
        echo "无效输入，设置未改变。"
    fi
    sleep 2
}
package_manager_submenu() { 
    local pkg_name=$1; local cmd_to_check=$2; local is_core=$3; 
    while true; do 
        clear
        draw_top_header
        echo "========================================="
        echo "         软件包管理: $pkg_name           "
        echo "========================================="
        echo
        if [ "$is_core" = true ]; then echo "   [ ⚠️ 必要 ] 此软件包是运行的核心依赖。"; else echo "   [ ✨ 可选 ] 此软件包提供额外功能。"; fi
        echo
        echo "   [1] 安装此软件包 (命令行)"
        echo
        echo "   [2] 卸载此软件包 (命令行)"
        echo
        if [ "$pkg_name" == "termux-api" ]; then echo "   [D] 在浏览器中打开配套APP下载页面"; echo; fi
        echo "   [0] 返回上一级"
        echo
        echo "========================================="
        prompt_with_poll "请按键选择: " action_choice
        case "$action_choice" in 
            1) if command -v "$cmd_to_check" >/dev/null; then echo "✅ 软件包 $pkg_name 似乎已经安装。"; sleep 2; else read -n 1 -p "准备安装 $pkg_name ，是否确认 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then pkg install "$pkg_name" -y; echo "安装完成！"; sleep 2; else echo "已取消安装。"; sleep 1; fi; fi;; 
            2) if ! command -v "$cmd_to_check" >/dev/null; then echo "ℹ️ 软件包 $pkg_name 尚未安装。"; sleep 2; else if [ "$is_core" = true ]; then echo "警告：这是一个核心软件包，卸载可能导致程序无法运行！"; fi; read -n 1 -p "准备卸载 $pkg_name ，是否确认 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then pkg uninstall "$pkg_name" -y; echo "卸载完成！"; sleep 2; else echo "已取消卸载。"; sleep 1; fi; fi;; 
            "d"|"D") if [ "$pkg_name" == "termux-api" ]; then if command -v termux-open-url >/dev/null; then echo "正在浏览器中打开下载页面..."; termux-open-url "$termux_api_apk_url"; sleep 2; else echo "错误: termux-open-url 命令不可用！请先安装 termux-api 命令行包。"; sleep 3; fi; else echo "无效选择..."; sleep 1; fi;; 
            0) break;; 
            *) echo "无效选择..."; sleep 1;; 
        esac; 
    done; 
}
package_selection_submenu() { 
    while true; do 
        clear
        draw_top_header
        echo "========================================="
        echo "            必要软件包管理               "
        echo "========================================="
        echo
        echo "   [1] git (版本控制)       - ⚠️ 必要"
        echo
        echo "   [2] curl (网络下载)      - ⚠️ 必要"
        echo
        echo "   [3] nodejs-lts (运行环境) - ⚠️ 必要"
        echo
        echo "   [4] jq (版本显示)        - ✨ 可选"
        echo
        echo "   [5] termux-api (后台保活)  - ✨ 可选"
        echo
        echo "   [0] 返回主菜单"
        echo
        echo "========================================="
        prompt_with_poll "请按键选择要管理的软件包 [1-5, 0]: " pkg_choice
        case "$pkg_choice" in 
            1) package_manager_submenu "git" "git" true;; 
            2) package_manager_submenu "curl" "curl" true;; 
            3) package_manager_submenu "nodejs-lts" "node" true;; 
            4) package_manager_submenu "jq" "jq" false;; 
            5) package_manager_submenu "termux-api" "termux-wake-lock" false;; 
            0) break;; 
            *) echo "无效选择..."; sleep 1; continue;; 
        esac; 
    done; 
}
termux_setup() { 
    clear
    draw_top_header
    echo "========================================="
    echo "        欢迎使用 Termux 环境初始化         "
    echo "========================================="
    echo
    echo "本向导将为您更新系统并安装所有核心依赖。"
    echo "这是一个一次性操作，可以确保脚本稳定运行。"
    echo
    read -n 1 -p "是否立即开始 (y/n)? " confirm
    echo
    if [ "$confirm" == "y" ]; then 
        echo
        echo "--- [步骤 1/2] 正在更新 Termux 基础包 ---"
        yes | pkg upgrade
        echo "--- [步骤 2/2] 正在安装核心软件包 ---"
        apt update && apt install git curl nodejs-lts -y
        echo "✅ 环境初始化完成！"
        sleep 2
    else 
        echo
        echo "已取消初始化。"
        sleep 2
    fi
}
toggle_notification_submenu() { 
    clear
    draw_top_header
    echo "========================================="
    echo "            通知保活功能设置             "
    echo "========================================="
    echo
    echo "  此功能通过创建一个常驻通知来增强后台保活。"
    echo "  当前状态: $enable_notification_keepalive"
    echo
    echo "========================================="
    read -p "请输入 'true' 或 'false' 来修改设置: " new_status
    if [ "$new_status" == "true" ] || [ "$new_status" == "false" ]; then 
        enable_notification_keepalive="$new_status"
        save_config
        echo "✅ 设置已更新为 [$new_status] 并已保存。"
    else 
        echo "无效输入，设置未改变。"
    fi
    sleep 2
}
additional_features_submenu() { 
    while true; do 
        clear
        draw_top_header
        echo "========================================="
        echo "                附加功能                 "
        echo "========================================="
        echo
        echo "   [1] 📦 软件包管理"
        echo
        echo "   [2] 🚀 Termux 环境初始化"
        echo
        echo "   [3] 🔔 通知保活设置 (当前: $enable_notification_keepalive)"
        echo
        echo "   [4] 🔐 密码启动 (当前: $enable_password_start)"
        echo
        echo "   [5] ⏳ 开/关主菜单倒计时 (当前: $enable_menu_timeout)"
        echo
        echo "   [6] 🔗 关联启动 (当前: $enable_linked_start)"
        echo
        echo "   [7] 👻 无感启动 (当前: $enable_silent_start)"
        echo
        echo "   [0] ↩️  返回主菜单"
        echo
        echo "========================================="
        prompt_with_poll "请按键选择 [1-7, 0]: " sub_choice
        case "$sub_choice" in 
            1) package_selection_submenu;; 
            2) termux_setup;; 
            3) toggle_notification_submenu;; 
            4) toggle_password_start_submenu;; 
            5) toggle_menu_timeout_submenu;; 
            6) linked_start_submenu;; 
            7) silent_start_submenu;; 
            0) break;; 
            *) err "输入错误！请重新选择。";; 
        esac; 
    done; 
}

proxy_service_submenu() {
    while true; do
        local gcli_status_text=""
        if check_gcli_status; then 
            gcli_status_text="🛑 停止 gcli2api 反代"
        else 
            gcli_status_text="🟢 启动 gcli2api 反代"
        fi

        clear
        draw_top_header
        echo "========================================="
        echo "            🛎️  代理服务菜单            "
        echo "========================================="
        echo
        echo "   [1] 🟢 启动 build 反代 (前台调试)"
        echo
        echo -e "   [2] $gcli_status_text"
        echo
        echo "   [0] ↩️  返回主菜单"
        echo
        echo "========================================="
        
        prompt_with_poll "请按键选择 [1-2, 0]: " sub_choice
        
        case "$sub_choice" in
            1)
                clear
                echo "正在启动 build 反代..."
                echo "服务将在此处前台运行，按 Ctrl+C 停止并返回。"
                sleep 1
                if [ -f "dark-server.js" ]; then
                    node dark-server.js
                else
                     echo "❌ 当前目录下未找到 dark-server.js"
                fi
                echo
                read -n 1 -p "服务已停止。按任意键返回..."
                ;;
            2)
                clear
                if check_gcli_status; then
                    stop_gcli_proxy
                    read -n 1 -p "按任意键返回..."
                else
                    start_gcli_proxy "verbose"
                    if [ $? -eq 10 ]; then
                        break
                    elif [ $? -eq 0 ]; then
                        read -n 1 -p "按任意键返回..."
                    else
                         read -n 1 -p "启动遇到错误，请检查。按任意键返回..."
                    fi
                fi
                ;;
            0) break ;;
            *) err "输入错误！请重新选择。" ;;
        esac
    done
}


# ===================================================================================
# --- [区块] 脚本主程序入口 ---
# ===================================================================================
load_config

# 触发无感启动 (后台运行)
process_silent_start

while true; do
    # 每次回到底层主菜单前，强行校验一次双边状态
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
    
    # --- 主菜单输入时的非阻塞状态检测轮询 ---
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
            echo ">> 随时按任意键可返回主菜单 (SillyTavern将在后台继续运行)"
            echo "--------------------------------------------------------"
            
            # 隔离日志：暂停任何轮询刷新，全权交由ST接管屏幕，按下按键才会返回并刷新。
            read -n 1
            
            if ! kill -0 "$st_pid" 2>/dev/null; then cleanup; fi
            continue
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
            echo ">> 随时按任意键可返回主菜单 (SillyTavern将在后台继续运行)"
            echo "--------------------------------------------------------"
            
            read -n 1
            
            if ! kill -0 "$st_pid" 2>/dev/null; then cleanup; fi
            continue
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