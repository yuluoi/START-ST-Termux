#!/bin/bash
# ===================================================================================
# --- [附加功能扩展模块] ---
# 文件名: st_launcher_addons.sh
# 存放路径: $HOME/st_launcher_addons.sh
# ===================================================================================

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

silent_start_submenu() {
    while true; do
        clear
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
                            echo "⚠️ 冲突检测: [gcli2api代理] 已在 关联启动 中 开启。"
                            echo " 1. 开启无感启动（同时关闭关联启动）"
                            echo " 2. 返回上一步"
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
                                2|*)
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
                            echo "⚠️ 冲突检测: [gcli2api代理] 已在 无感启动 中 开启。"
                            echo " 1. 开启关联启动（同时关闭无感启动）"
                            echo " 2. 返回上一步"
                            read -n 1 -p "请选择: " conflict_choice
                            case "$conflict_choice" in
                                1)
                                    enable_silent_start="false"
                                    silent_start_service="none"
                                    linked_proxy_service="gcli"
                                    enable_linked_start="true"
                                    save_config
                                    echo; echo "✅ 已关联: gcli2api代理 (关联启动开启，已自动关闭无感启动)"
                                    sleep 2
                                    ;;
                                2|*)
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
    echo "========================================="
    echo "            通知保活功能设置             "
    echo "========================================="
    echo
    echo "  此功能通过创建一个常驻通知来增强后台保活。"
    echo "  当前状态: $enable_notification_keepalive"
    echo
    echo "========================================="
    read -p "请输入 'true' 或 'false' 来修改设置: " new_status
    if [ "$new_status" == "true" ]; then 
        if ! command -v termux-notification >/dev/null; then
            echo "❌ 检测失败: 未安装 termux-api 命令行工具，请先在[软件包管理]中安装。"
        else
            rm -f "$HOME/.st_notif_confirm"
            termux-notification --id 1002 --title "Termux 启动脚本" --content "是否确认开启通知保活功能？" --button1 "是(开启)" --button1-action "touch $HOME/.st_notif_confirm; termux-notification-remove 1002" >/dev/null 2>&1
            
            echo "⏳ 验证请求已发出！"
            echo "👉 请下拉手机状态栏，找到弹出的通知并点击【是(开启)】按钮。"
            echo "等待操作中 (30秒超时)..."
            
            local wait_count=0
            local confirmed=false
            while [ $wait_count -lt 30 ]; do
                if [ -f "$HOME/.st_notif_confirm" ]; then
                    confirmed=true
                    break
                fi
                sleep 1
                wait_count=$((wait_count + 1))
            done
            
            rm -f "$HOME/.st_notif_confirm"
            termux-notification-remove 1002 >/dev/null 2>&1
            
            if [ "$confirmed" == "true" ]; then
                enable_notification_keepalive="true"
                save_config
                echo "✅ 已成功通过通知栏确认！设置已更新为 [true] 并已保存。"
            else
                echo "❌ 等待超时: 未收到通知栏的确认指令。"
                echo "   可能原因: 1. 手机未安装 Termux:API 安卓软件(APP)"
                echo "             2. 系统屏蔽了通知或没有给予相关权限"
            fi
        fi
    elif [ "$new_status" == "false" ]; then 
        enable_notification_keepalive="false"
        save_config
        echo "✅ 设置已更新为 [false] 并已保存。"
    else 
        echo "无效输入，设置未改变。"
    fi
    sleep 3
}

additional_features_submenu() { 
    while true; do 
        clear
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