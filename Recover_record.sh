#!/bin/bash
# ===================================================================================
# --- [附加模块] 聊天记录恢复模块 (实验性版本) ---
# 文件名: Recover_record.sh
# ===================================================================================

recover_chat_history() {
    clear
    echo "========================================="
    echo "       📂 聊天记录恢复 (实验性版本)      "
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
    echo "请选择恢复策略："
    echo " [1] 时间最晚 (取最近的备份，速度较快)"
    echo " [2] 对话数最多 (忽略时间，取该角色对话记录最多的备份，需全局扫描)"
    
    local strategy=""
    while true; do
        read -n 1 -p "请输入序号(1 或 2): " strategy
        echo
        if [[ "$strategy" == "1" ]] || [[ "$strategy" == "2" ]]; then
            break
        else
            echo "输入无效，请输入 1 或 2。"
        fi
    done

    echo "========================================="
    echo "🔍 正在进行智能匹配 (大小>=1MB，且包含至少2次角色name)..."
    if [ "$strategy" == "2" ]; then
        echo "⏳ 启用全局扫描模式，请耐心等待..."
    fi
    
    # 用于策略2的记录数组
    declare -A max_counts
    declare -A best_files

    # 智能搜索逻辑：
    # 按照时间倒序遍历备份文件，比对当前尚未恢复的角色。
    while IFS= read -r file; do
        # 策略1：如果所有待恢复角色都已找到，直接跳出读取文件的大循环，避免无效搜索
        if [ "$strategy" == "1" ] && [ ${#pending_folders[@]} -eq 0 ]; then
            break
        fi
        
        # 获取文件大小 (字节)
        local size
        size=$(stat -c %s "$file" 2>/dev/null)
        if [ -z "$size" ]; then continue; fi
        
        # =========================================================
        # 【修改文件大小限制说明】
        # 这里判断文件大小是否符合条件。实验版本设置为不低于 1MB。
        # 0.5 MB = 524288  字节
        # 1 MB   = 1048576 字节
        # 1.5 MB = 1572864 字节
        # 2 MB   = 2097152 字节
        # 2.5 MB = 2621440 字节
        # 3 MB   = 3145728 字节
        # =========================================================
        if [ "$size" -ge 1048576 ]; then
            # 遍历当前尚未找到备份/尚未扫描完毕的目标角色
            for target in "${!pending_folders[@]}"; do
                local target_string="\"chatId\":\"$target - "
                local target_name_string="\"name\":\"$target\""
                
                # 步骤 1: 极速匹配目标 chatId 字符串
                if grep -q -F "$target_string" "$file"; then
                    
                    # 步骤 2: 统计 "name":"文件夹名" 出现的次数
                    local name_count
                    name_count=$(grep -o -F "$target_name_string" "$file" | wc -l)
                    
                    # 判断出现次数是否至少为 2 次
                    if [ "$name_count" -ge 2 ]; then
                        
                        if [ "$strategy" == "1" ]; then
                            # 策略 1：找到即恢复
                            # 获取精准到毫秒的当前时间并构造新文件名
                            local current_time=$(date +"%Y-%m-%d@%Hh%Mm%Ss%3Nms")
                            local new_filename="${target} - ${current_time}.jsonl"
                            
                            echo "✅ [$target] 匹配成功 (name出现 ${name_count} 次) -> $(basename "$file")"
                            # 在复制的同时重命名文件，绝对不影响源文件
                            cp "$file" "$chats_dir/$target/$new_filename"
                            if [ $? -eq 0 ]; then
                                echo "   🎉 复制完成，已重命名为: $new_filename"
                            else
                                echo "   ❌ 复制失败，请检查权限"
                            fi
                            # 从列表中剔除
                            unset pending_folders["$target"]
                            break # 跳出内层 for 循环，处理下一个文件
                            
                        elif [ "$strategy" == "2" ]; then
                            # 策略 2：记录最高次数和对应文件
                            local current_max=${max_counts["$target"]:-0}
                            # 使用 -gt 确保在次数并列时，取时间更晚的那个（因为 ls -t 最先扫到的是最新的）
                            if [ "$name_count" -gt "$current_max" ]; then
                                max_counts["$target"]=$name_count
                                best_files["$target"]="$file"
                            fi
                        fi
                    fi
                fi
            done
        fi
    done < <(ls -t "${backup_files[@]}")
    
    # 策略 2 的善后处理：循环结束后执行复制
    if [ "$strategy" == "2" ]; then
        for target in "${!pending_folders[@]}"; do
            local best_file="${best_files["$target"]}"
            if [ -n "$best_file" ]; then
                local best_count="${max_counts["$target"]}"
                # 获取精准到毫秒的当前时间并构造新文件名
                local current_time=$(date +"%Y-%m-%d@%Hh%Mm%Ss%3Nms")
                local new_filename="${target} - ${current_time}.jsonl"
                
                echo "✅ [$target] 匹配成功 (最高对话数: ${best_count} 次) -> $(basename "$best_file")"
                # 在复制的同时重命名文件，绝对不影响源文件
                cp "$best_file" "$chats_dir/$target/$new_filename"
                if [ $? -eq 0 ]; then
                    echo "   🎉 复制完成，已重命名为: $new_filename"
                else
                    echo "   ❌ 复制失败，请检查权限"
                fi
                # 从列表中剔除，以配合后续的未找到检查
                unset pending_folders["$target"]
            fi
        done
    fi
    
    echo "========================================="
    
    # 检查是否还有未找到备份的角色
    if [ ${#pending_folders[@]} -gt 0 ]; then
        echo "⚠️ 以下角色的备份未找到符合条件的文件 (>=1MB，含对应字段，且name>=2次):"
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
