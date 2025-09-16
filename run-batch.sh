#!/usr/bin/env bash
set -euo pipefail

# Unified batch runner for kissat-RS
# Features:
#  - MODE=vsids | mix (default vsids)
#  - Single pass AWK parsing of solver stdout capturing:
#       * [LBD] conflict= learned= glue= size=
#       * [BACKTRACK] type=conflict from= to= time= conflicts=
#  - Produces:
#       OUTPUT_DIR/solver_logs/*.log          (filtered human readable)
#       OUTPUT_DIR/lbd_csv/lbd_<file>.csv     (appended per instance)
#       OUTPUT_DIR/backtrack_logs/backtrack_<file>.log  (detail + summary)
#       OUTPUT_DIR/summary/summary.txt & summary.csv (aggregated after run)
#  - Loop support (LOOP_COUNT) though default is 1
#  - Parallel execution capped to CPU cores (or J override)
#
# ===================== 配置区（直接修改这里的值） =====================
# MODE: 运行模式 vsids 或 mix
MODE=vsids

# CNF_DIR: CNF 文件目录（绝对路径或相对路径）
CNF_DIR="/mnt/SAT/2021CNF"

# 输出基目录：所有结果会写入  <OUTPUT_DIR>/<模式>_runs_<时间戳>/
OUTPUT_DIR="/mnt/fix-paper/kissat"

# Kissat 可执行文件路径
KISSAT_PATH="/mnt/fix-paper/kissat/build/kissat"

# 每轮最多处理的 CNF 文件数
TOTAL_FILES=400

# 循环次数（>1 时会多轮重新读取文件列表）
LOOP_COUNT=1

# 是否自动计算并行数：AUTO_J=true/false
AUTO_J=true
# 若 AUTO_J=true, 预留给系统的核心数量
J_RESERVED=2
# 若 AUTO_J=false，则使用下面手动指定并行任务数
J=32

# 单实例超时时间（秒）
TIME_LIMIT=3600

# 额外附加给求解器的参数（可为空）。例如：EXTRA="--restart=0 --chrono=0"
EXTRA=""
# =================== 配置区结束（下面逻辑一般不需要改） ===================

# 自动并行计算
if [ "$AUTO_J" = true ]; then
  _all_cores=$( (command -v nproc >/dev/null 2>&1 && nproc) || sysctl -n hw.ncpu ) || _all_cores=1
  _tmp=$((_all_cores - J_RESERVED))
  if [ $_tmp -lt 1 ]; then _tmp=1; fi
  J=$_tmp
fi

if [ ! -x "$KISSAT_PATH" ]; then
  echo "[ERROR] Solver not executable: $KISSAT_PATH" >&2
  exit 1
fi

case "$MODE" in
  vsids)  MODE_TAG="no_mix"; EXTRA_PARAMS="--stable=2 --randec=0 --randecstable=0" ;;
  mix)    MODE_TAG="mix";    EXTRA_PARAMS="" ;;
  *) echo "[ERROR] Unknown MODE=$MODE (expected vsids|mix)" >&2; exit 1;;
endcase

TS=$(date +"%Y%m%d-%H%M%S")
BASE_DIR="$OUTPUT_DIR/${MODE_TAG}_runs_$TS"
SOLVER_LOG_DIR="$BASE_DIR/solver_logs"
BACKTRACK_LOG_DIR="$BASE_DIR/backtrack_logs"
LBD_DIR="$BASE_DIR/lbd_csv"
SUMMARY_DIR="$BASE_DIR/summary"
mkdir -p "$SOLVER_LOG_DIR" "$BACKTRACK_LOG_DIR" "$LBD_DIR" "$SUMMARY_DIR"

echo "[INFO] MODE=$MODE  EXTRA_PARAMS='$EXTRA_PARAMS'  EXTRA='$EXTRA'"
echo "[INFO] Output base: $BASE_DIR"
echo "[INFO] Parallel jobs (J) = $J (AUTO_J=$AUTO_J reserved=$J_RESERVED)"

tmp_list() {
  mktemp "/tmp/kissat_cnf_list.XXXXXX"
}

process_file() {
  local loop_num="$1"; shift
  local cnf_rel="$1"
  local cnf_abs
  cnf_abs=$(readlink -f "$cnf_rel" 2>/dev/null || realpath "$cnf_rel" 2>/dev/null || echo "$cnf_rel")
  local filename
  filename=$(basename "$cnf_abs")

  local raw_tmp
  raw_tmp=$(mktemp)
  local filtered_log="$SOLVER_LOG_DIR/kissat_output_${loop_num}_${filename}_$$.log"
  local backtrack_log="$BACKTRACK_LOG_DIR/backtrack_${loop_num}_${filename}_$$.log"
  local lbd_csv="$LBD_DIR/lbd_${filename}.csv"

  # Header for human log
  {
    echo "========================================"
    echo "CNF文件: $cnf_abs"
    echo "开始时间: $(date)"
    echo "========================================"
  } > "$filtered_log"

  # Ensure LBD CSV header exists
  if [ ! -f "$lbd_csv" ]; then
    echo "instance,loop,conflict,learned_index,lbd,size" > "$lbd_csv"
  fi

  # Single run capture + single pass parse using awk
  # We duplicate stream: raw to temp (for safety) and piped into awk for extraction & filtered output assembly.
  timeout -s SIGTERM "$TIME_LIMIT" "$KISSAT_PATH" --log=1 $EXTRA_PARAMS $EXTRA "$cnf_abs" \
    | tee "$raw_tmp" \
    | awk -v inst="$filename" -v loop="$loop_num" -v lbdcsv="$lbd_csv" -v btlog="$backtrack_log.tmp" '
      BEGIN { in_solving=0; conflict_bt=0; normal_bt=0; }
      # Filter sections for human readable solver log (outside solving region) handled later
      {
        full_line=$0
      }
      /^c ---- \[ solving \] / { in_solving=1; print full_line >>"'"$filtered_log"'"; next }
      /^c ---- \[ result \] /  { in_solving=0; next }
      !in_solving { print full_line >>"'"$filtered_log"'" }

      # New LBD unified format
      /^\[LBD]/ {
        conflict=""; learned=""; glue=""; sz="";
        for (i=1;i<=NF;i++) {
          if ($i ~ /^conflict=/) { split($i,a,"="); conflict=a[2]; }
          else if ($i ~ /^learned=/) { split($i,a,"="); learned=a[2]; }
          else if ($i ~ /^glue=/) { split($i,a,"="); glue=a[2]; }
          else if ($i ~ /^size=/) { split($i,a,"="); sz=a[2]; }
        }
        if (glue!="") {
          if (conflict=="") conflict=-1; if (learned=="") learned=-1; if (sz=="") sz=-1;
          printf "%s,%s,%s,%s,%s,%s\n", inst, loop, conflict, learned, glue, sz >> lbdcsv;
        }
        next;
      }

      # Backtrack unified format only
      /^\[BACKTRACK]/ {
        # example: [BACKTRACK] type=conflict from=10 to=7 time=123.456 conflicts=9999
        bt_type=""; from=""; to=""; bt_conflicts=""; for (i=1;i<=NF;i++) {
          if ($i ~ /^type=/) { split($i,a,"="); bt_type=a[2]; }
          else if ($i ~ /^from=/) { split($i,a,"="); from=a[2]; }
          else if ($i ~ /^to=/) { split($i,a,"="); to=a[2]; }
          else if ($i ~ /^conflicts=/) { split($i,a,"="); bt_conflicts=a[2]; }
        }
        if (bt_type=="conflict") conflict_bt++;
        else if (bt_type=="normal") normal_bt++;
        print full_line >> btlog;
        next;
      }

      END {
        # Write summary footer for backtrack log if any entries
        if ((conflict_bt+normal_bt) > 0) {
          print "========================================" >> btlog;
          print "回溯统计信息:" >> btlog;
          print "冲突回溯次数: " conflict_bt >> btlog;
            print "普通回溯次数: " normal_bt >> btlog;
          print "总决策回溯次数: " (conflict_bt+normal_bt) >> btlog;
        }
      }
    '
  exit_code=$?

  # Finalize backtrack log (add header + tail info)
  {
    echo "========================================"
    echo "CNF文件: $cnf_abs"
    echo "开始时间: (见 solver 日志头)"
    echo "BACKTRACK_LOG 详细信息:"
    echo "========================================"
    if [ -f "$backtrack_log.tmp" ]; then
      cat "$backtrack_log.tmp"
    fi
    echo "结束时间: $(date)"
    echo "========================================"
  } > "$backtrack_log"
  rm -f "$backtrack_log.tmp"

  # Append end of solver filtered log
  {
    echo
    echo "========================================"
    echo "结束时间: $(date)"
    if [ $exit_code -eq 124 ]; then
      echo "状态: TIMEOUT (${TIME_LIMIT}秒)"
    else
      echo "退出码: $exit_code"
    fi
    echo "文件处理完成: $cnf_abs"
    echo "========================================"
    echo
  } >> "$filtered_log"

  rm -f "$raw_tmp"
}

export -f process_file
export MODE MODE_TAG EXTRA_PARAMS EXTRA KISSAT_PATH SOLVER_LOG_DIR BACKTRACK_LOG_DIR LBD_DIR TIME_LIMIT

for ((loop=1; loop<=LOOP_COUNT; loop++)); do
  echo "========== LOOP $loop / $LOOP_COUNT =========="
  list_file=$(tmp_list)
  (cd "$CNF_DIR" && find . -name '*.cnf' | head -n "$TOTAL_FILES") > "$list_file"
  if [ ! -s "$list_file" ]; then
    echo "[WARN] No CNF files found in $CNF_DIR"
    continue
  fi
  echo "[INFO] Loop $loop: $(wc -l < "$list_file") files"
  # Parallel execution
  cat "$list_file" | xargs -P "$J" -I {} bash -c 'process_file "$0" "$1"' "$loop" {} || true
  rm -f "$list_file"
  echo "[INFO] Loop $loop finished"
 done

# Aggregate summary
SUMMARY_TXT="$SUMMARY_DIR/summary.txt"
SUMMARY_CSV="$SUMMARY_DIR/summary.csv"
{
  echo "处理汇总报告"
  echo "生成时间: $(date)"
  echo "MODE: $MODE"
  echo "根目录: $BASE_DIR"
  echo "========================================"
  echo "求解器日志数: $(find "$SOLVER_LOG_DIR" -name 'kissat_output_*.log' | wc -l)"
  echo "LBD CSV 数: $(find "$LBD_DIR" -name 'lbd_*.csv' | wc -l)"
  echo "回溯日志数: $(find "$BACKTRACK_LOG_DIR" -name 'backtrack_*.log' | wc -l)"
} > "$SUMMARY_TXT"

# Simple CSV aggregation of last line per LBD file (as example)
echo "file,rows" > "$SUMMARY_CSV"
for f in "$LBD_DIR"/lbd_*.csv; do
  [ -f "$f" ] || continue
  rows=$(($(wc -l < "$f")-1))
  echo "$(basename "$f"),$rows" >> "$SUMMARY_CSV"
 done

echo "[INFO] Summary generated: $SUMMARY_TXT"
echo "[INFO] CSV summary: $SUMMARY_CSV"

