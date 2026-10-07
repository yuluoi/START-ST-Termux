#!/bin/bash
# ===================================================================================
# --- [附加模块] 聊天记录恢复模块 ---
# 文件名: Recover_record.sh
# ===================================================================================

recover_chat_history() {
    clear
    echo "========================================="
    echo "            📂 聊天记录恢复             "
    echo "========================================="
    echo
    
    local chats_dir="$sillytavern_dir/data/default-user/chats"
    local backups_dir="$sillytavern_dir/data/default-user/backups"
    
    if [ ! -d "$chats_dir" ]; then
        echo "❌ 找不到聊天记录文件夹: $chats_dir"
        echo
        read -n 1 -p "按任意键返回主菜单..."
        return
    fi
    
    # 提取所有文件夹名
    local folders=()
    while IFS= read -r -d '' dir; do
        folders+=("$(basename "$dir")")
    done < <(find "$chats_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    
    if [ ${#folders[@]} -eq 0 ]; then
        echo "❌ 没有找到任何角色聊天文件夹。"
        echo
        read -n 1 -p "按任意键返回主菜单..."
        return
    fi
    
    echo "读取到以下角色文件夹："
    local i=1
    for folder in "${folders[@]}"; do
        echo "$i. $folder"
        i=$((i + 1))
    done
    echo "0. 取消"
    echo "========================================="
    
    local sel
    read -p "请输入序号进行选择: " sel
    
    if [[ ! "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -eq 0 ] || [ "$sel" -gt ${#folders[@]} ]; then
        echo "已取消或输入无效。"
        sleep 1
        return
    fi
    
    local selected_folder="${folders[$((sel-1))]}"
    echo "已选择文件夹: $selected_folder"
    
    if [ ! -d "$backups_dir" ]; then
        echo "❌ 找不到备份文件夹: $backups_dir"
        echo
        read -n 1 -p "按任意键返回主菜单..."
        return
    fi
    
    echo "正在查找备份文件中 (时间倒序，大小>=2MB)..."
    
    # 构建要匹配的目标字段
    local target_string="\"chatId\":\"$selected_folder - "
    local found_file=""
    
    shopt -s nullglob
    local backup_files=("$backups_dir"/*.jsonl)
    shopt -u nullglob
    
    if [ ${#backup_files[@]} -eq 0 ]; then
         echo "❌ 备份文件夹中没有找到 .jsonl 格式的备份文件。"
         echo
         read -n 1 -p "按任意键返回主菜单..."
         return
    fi

    # 使用 ls -t 将备份文件按时间倒序排列读取
    while IFS= read -r file; do
        # 获取文件大小 (字节)
        local size
        size=$(stat -c %s "$file" 2>/dev/null)
        if [ -z "$size" ]; then continue; fi
        
        # 判断大小是否 >= 2MB (2 * 1024 * 1024 = 2097152 字节)
        if [ "$size" -ge 2097152 ]; then
            # 快速匹配目标字符串内容
            if grep -q -F "$target_string" "$file"; then
                found_file="$file"
                break
            fi
        fi
    done < <(ls -t "${backup_files[@]}")
    
    if [ -n "$found_file" ]; then
        echo
        echo "✅ 找到匹配的备份文件："
        echo "文件: $(basename "$found_file")"
        echo "大小: $(stat -c %s "$found_file") 字节"
        echo
        echo "正在复制到: $chats_dir/$selected_folder/"
        cp "$found_file" "$chats_dir/$selected_folder/"
        if [ $? -eq 0 ]; then
            echo "🎉 恢复成功！文件已成功复制。"
        else
            echo "❌ 复制失败，请检查文件权限或路径。"
        fi
    else
        echo
        echo "❌ 未找到符合以下所有条件的备份文件："
        echo "   1. 包含匹配字段: $target_string"
        echo "   2. 文件大小: 不低于 2MB"
    fi
    
    echo
    read -n 1 -p "按任意键返回主菜单..."
}
