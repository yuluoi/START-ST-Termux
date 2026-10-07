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
    echo "[all] 全选"
    local i=1
    for folder in "${folders[@]}"; do
        echo "[$i] $folder"
        i=$((i + 1))
    done
    echo "[0] 取消"
    echo "========================================="
    
    local sel
    read -p "请输入序号进行选择，多个文件序号之间用逗号分隔： " sel
    
    # 去除输入中可能存在的空格
    sel=$(echo "$sel" | tr -d ' ')
    
    if [[ -z "$sel" ]] || [[ "$sel" == "0" ]]; then
        echo "已取消。"
        sleep 1
        return
    fi
    
    # 使用关联数组记录需要恢复的目标文件夹，利用关联数组的特性天然去重
    declare -A pending_folders
    
    if [[ "${sel,,}" == "all" ]]; then
        for folder in "${folders[@]}"; do
            pending_folders["$folder"]=1
        done
    else
        # 将逗号分隔的输入转为数组
        IFS=',' read -ra ADDR <<< "$sel"
        for idx in "${ADDR[@]}"; do
            if [[ "$idx" == "0" ]]; then
                echo "已取消。"
                sleep 1
                return
            fi
            # 校验输入是否为有效数字
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -gt 0 ] && [ "$idx" -le "${#folders[@]}" ]; then
                local selected_folder="${folders[$((idx-1))]}"
                pending_folders["$selected_folder"]=1
            fi
        done
    fi
    
    local pending_count=${#pending_folders[@]}
    if [ "$pending_count" -eq 0 ]; then
        echo "输入无效，未选择任何有效角色。"
        sleep 1
        return
    fi
    
    echo "已选择 $pending_count 个角色准备恢复。"
    
    if [ ! -d "$backups_dir" ]; then
        echo "❌ 找不到备份文件夹: $backups_dir"
        echo
        read -n 1 -p "按任意键返回主菜单..."
        return
    fi
    
    shopt -s nullglob
    local backup_files=("$backups_dir"/*.jsonl)
    shopt -u nullglob
    
    if [ ${#backup_files[@]} -eq 0 ]; then
         echo "❌ 备份文件夹中没有找到 .jsonl 格式的备份文件。"
         echo
         read -n 1 -p "按任意键返回主菜单..."
         return
    fi

    echo "========================================="
    echo "🔍 正在进行智能匹配 (时间倒序，大小>=2MB)..."
    
    # 智能搜索逻辑：
    # 按照时间倒序遍历备份文件，比对当前尚未恢复的角色。
    # 一旦某角色的最新备份被找到，就从 pending_folders 中剔除。
    # 如果 pending_folders 为空，说明全部找齐，立即提前结束搜索循环。
    while IFS= read -r file; do
        # 如果所有待恢复角色都已找到，直接跳出读取文件的大循环，避免无效搜索
        if [ ${#pending_folders[@]} -eq 0 ]; then
            break
        fi
        
        # 获取文件大小 (字节)
        local size
        size=$(stat -c %s "$file" 2>/dev/null)
        if [ -z "$size" ]; then continue; fi
        
        # 判断大小是否 >= 2MB (2 * 1024 * 1024 = 2097152 字节)
        if [ "$size" -ge 2097152 ]; then
            # 遍历当前尚未找到备份的目标角色
            for target in "${!pending_folders[@]}"; do
                local target_string="\"chatId\":\"$target - "
                
                # 快速匹配目标字符串内容 (使用 -F 避免正则符号冲突)
                if grep -q -F "$target_string" "$file"; then
                    echo "✅ [$target] 匹配成功 -> $(basename "$file")"
                    cp "$file" "$chats_dir/$target/"
                    if [ $? -eq 0 ]; then
                        echo "   🎉 复制完成"
                    else
                        echo "   ❌ 复制失败，请检查权限"
                    fi
                    
                    # 匹配成功后，将该角色从待找寻列表中删除，此后不再搜索它的旧备份
                    unset pending_folders["$target"]
                    
                    # 一个备份文件通常对应一个角色，找到即可跳出内层循环继续看下一个文件
                    break
                fi
            done
        fi
    done < <(ls -t "${backup_files[@]}")
    
    echo "========================================="
    
    # 检查是否还有未找到备份的角色
    if [ ${#pending_folders[@]} -gt 0 ]; then
        echo "⚠️ 以下角色的备份未找到符合条件的文件 (>=2MB 且包含对应字段):"
        for target in "${!pending_folders[@]}"; do
            echo "   - $target"
        done
        echo "========================================="
    else
        echo "✨ 所有选择的角色均已成功恢复！"
    fi
    
    echo
    read -n 1 -p "按任意键返回主菜单..."
}
