#!/bin/bash

# ===================================================================================
# --- [可修改区块] 全局变量定义 ---
# ===================================================================================
sillytavern_dir="$HOME/SillyTavern"
sillytavern_old_dir="$HOME/SillyTavern_old"
llm_proxy_dir="$HOME/-gemini-"
st_pid_file="$HOME/.sillytavern_runner.pid"
llm_pid_file="$HOME/.llm-proxy/logs/llm-proxy.pid"
gcli_pid_file="$HOME/.gcli2api.pid"
build_pid_file="$HOME/.dark-server.pid"
llm_startup_log="$HOME/.llm-proxy/logs/startup.log"
# gcli2api 日志文件路径 (Termux 根目录)
gcli_log_file="$HOME/gcli2api_log.txt"
config_file="$HOME/.st_launcher_config"
password_alias_file="$HOME/.st_launcher_alias"
script_path=$(readlink -f "$0")
script_name=$(basename "$0")
BASHRC_START_TAG="# <<< START MANAGED BLOCK BY $script_name >>>"
BASHRC_END_TAG="# <<< END MANAGED BLOCK BY $script_name >>>"
proxy_url="https://ghfast.top"
install_script_url="https://raw.githubusercontent.com/rzline/st-cr-ins.sh/main/install.sh"
install_script_name="install.sh"
termux_api_apk_url="https://github.com/termux/termux-api/releases"
menu_timeout=10
enable_menu_timeout="true"

# --- [区块] 配置管理 ---
load_config() {
    # 默认值
    enable_notification_keepalive="true"
    enable_auto_start="true"
    enable_password_start="false"
    enable_menu_timeout="true"
    enable_linked_start="false"
    linked_proxy_service="none"

    if [ -f "$config_file" ]; then source "$config_file"; fi
    save_config
}
save_config() {
    echo "enable_notification_keepalive=$enable_notification_keepalive" > "$config_file"
    echo "enable_auto_start=$enable_auto_start" >> "$config_file"
    echo "enable_password_start=$enable_password_start" >> "$config_file"
    echo "enable_menu_timeout=$enable_menu_timeout" >> "$config_file"
    echo "enable_linked_start=$enable_linked_start" >> "$config_file"
    echo "linked_proxy_service=$linked_proxy_service" >> "$config_file"
}

# --- [区块] 通用工具函数 ---
err() { echo; echo "❌ 错误: $1" >&2; read -n 1 -p "按任意键继续..."; }
cleanup() {
    rm -f "$st_pid_file"
    if [ "$enable_notification_keepalive" = true ]; then
        command -v termux-notification-remove >/dev/null && termux-notification-remove 1001
    fi
}

# --- [重写] Gcli 状态检测专用函数 ---
# 修复：不再仅依赖文件存在，而是真实检测进程/PM2状态，并自动清理死文件
check_gcli_status() {
    if [ -f "$gcli_pid_file" ]; then
        local content=$(cat "$gcli_pid_file")
        
        # 情况1: PID文件内容是 "PM2_WEB"
        if [ "$content" == "PM2_WEB" ]; then
            # 必须检查 pm2 是否真的在运行该服务
            if command -v pm2 >/dev/null; then
                # 获取 web 服务的 PID (屏蔽错误输出，防止刷屏)
                local pm2_pid=$(pm2 pid web 2>/dev/null)
                
                # 检查1: pm2_pid 必须是数字
                # 检查2: kill -0 确认该 PID 的进程真实存在
                if [[ "$pm2_pid" =~ ^[0-9]+$ ]] && [ "$pm2_pid" -gt 0 ] && kill -0 "$pm2_pid" 2>/dev/null; then
                    return 0 # 真实存活
                fi
            fi
            # 如果代码走到这里，说明 PID 文件虽然在，但服务挂了 -> 视为未运行并清理
            rm -f "$gcli_pid_file"
            return 1

        # 情况2: PID文件内容是普通 PID 数字
        elif [ -n "$content" ]; then
            if kill -0 "$content" 2>/dev/null; then
                return 0
            else
                # 进程不存在 -> 清理死文件
                rm -f "$gcli_pid_file"
                return 1
            fi
        fi
    fi
    # 文件不存在
    return 1
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
# --- [区块] 服务管理函数 (LLM / Gcli / Build) ---
# ===================================================================================

# 1. LLM 代理
start_llm_proxy() {
    if [ -f "$llm_pid_file" ] && kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then
        echo "✅ LLM代理服务已在运行 (PID: $(cat "$llm_pid_file"))，跳过启动。"
        return 0
    fi

    local start_script_path="$llm_proxy_dir/dist/手机安卓一键脚本/666/start-termux.sh"
    echo "正在尝试启动 LLM 代理服务..."
    if [ ! -d "$llm_proxy_dir" ]; then err "LLM代理服务目录 '$llm_proxy_dir' 不存在！"; return 1; fi
    if [ ! -f "$start_script_path" ]; then err "启动脚本 '$start_script_path' 未找到！"; return 1; fi
    rm -f "$llm_pid_file"; > "$llm_startup_log"
    echo "在后台启动服务进程..."
    (cd "$(dirname "$start_script_path")" && chmod +x start-termux.sh && ./start-termux.sh start) > "$llm_startup_log" 2>&1 &
    
    echo -n "正在等待服务初始化 (最长20秒) "; local timeout=20
    while [ $timeout -gt 0 ]; do
        if [ -f "$llm_pid_file" ] && kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then
            echo; echo "✅ 服务成功启动！PID: $(cat "$llm_pid_file")。"; sleep 1; return 0
        fi
        echo -n "."; sleep 1; timeout=$((timeout - 1))
    done
    err "LLM服务未能成功启动，请检查日志。"; return 1
}

stop_llm_proxy() {
    echo "正在停止 LLM 代理服务..."
    if [ -f "$llm_pid_file" ]; then
        local pid=$(cat "$llm_pid_file")
        kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
        rm -f "$llm_pid_file"
        echo "✅ LLM服务已停止。"
    else
        echo "服务未运行。"
    fi
}

# 2. Gcli2api 代理
start_gcli_proxy() {
    local mode=$1 # "verbose" or "silent"
    
    # 再次调用检查函数，防止重复启动
    if check_gcli_status; then
        echo "✅ Gcli2api服务已在运行，跳过启动。"
        return 0
    fi

    echo "正在后台启动 gcli2api..."
    if [ -d "$HOME/gcli2api" ]; then
        local original_dir=$(pwd)
        cd "$HOME/gcli2api" || { echo "无法进入目录"; sleep 2; return 1; }

        # --- 清理旧进程 ---
        pkill -f "bash termux-start.sh" >/dev/null 2>&1
        if command -v pm2 >/dev/null; then
             pm2 delete web >/dev/null 2>&1
        fi
        sleep 0.5
        
        # 清空日志
        : > "$gcli_log_file"

        # --- 启动服务 ---
        nohup bash termux-start.sh < /dev/null > "$gcli_log_file" 2>&1 &
        local new_pid=$!
        
        # --- 根据模式决定是否显示日志 ---
        if [ "$mode" == "verbose" ]; then
            echo "启动命令已发送 (PID: $new_pid)。"
            echo "================ 日志输出 (按任意键停止查看，服务不中断) ================"
            
            tail -f "$gcli_log_file" &
            local tail_pid=$!
            
            read -n 1 -s -r
            
            kill "$tail_pid" 2>/dev/null
            wait "$tail_pid" 2>/dev/null
            
            echo -e "\n=========================================================================="
            echo "已退出日志查看模式。"
        else
            sleep 4
        fi
        
        # --- 检查进程状态 (宽容模式) ---
        local is_success=false
        
        # 1. 启动脚本进程还在
        if kill -0 "$new_pid" 2>/dev/null; then
            echo "$new_pid" > "$gcli_pid_file"
            is_success=true
        # 2. 日志显示 PM2 成功
        elif grep -q "PM2" "$gcli_log_file" || grep -q "online" "$gcli_log_file" || grep -q "Done" "$gcli_log_file"; then
            echo "PM2_WEB" > "$gcli_pid_file"
            is_success=true
        fi

        if [ "$is_success" = true ]; then
            if [ "$mode" == "verbose" ]; then echo "✅ 服务认定为运行正常。"; fi
            cd "$original_dir"
            return 0
        else
            echo "❌ 启动失败！进程已退出且未检测到PM2成功标志。"
            echo "--- 日志最后 10 行 ---"
            tail -n 10 "$gcli_log_file"
            echo "---------------------"
            rm -f "$gcli_pid_file"
            cd "$original_dir"
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

# 3. Build (Dark Server) 代理 - 后台启动版
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

# --- [修改] 关联启动处理器 ---
process_linked_start() {
    if [ "$enable_linked_start" == "true" ] && [ "$linked_proxy_service" != "none" ]; then
        echo "🔗 正在关联启动服务: $linked_proxy_service ..."
        local start_result=0
        
        case "$linked_proxy_service" in
            "llm")
                start_llm_proxy
                start_result=$?
                ;;
            "gcli")
                start_gcli_proxy "silent"
                start_result=$?
                ;;
            "build")
                start_build_proxy_bg
                start_result=$?
                ;;
            *)
                echo "无效关联配置。"
                ;;
        esac

        if [ $start_result -ne 0 ]; then
            err "⚠️ 关联服务启动失败！请检查上方报错。按任意键将继续尝试启动 SillyTavern..."
        else
            echo "✅ 关联服务启动成功。"
            echo "⏳ 正在等待 5 秒让代理服务完成初始化..."
            sleep 5
        fi
        echo "-----------------------------------------"
    fi
}


# --- [区块] SillyTavern 安装与更新 ---
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
install_st_fresh() { local repo_url="https://github.com/SillyTavern/SillyTavern"; if use_proxy; then repo_url="$proxy_url/$repo_url"; fi; local temp_new_dir="$HOME/SillyTavern_new"; echo "正在克隆全新的 SillyTavern 到临时目录..."; rm -rf "$temp_new_dir"; git clone --depth 1 --branch release "$repo_url" "$temp_new_dir" || { err "Git 克隆失败！"; rm -rf "$temp_new_dir"; return 1; }; echo "正在安装 npm 依赖..."; (cd "$temp_new_dir" && npm install) || { err "npm 依赖安装失败！"; rm -rf "$temp_new_dir"; return 1; }; if [ -d "$sillytavern_dir" ]; then echo "正在迁移用户数据..."; if [ -d "$sillytavern_dir/data/default-user" ]; then cp -r "$sillytavern_dir/data/default-user/characters/." "$temp_new_dir/public/characters/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/chats/." "$temp_new_dir/public/chats/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/worlds/." "$temp_new_dir/public/worlds/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/groups/." "$temp_new_dir/public/groups/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/group chats/." "$temp_new_dir/public/group chats/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/OpenAI Settings/." "$temp_new_dir/public/OpenAI Settings/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/User Avatars/." "$temp_new_dir/public/User Avatars/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/backgrounds/." "$temp_new_dir/public/backgrounds/" 2>/dev/null; cp -r "$sillytavern_dir/data/default-user/settings.json" "$temp_new_dir/public/settings.json" 2>/dev/null; else cp -r "$sillytavern_dir/public/characters/." "$temp_new_dir/public/characters/" 2>/dev/null; cp -r "$sillytavern_dir/public/chats/." "$temp_new_dir/public/chats/" 2>/dev/null; cp -r "$sillytavern_dir/public/worlds/." "$temp_new_dir/public/worlds/" 2>/dev/null; cp -r "$sillytavern_dir/public/groups/." "$temp_new_dir/public/groups/" 2>/dev/null; cp -r "$sillytavern_dir/public/group chats/." "$temp_new_dir/public/group chats/" 2>/dev/null; cp -r "$sillytavern_dir/public/OpenAI Settings/." "$temp_new_dir/public/OpenAI Settings/" 2>/dev/null; cp -r "$sillytavern_dir/public/User Avatars/." "$temp_new_dir/public/User Avatars/" 2>/dev/null; cp -r "$sillytavern_dir/public/backgrounds/." "$temp_new_dir/public/backgrounds/" 2>/dev/null; cp -r "$sillytavern_dir/public/settings.json" "$temp_new_dir/public/settings.json" 2>/dev/null; fi; echo "✅ 数据迁移完成。正在备份旧版本程序文件到 $sillytavern_old_dir..."; rm -rf "$sillytavern_old_dir"; mv "$sillytavern_dir" "$sillytavern_old_dir"; fi; mv "$temp_new_dir" "$sillytavern_dir"; echo "✅ 全新安装/更新完成！"; }
version_rollback() { if [ ! -d "$sillytavern_old_dir" ]; then err "错误：未找到可用于回退的旧版本。"; return; fi; read -n 1 -p "警告：这将用旧版本覆盖当前版本，是否确认 (y/n)? " confirm; echo; if [ "$confirm" != "y" ]; then echo "已取消。"; sleep 1; return; fi; echo "正在回退版本..."; mv "$sillytavern_dir" "$HOME/SillyTavern_temp"; mv "$sillytavern_old_dir" "$sillytavern_dir"; mv "$HOME/SillyTavern_temp" "$sillytavern_old_dir"; echo "✅ 版本回退成功！"; sleep 2; }
update_submenu() { while true; do clear; echo "========================================="; echo "         SillyTavern 安装与更新          "; echo "========================================="; local_ver=$(get_st_local_ver); latest_ver=$(get_st_latest_ver); echo; echo "  当前版本: $local_ver"; echo "  最新版本: $latest_ver"; echo "-----------------------------------------"; echo; echo "   [1] 增量更新 (推荐，速度快)"; echo; echo "   [2] 全新更新 (强制覆盖，并保留数据)"; echo; echo "   [3] 版本回退 (恢复到上一个版本)"; echo; echo "   [0] 返回主菜单"; echo; echo "========================================="; read -n 1 -p "请按键选择: " choice; echo; case "$choice" in 1) clear; update_st_incremental; echo; read -n 1 -p "操作完成！按任意键返回...";; 2) read -n 1 -p "警告：这将重新下载并覆盖程序文件，是否确认 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then clear; install_st_fresh; echo; read -n 1 -p "操作完成！按任意键返回..."; fi;; 3) clear; version_rollback;; 0) break;; *) err "无效选择...";; esac; done; }

# --- [区块] 其他子菜单 ---

# [新增] 关联启动设置子菜单
linked_start_submenu() {
    while true; do
        clear
        local status_text="关闭"
        if [ "$enable_linked_start" == "true" ]; then status_text="开启"; fi
        
        local current_selection_text="无"
        case "$linked_proxy_service" in
            "llm") current_selection_text="LLM代理";;
            "build") current_selection_text="Build反代";;
            "gcli") current_selection_text="Gcli2api代理";;
        esac

        echo "========================================="
        echo "           🔗 关联启动设置            "
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
        read -n 1 -p "请按键选择: " choice
        echo

        case "$choice" in
            1)
                clear
                echo "请选择要关联启动的服务 (单选):"
                echo " [1] LLM代理"
                echo " [2] Build反代 (dark-server)"
                echo " [3] Gcli2api代理"
                echo " [0] 取消"
                read -n 1 -p "选择: " sel
                case "$sel" in
                    1) linked_proxy_service="llm"; enable_linked_start="true"; save_config; echo; echo "✅ 已关联: LLM代理"; sleep 1;;
                    2) linked_proxy_service="build"; enable_linked_start="true"; save_config; echo; echo "✅ 已关联: Build反代"; sleep 1;;
                    3) linked_proxy_service="gcli"; enable_linked_start="true"; save_config; echo; echo "✅ 已关联: Gcli2api代理"; sleep 1;;
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
    clear; echo "========================================="; echo "         🔐 命令行密码启动设置         "; echo "========================================="; echo
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
        read -n 1 -p "请选择操作: " choice; echo
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
    clear; echo "========================================="; echo "           主菜单倒计时设置            "; echo "========================================="; echo
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
additional_features_submenu() { while true; do clear; echo "========================================="; echo "                附加功能                 "; echo "========================================="; echo; echo "   [1] 📦 软件包管理"; echo; echo "   [2] 🚀 Termux 环境初始化"; echo; echo "   [3] 🔔 通知保活设置 (当前: $enable_notification_keepalive)"; echo; echo "   [4] ⚡️ 跨会话自启设置 (当前: $enable_auto_start)"; echo; echo "   [5] 🔐 密码启动 (当前: $enable_password_start)"; echo; echo "   [6] ⏳ 开/关主菜单倒计时 (当前: $enable_menu_timeout)"; echo; echo "   [7] ⚙️  进入(可选的)原版脚本菜单"; echo "   [8] 🔗 关联启动 (当前: $enable_linked_start)"; echo; echo "   [0] ↩️  返回主菜单"; echo; echo "========================================="; read -n 1 -p "请按键选择 [1-8, 0]: " sub_choice; echo; case "$sub_choice" in 1) package_selection_submenu;; 2) termux_setup;; 3) toggle_notification_submenu;; 4) toggle_auto_start_submenu;; 5) toggle_password_start_submenu;; 6) toggle_menu_timeout_submenu;; 7) if [ ! -f "$install_script_name" ]; then clear; echo "========================================="; echo "      ⚠️ $install_script_name 脚本不存在"; echo "========================================="; echo; echo "   [1] 立即下载"; echo; echo "   [2] 暂不下载"; echo; echo "========================================="; read -n 1 -p "请按键选择 [1-2]: " choice; echo; if [ "$choice" == "1" ]; then echo "正在下载 $install_script_name..."; curl -s -O "$install_script_url" && chmod +x "$install_script_name"; if [ $? -eq 0 ]; then echo "下载成功！正在进入..."; sleep 1; clear; ./"$install_script_name"; exit 0; else err "下载失败！"; fi; fi; else echo "选择 [7]，正在进入原版脚本菜单..."; sleep 1; clear; ./"$install_script_name"; exit 0; fi;; 8) linked_start_submenu;; 0) break;; *) err "输入错误！请重新选择。";; esac; done; }
toggle_notification_submenu() { clear; echo "========================================="; echo "           通知保活功能设置            "; echo "========================================="; echo; echo "  此功能通过创建一个常驻通知来增强后台保活。"; echo "  当前状态: $enable_notification_keepalive"; echo; echo "========================================="; read -p "请输入 'true' 或 'false' 来修改设置: " new_status; if [ "$new_status" == "true" ] || [ "$new_status" == "false" ]; then enable_notification_keepalive="$new_status"; save_config; echo "✅ 设置已更新为 [$new_status] 并已保存。"; else echo "无效输入，设置未改变。"; fi; sleep 2; }
toggle_auto_start_submenu() { clear; echo "========================================="; echo "         跨会话自动启动设置            "; echo "========================================="; echo; echo "  此功能用于在检测到SillyTavern已运行时，"; echo "  自动在新会话中启动LLM代理服务。"; echo "  当前状态: $enable_auto_start"; echo; echo "========================================="; read -p "请输入 'true' 或 'false' 来修改设置: " new_status; if [ "$new_status" == "true" ] || [ "$new_status" == "false" ]; then enable_auto_start="$new_status"; save_config; echo "✅ 设置已更新为 [$new_status] 并已保存。"; else echo "无效输入，设置未改变。"; fi; sleep 2; }
display_service_status() { 
    local st_status_text="\033[0;31m未启动\033[0m"; 
    local llm_status_text="\033[0;31m未启动\033[0m"; 
    local gcli_status_text="\033[0;31m未启动\033[0m";

    if [ "$st_is_running" = true ]; then st_status_text="\033[0;32m已启动\033[0m"; fi; 
    if [ "$llm_is_running" = true ]; then llm_status_text="\033[0;32m已启动\033[0m"; fi; 
    
    # [修复] 使用新函数检测全局状态
    gcli_is_running=false
    if check_gcli_status; then 
        gcli_is_running=true
        gcli_status_text="\033[0;32m已启动\033[0m"; 
    fi

    echo "========================================="; 
    echo "服务运行状态:"; 
    echo -e "  SillyTavern:   $st_status_text"; 
    echo -e "  LLM代理服务:  $llm_status_text"; 
    echo -e "  Gcli2api反代:  $gcli_status_text";
    echo "========================================="; 
}
package_manager_submenu() { local pkg_name=$1; local cmd_to_check=$2; local is_core=$3; while true; do clear; echo "========================================="; echo "          软件包管理: $pkg_name          "; echo "========================================="; echo; if [ "$is_core" = true ]; then echo "   [ ⚠️ 必要 ] 此软件包是运行的核心依赖。"; else echo "   [ ✨ 可选 ] 此软件包提供额外功能。"; fi; echo; echo "   [1] 安装此软件包 (命令行)"; echo; echo "   [2] 卸载此软件包 (命令行)"; echo; if [ "$pkg_name" == "termux-api" ]; then echo "   [D] 在浏览器中打开配套APP下载页面"; echo; fi; echo "   [0] 返回上一级"; echo; echo "========================================="; read -n 1 -p "请按键选择: " action_choice; echo; case "$action_choice" in 1) if command -v "$cmd_to_check" >/dev/null; then echo "✅ 软件包 $pkg_name 似乎已经安装。"; sleep 2; else read -n 1 -p "准备安装 $pkg_name ，是否确认 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then pkg install "$pkg_name" -y; echo "安装完成！"; sleep 2; else echo "已取消安装。"; sleep 1; fi; fi;; 2) if ! command -v "$cmd_to_check" >/dev/null; then echo "ℹ️ 软件包 $pkg_name 尚未安装。"; sleep 2; else if [ "$is_core" = true ]; then echo "警告：这是一个核心软件包，卸载可能导致程序无法运行！"; fi; read -n 1 -p "准备卸载 $pkg_name ，是否确认 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then pkg uninstall "$pkg_name" -y; echo "卸载完成！"; sleep 2; else echo "已取消卸载。"; sleep 1; fi; fi;; "d"|"D") if [ "$pkg_name" == "termux-api" ]; then if command -v termux-open-url >/dev/null; then echo "正在浏览器中打开下载页面..."; termux-open-url "$termux_api_apk_url"; sleep 2; else echo "错误: termux-open-url 命令不可用！请先安装 termux-api 命令行包。"; sleep 3; fi; else echo "无效选择..."; sleep 1; fi;; 0) break;; *) echo "无效选择..."; sleep 1;; esac; done; }
package_selection_submenu() { while true; do clear; echo "========================================="; echo "           必要软件包管理              "; echo "========================================="; echo; echo "   [1] git (版本控制)       - ⚠️ 必要"; echo; echo "   [2] curl (网络下载)      - ⚠️ 必要"; echo; echo "   [3] nodejs-lts (运行环境) - ⚠️ 必要"; echo; echo "   [4] jq (版本显示)        - ✨ 可选"; echo; echo "   [5] termux-api (后台保活)  - ✨ 可选"; echo; echo "   [0] 返回主菜单"; echo; echo "========================================="; read -n 1 -p "请按键选择要管理的软件包 [1-5, 0]: " pkg_choice; echo; case "$pkg_choice" in 1) package_manager_submenu "git" "git" true;; 2) package_manager_submenu "curl" "curl" true;; 3) package_manager_submenu "nodejs-lts" "node" true;; 4) package_manager_submenu "jq" "jq" false;; 5) package_manager_submenu "termux-api" "termux-wake-lock" false;; 0) break;; *) echo "无效选择..."; sleep 1; continue;; esac; done; }
termux_setup() { clear; echo "========================================="; echo "       欢迎使用 Termux 环境初始化        "; echo "========================================="; echo; echo "本向导将为您更新系统并安装所有核心依赖。"; echo "这是一个一次性操作，可以确保脚本稳定运行。"; echo; read -n 1 -p "是否立即开始 (y/n)? " confirm; echo; if [ "$confirm" == "y" ]; then echo; echo "--- [步骤 1/2] 正在更新 Termux 基础包 ---"; yes | pkg upgrade; echo "--- [步骤 2/2] 正在安装核心软件包 ---"; apt update && apt install git curl nodejs-lts -y; echo "✅ 环境初始化完成！"; sleep 2; else echo; echo "已取消初始化。"; sleep 2; fi; }

# [新增] 代理服务子菜单
proxy_service_submenu() {
    while true; do
        # 刷新 LLM 状态显示
        local llm_submenu_is_running=false
        if [ -f "$llm_pid_file" ] && kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then llm_submenu_is_running=true; fi
        local llm_status_text=""
        if [ "$llm_submenu_is_running" = true ]; then llm_status_text="🛑 停止 LLM 代理服务"; else llm_status_text="📤 启动 LLM 代理服务"; fi

        # 刷新 Gcli2api 状态显示 (使用新函数)
        local gcli_status_text=""
        if check_gcli_status; then 
            gcli_status_text="🛑 停止 gcli2api 反代"
        else 
            gcli_status_text="🟢 启动 gcli2api 反代"
        fi

        clear
        echo "========================================="
        echo "           🛎️  代理服务菜单            "
        echo "========================================="
        echo
        echo "   [1] $llm_status_text"
        echo
        echo "   [2] 🟢 启动 build 反代 (前台调试)"
        echo
        echo -e "   [3] $gcli_status_text"
        echo
        echo "   [0] ↩️  返回主菜单"
        echo
        echo "========================================="
        read -n 1 -p "请按键选择 [1-3, 0]: " sub_choice
        echo
        case "$sub_choice" in
            1)
                if [ "$llm_submenu_is_running" = true ]; then stop_llm_proxy; else start_llm_proxy; read -n 1 -p "按任意键继续..."; fi
                ;;
            2)
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
            3)
                clear
                # 使用新函数检测
                if check_gcli_status; then
                    stop_gcli_proxy
                    read -n 1 -p "按任意键返回..."
                else
                    # 仅在手动启动时使用 "verbose" 模式
                    start_gcli_proxy "verbose"
                    if [ $? -eq 0 ]; then
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
trap cleanup EXIT
st_is_running=false
if [ -f "$st_pid_file" ] && kill -0 "$(cat "$st_pid_file")" 2>/dev/null; then st_is_running=true; else rm -f "$st_pid_file"; fi
if [ "$enable_auto_start" = true ] && [ "$st_is_running" = true ]; then llm_is_running=false; if [ -f "$llm_pid_file" ] && kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then llm_is_running=true; fi; if [ "$llm_is_running" = false ]; then st_pid=$(cat "$st_pid_file"); clear; echo "✅ 检测到 SillyTavern (PID: $st_pid) 正在运行。"; echo "🚀 根据预设逻辑，将自动启动 LLM 代理服务..."; start_llm_proxy; echo "自动启动任务完成。正在进入主菜单..."; sleep 1; fi; fi

while true; do
    # 状态刷新检测
    st_is_running=false
    if [ -f "$st_pid_file" ] && kill -0 "$(cat "$st_pid_file")" 2>/dev/null; then st_is_running=true; fi
    llm_is_running=false
    if [ -f "$llm_pid_file" ] && kill -0 "$(cat "$llm_pid_file")" 2>/dev/null; then llm_is_running=true; fi
    
    # [修复] 使用新函数检测全局状态
    gcli_is_running=false
    if check_gcli_status; then gcli_is_running=true; fi

    clear
    keepalive_status_text="(带唤醒锁)"
    if [ "$enable_notification_keepalive" = true ]; then keepalive_status_text="(唤醒锁+通知)"; fi
    
    echo "========================================="
    echo "       欢迎使用 Termux 启动脚本        "
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
    
    display_service_status
    choice=""
    
    if [ "$st_is_running" = true ]; then
        read -n 1 -p "请按键选择 [1-5, 0]: " choice
        echo
    else
        if [ "$enable_menu_timeout" = true ]; then
            prompt_text="请按键选择 [1-5, 0] "
            final_text="秒后自动选1): "
            for i in $(seq $menu_timeout -1 1); do
                printf "\r%s(%2d%s" "$prompt_text" "$i" "$final_text"
                read -n 1 -t 1 choice
                if [ -n "$choice" ]; then break; fi
            done
            printf "\r\033[K"
            choice=${choice:-1}
        else
            read -n 1 -p "请按键选择 [1-5, 0]: " choice
            echo
        fi
    fi
    
    case "$choice" in
        1)
            if [ "$st_is_running" = true ]; then err "SillyTavern 已在运行中！"; continue; fi
            if [ ! -f "$sillytavern_dir/server.js" ]; then err "SillyTavern 尚未安装，请用选项[3]安装。"; continue; fi
            
            # --- [修改] 关联启动检查 (静默) ---
            process_linked_start
            # ---------------------------

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
            echo "SillyTavern 已启动 (PID: $st_pid)，按任意键可返回菜单（服务将在后台继续运行）。"
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
            
            # --- [修改] 关联启动检查 (静默) ---
            process_linked_start
            # ---------------------------

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
            echo "SillyTavern 已在局域网模式下启动 (PID: $st_pid)，按任意键可返回菜单（服务将在后台继续运行）。"
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