#!/bin/bash
# ===================================================================================
# --- [代理服务模块] ---
# 文件名: st_launcher_proxy.sh
# 存放路径: $HOME/st_launcher_proxy.sh
# ===================================================================================

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