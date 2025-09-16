#!/bin/bash

# 记录 kissat-4.0.1求解器完整输出的脚本
# 当前仍然采用原始混合策略：在普通 VSIDS 和其他策略间切换
# 功能：记录回溯日志（冲突回溯和普通回溯）和求解结果统计
# 设置循环次数
LOOP_COUNT=1  # 可以根据需要调整循环次数

# 需要修改的路径
CNF_DIR="/mnt/chenli/SAT/2021cnf"
OUTPUT_DIR="/mnt/chenli/SAT/ori-kissat-4.0.1/ori_mix_output_logs"
KISSAT_PATH="/mnt/chenli/SAT/ori-kissat-4.0.1/build/kissat"

# 每次循环处理的CNF文件个数
TOTAL_FILES=400

# 获取系统的CPU核心数
NUM_CORES=$(nproc)

# 确保输出目录存在
mkdir -p "$OUTPUT_DIR"

# 定义处理单个文件的函数，接收循环次数和文件路径作为参数
process_file() {
    loop_num="$1"
    file="$2"
    str=$(readlink -f "$file")
    echo "循环 $loop_num: 开始处理文件: $str"

    # 获取文件名（不含路径）
    filename=$(basename "$str")
    
    # 创建唯一的输出文件，包含进程ID以避免并行冲突
    output_file="$OUTPUT_DIR/kissat_output_${loop_num}_${filename}_$$.log"
    
    # 在输出文件开头记录CNF文件路径和开始时间
    echo "========================================" > "$output_file"
    echo "CNF文件: $str" >> "$output_file"
    echo "开始时间: $(date)" >> "$output_file"
    echo "========================================" >> "$output_file"
    
    # 创建临时文件存储完整输出
    temp_output=$(mktemp)
    
    # 使用timeout命令限制程序执行时间为3600秒，并记录完整输出到临时文件
    # 添加--log=1参数以启用回溯日志记录
    timeout -s SIGTERM 3600 "$KISSAT_PATH" --log=1 "$str" > "$temp_output" 2>&1
    exit_code=$?

        # 解析 LBD_LOG 行写入当前实例专属 CSV
        # 输出文件：$OUTPUT_DIR/lbd_<原文件名>.csv
        lbd_csv="$OUTPUT_DIR/lbd_${filename}.csv"
        if [ ! -f "$lbd_csv" ]; then
                echo "instance,loop,conflict,learned_index,lbd,size" > "$lbd_csv"
        fi
        awk -v inst="$filename" -v loop="$loop_num" -v of="$lbd_csv" '
            /LBD_LOG/ {
                conflict=""; learned=""; lbd=""; size="";
                for (i=1;i<=NF;i++) {
                    if ($i ~ /^conflict=/) { split($i,a,"="); conflict=a[2]; }
                    else if ($i ~ /^learned=/) { split($i,a,"="); learned=a[2]; }
                    else if ($i ~ /^lbd=/) { split($i,a,"="); lbd=a[2]; }
                    else if ($i ~ /^size=/) { split($i,a,"="); size=a[2]; }
                }
                if (conflict!="" && learned!="" && lbd!="") {
                    printf "%s,%s,%s,%s,%s,%s\n", inst, loop, conflict, learned, lbd, size >> of;
                }
            }
        ' "$temp_output"
    
    # 过滤输出：保留求解前和求解后的信息，跳过求解过程中的详细信息
    awk '
    BEGIN { in_solving = 0 }
    /^c ---- \[ solving \] -----------------------------------------------------------$/ { 
        in_solving = 1 
        print $0
        next
    }
    /^c ---- \[ result \] ------------------------------------------------------------$/ { 
        in_solving = 0 
        next
    }
    !in_solving { print $0 }
    ' "$temp_output" >> "$output_file"
    
    # 单独提取并保存BACKTRACK_LOG信息到专门的日志文件
    backtrack_log_file="$OUTPUT_DIR/backtrack_logs_${loop_num}_${filename}_$$.log"
    echo "========================================" > "$backtrack_log_file"
    echo "CNF文件: $str" >> "$backtrack_log_file"
    echo "开始时间: $(date)" >> "$backtrack_log_file"
    echo "BACKTRACK_LOG 详细信息:" >> "$backtrack_log_file"
    echo "========================================" >> "$backtrack_log_file"
    
    # 只提取决策相关的BACKTRACK_LOG行（排除系统维护性回溯）
    grep -E "BACKTRACK_LOG: (backtrack from level|conflict_backtrack)" "$temp_output" >> "$backtrack_log_file" 2>/dev/null
    
    # 统计回溯信息（只统计决策相关的回溯）
    echo "" >> "$backtrack_log_file"
    echo "========================================" >> "$backtrack_log_file"
    echo "回溯统计信息:" >> "$backtrack_log_file"
    
    # 统计回溯信息
    conflict_backtracks=$(grep -c "BACKTRACK_LOG: conflict_backtrack" "$temp_output" 2>/dev/null || echo "0")
    normal_backtracks=$(grep -c "BACKTRACK_LOG: backtrack from level" "$temp_output" 2>/dev/null || echo "0")
    total_decision_backtracks=$((conflict_backtracks + normal_backtracks))
    
    echo "冲突回溯次数: $conflict_backtracks" >> "$backtrack_log_file"
    echo "普通回溯次数: $normal_backtracks" >> "$backtrack_log_file"
    echo "总决策回溯次数: $total_decision_backtracks" >> "$backtrack_log_file"
    
    if [ "$total_decision_backtracks" -gt 0 ]; then
        # 提取最后冲突次数
        last_conflicts=$(grep -E "BACKTRACK_LOG: (backtrack from level|conflict_backtrack)" "$temp_output" | tail -1 | grep -o 'conflicts [0-9]*' | cut -d' ' -f2 2>/dev/null || echo "N/A")
        echo "最终冲突次数: $last_conflicts" >> "$backtrack_log_file"
        
        # 提取决策层级范围
        max_level=$(grep -E "BACKTRACK_LOG: (backtrack from level|conflict_backtrack)" "$temp_output" | grep -o 'from level [0-9]*' | cut -d' ' -f3 | sort -n | tail -1 2>/dev/null || echo "N/A")
        echo "最大决策层级: $max_level" >> "$backtrack_log_file"
    fi
    
    echo "结束时间: $(date)" >> "$backtrack_log_file"
    echo "========================================" >> "$backtrack_log_file"
    
    # 清理临时文件
    rm -f "$temp_output"
    
    # 记录结束时间和退出码
    echo "" >> "$output_file"
    echo "========================================" >> "$output_file"
    echo "结束时间: $(date)" >> "$output_file"
    if [ $exit_code -eq 124 ]; then
        echo "状态: TIMEOUT (3600秒)" >> "$output_file"
        echo "文件处理超时: $str"
    else
        echo "退出码: $exit_code" >> "$output_file"
        echo "文件处理完成: $str"
    fi
    echo "========================================" >> "$output_file"
    
    # 在文件末尾添加空行用于分隔不同问题的记录
    echo "" >> "$output_file"
}

export -f process_file
export KISSAT_PATH
export OUTPUT_DIR

# 主循环
for ((i=1; i<=LOOP_COUNT; i++)); do
    echo "=============================="
    echo "开始循环 $i"
    echo "=============================="

    # 切换到CNF文件目录
    cd "$CNF_DIR" || { echo "无法切换到目录 $CNF_DIR"; exit 1; }

    # 获取所有CNF文件
    find . -name "*.cnf" | head -n "$TOTAL_FILES" > "/tmp/cnf_files_${i}.txt"

    # 检查是否有文件需要处理
    if [ ! -s "/tmp/cnf_files_${i}.txt" ]; then
        echo "循环 $i: 没有找到CNF文件。跳过。"
        continue
    fi

    echo "循环 $i: 找到 $(wc -l < "/tmp/cnf_files_${i}.txt") 个CNF文件"

    # 使用xargs命令并行处理文件
    cat "/tmp/cnf_files_${i}.txt" | \
    xargs -P "$NUM_CORES" -I {} bash -c 'process_file "$0" "$1"' "$i" "{}"

    echo "循环 $i 完成。输出文件保存在: $OUTPUT_DIR"
    
    # 清理临时文件
    rm -f "/tmp/cnf_files_${i}.txt"
done

echo "所有 $LOOP_COUNT 次循环处理完成"
echo "完整输出日志保存在目录: $OUTPUT_DIR"

# 创建一个汇总文件
SUMMARY_FILE="$OUTPUT_DIR/processing_summary_$(date +%Y%m%d_%H%M%S).txt"
echo "处理汇总报告" > "$SUMMARY_FILE"
echo "生成时间: $(date)" >> "$SUMMARY_FILE"
echo "========================================" >> "$SUMMARY_FILE"
echo "处理的CNF文件总数: $(find "$OUTPUT_DIR" -name "kissat_output_*.log" | wc -l)" >> "$SUMMARY_FILE"
echo "输出日志目录: $OUTPUT_DIR" >> "$SUMMARY_FILE"
echo "========================================" >> "$SUMMARY_FILE"

# 统计结果类型
echo "" >> "$SUMMARY_FILE"
echo "结果统计:" >> "$SUMMARY_FILE"
timeout_count=$(grep -l "状态: TIMEOUT" "$OUTPUT_DIR"/kissat_output_*.log 2>/dev/null | wc -l)
satisfiable_count=$(grep -l "s SATISFIABLE" "$OUTPUT_DIR"/kissat_output_*.log 2>/dev/null | wc -l)
unsatisfiable_count=$(grep -l "s UNSATISFIABLE" "$OUTPUT_DIR"/kissat_output_*.log 2>/dev/null | wc -l)
unknown_count=$(grep -l "s UNKNOWN" "$OUTPUT_DIR"/kissat_output_*.log 2>/dev/null | wc -l)

echo "TIMEOUT: $timeout_count" >> "$SUMMARY_FILE"
echo "SATISFIABLE: $satisfiable_count" >> "$SUMMARY_FILE"
echo "UNSATISFIABLE: $unsatisfiable_count" >> "$SUMMARY_FILE"
echo "UNKNOWN: $unknown_count" >> "$SUMMARY_FILE"

# 统计回溯日志信息
echo "" >> "$SUMMARY_FILE"
echo "回溯日志统计:" >> "$SUMMARY_FILE"
backtrack_log_files=$(find "$OUTPUT_DIR" -name "backtrack_logs_*.log" 2>/dev/null | wc -l)
echo "回溯日志文件数: $backtrack_log_files" >> "$SUMMARY_FILE"

if [ "$backtrack_log_files" -gt 0 ]; then
    total_conflict_backtracks=$(grep -h "冲突回溯次数:" "$OUTPUT_DIR"/backtrack_logs_*.log 2>/dev/null | awk '{sum += $2} END {print sum+0}')
    total_normal_backtracks=$(grep -h "普通回溯次数:" "$OUTPUT_DIR"/backtrack_logs_*.log 2>/dev/null | awk '{sum += $2} END {print sum+0}')
    total_decision_backtracks=$((total_conflict_backtracks + total_normal_backtracks))
    
    echo "总冲突回溯次数: $total_conflict_backtracks" >> "$SUMMARY_FILE"
    echo "总普通回溯次数: $total_normal_backtracks" >> "$SUMMARY_FILE"
    echo "总决策回溯次数: $total_decision_backtracks" >> "$SUMMARY_FILE"
fi

echo "汇总报告已保存到: $SUMMARY_FILE"
