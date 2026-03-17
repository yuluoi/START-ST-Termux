#!/bin/bash
# ===================================================================================
# --- [安装与更新模块] ---
# 文件名: st_launcher_update.sh
# 存放路径: $HOME/st_launcher_update.sh
# ===================================================================================

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