#!/bin/bash
#=============================================================================
# vcs_run.sh - VCS 仿真运行脚本
#
# 功能：
#   1. 执行编译生成的 simv 进行仿真
#   2. 支持 UVM 测试选择、随机种子、波形转储
#   3. 支持 case_define（运行时 plusarg）和 case_seq（UVM sequence 注入）
#   4. 支持代码覆盖率（CODE_COV）和功能覆盖率（FUNC_COV）独立开关
#   5. 支持超时控制（CASE_TIMEOUT），防止仿真挂死
#   6. 支持波形转储范围控制（WAVE_SCOPE）
#   7. 仿真结束后写入 result.json 供回归脚本汇总
#   8. 仿真结束后自动打开波形调试工具（AUTO_DEBUG）
#
# 依赖环境变量（由 Makefile 或 run_cases.py 设置）：
#   必填：REPO_ROOT, PROJ, TC, OUTPUT_ROOT
#   可选：
#     SEED          随机种子（默认 random）
#     VERBOSITY     UVM 打印级别（默认 UVM_MEDIUM）
#     WAVE          波形转储开关（默认 1）
#     WAVE_SCOPE    波形转储范围（默认空=全量；指定时如 "tb_top.u_dut"）
#     CODE_COV      代码覆盖率开关（默认 0）
#     FUNC_COV      功能覆盖率开关（默认 0）
#     CASE_TIMEOUT  仿真超时秒数（默认 3600）
#     AUTO_DEBUG    仿真结束后自动打开波形（默认 0）
#     CASE_SEQ      UVM sequence 类名（传递给 TB）
#     CASE_DEFINE   激励自定义 plusarg 列表（空格分隔）
#     CASE_ID       激励唯一 ID（用于日志标记）
#
# 基于 Synopsys VCS 2020
#=============================================================================

set -euo pipefail

#-----------------------------------------------------------------------------
# 颜色定义
#-----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

#-----------------------------------------------------------------------------
# 环境变量默认值
#-----------------------------------------------------------------------------
SEED="${SEED:-random}"
VERBOSITY="${VERBOSITY:-UVM_MEDIUM}"
WAVE="${WAVE:-1}"
WAVE_SCOPE="${WAVE_SCOPE:-}"         # 空=全量转储；非空=仅转储指定层次
CODE_COV="${CODE_COV:-0}"
FUNC_COV="${FUNC_COV:-0}"
CASE_TIMEOUT="${CASE_TIMEOUT:-3600}" # 默认超时 1 小时
AUTO_DEBUG="${AUTO_DEBUG:-0}"
CASE_SEQ="${CASE_SEQ:-}"
CASE_DEFINE="${CASE_DEFINE:-}"
CASE_ID="${CASE_ID:-}"

#-----------------------------------------------------------------------------
# 路径定义
#-----------------------------------------------------------------------------
COMPILE_DIR="${OUTPUT_ROOT}/${PROJ}/compile"
SIMV="${COMPILE_DIR}/simv"

#-----------------------------------------------------------------------------
# 检查 simv 是否存在
#-----------------------------------------------------------------------------
if [ ! -f "${SIMV}" ]; then
    echo -e "${RED}[ERROR] simv 不存在: ${SIMV}${NC}"
    echo -e "${YELLOW}[INFO]  请先运行 make compile PROJ=${PROJ}${NC}"
    exit 1
fi

#-----------------------------------------------------------------------------
# 处理随机种子：计算 SEED_DIR 用于路径拼接，SEED 保持原值传给 simv
#-----------------------------------------------------------------------------
if [ "${SEED}" = "random" ]; then
    SEED_DIR=$(tr -dc '0-9' < /dev/urandom | head -c 9 | sed 's/^0*//')
    SEED_DIR="${SEED_DIR:-1}"   # 防止全为 0 时变成空字符串
else
    SEED_DIR="${SEED}"
fi

#-----------------------------------------------------------------------------
# 仿真输出目录（按 测试名_种子 隔离，每次运行结果独立存放）
#-----------------------------------------------------------------------------
SIM_DIR="${OUTPUT_ROOT}/${PROJ}/sim/${TC}_${SEED_DIR}"
SIM_LOG="${SIM_DIR}/${TC}.log"
FSDB_FILE="${SIM_DIR}/${TC}.fsdb"
RESULT_JSON="${SIM_DIR}/result.json"

mkdir -p "${SIM_DIR}"

#-----------------------------------------------------------------------------
# 记录开始时间
#-----------------------------------------------------------------------------
START_TS=$(date +%s)

#-----------------------------------------------------------------------------
# 打印运行信息
#-----------------------------------------------------------------------------
echo -e "${GREEN}[INFO] ===== 开始仿真 =====${NC}"
echo -e "[INFO] 项目:     ${PROJ}"
echo -e "[INFO] 测试:     ${TC}"
echo -e "[INFO] 种子:     ${SEED_DIR}"
echo -e "[INFO] 超时:     ${CASE_TIMEOUT}s"
[ -n "${CASE_ID}"     ] && echo -e "[INFO] Case ID:  ${CASE_ID}"
[ -n "${CASE_SEQ}"    ] && echo -e "[INFO] Seq:      ${CASE_SEQ}"
[ -n "${WAVE_SCOPE}"  ] && echo -e "[INFO] 波形范围: ${WAVE_SCOPE}"
echo -e "[INFO] 覆盖率:   代码=${CODE_COV}  功能=${FUNC_COV}"

#-----------------------------------------------------------------------------
# 构建仿真命令
#-----------------------------------------------------------------------------
SIM_CMD="${SIMV}"

# UVM 基本参数
SIM_CMD+=" +UVM_TESTNAME=${TC}"                  # UVM 测试类名
SIM_CMD+=" +UVM_VERBOSITY=${VERBOSITY}"          # UVM 打印级别
SIM_CMD+=" +ntb_random_seed=${SEED}"             # 随机种子
SIM_CMD+=" -l ${SIM_LOG}"                        # 仿真日志

# 传递 UVM sequence 类名（由 TB 通过 plusarg 读取）
if [ -n "${CASE_SEQ}" ]; then
    SIM_CMD+=" +UVM_SEQ=${CASE_SEQ}"
fi

# 传递激励自定义 plusarg（case_define 中的每个条目）
if [ -n "${CASE_DEFINE}" ]; then
    for define_arg in ${CASE_DEFINE}; do
        SIM_CMD+=" ${define_arg}"
    done
fi

# 波形转储（FSDB 格式，供 Verdi 使用）
if [ "${WAVE}" = "1" ]; then
    SIM_CMD+=" +fsdbfile+${FSDB_FILE}"           # FSDB 输出路径
    SIM_CMD+=" +fsdb+autoflush"                  # 自动刷新，防止异常退出丢失波形
    SIM_CMD+=" +DUMP_WAVE"                       # 通知 TB 执行 fsdbDumpvars
    # 波形转储范围：空=全量，非空=指定层次
    if [ -n "${WAVE_SCOPE}" ]; then
        SIM_CMD+=" +WAVE_SCOPE=${WAVE_SCOPE}"
    fi
fi

# 代码覆盖率（line/condition/fsm/toggle/branch）
if [ "${CODE_COV}" = "1" ]; then
    SIM_CMD+=" -cm line+cond+fsm+tgl+branch"     # 覆盖率收集类型
    SIM_CMD+=" -cm_dir ${SIM_DIR}/code_cov.vdb"  # 覆盖率数据存储目录
    SIM_CMD+=" -cm_name ${TC}_${SEED}"           # 覆盖率实例名（用于合并）
fi

# 功能覆盖率（通知 TB 开启 UVM covergroup 采样）
if [ "${FUNC_COV}" = "1" ]; then
    SIM_CMD+=" +FUNC_COV"                        # TB 通过此 plusarg 使能 covergroup
fi

#-----------------------------------------------------------------------------
# 打印仿真命令
#-----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[CMD]${NC} timeout ${CASE_TIMEOUT} ${SIM_CMD}"
echo ""

#-----------------------------------------------------------------------------
# 切换到仿真目录并执行（用 timeout 包裹防止挂死）
#-----------------------------------------------------------------------------
cd "${SIM_DIR}"
timeout "${CASE_TIMEOUT}" bash -c "${SIM_CMD}" || true
SIM_EXIT=$?

#-----------------------------------------------------------------------------
# 计算仿真耗时
#-----------------------------------------------------------------------------
END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))

#-----------------------------------------------------------------------------
# 超时检测（timeout 返回 124）
#-----------------------------------------------------------------------------
TIMED_OUT=0
if [ "${SIM_EXIT}" -eq 124 ]; then
    TIMED_OUT=1
    echo -e "${RED}[ERROR] 仿真超时（>${CASE_TIMEOUT}s），已强制终止${NC}"
fi

#-----------------------------------------------------------------------------
# 仿真结果判定（扫描 UVM 报告行）
#-----------------------------------------------------------------------------
echo ""
echo "============================================================"

UVM_FATAL=0
UVM_ERROR=0

if [ -f "${SIM_LOG}" ]; then
    UVM_FATAL=$(grep -c "UVM_FATAL" "${SIM_LOG}" 2>/dev/null || true)
    UVM_ERROR=$(grep -c "UVM_ERROR" "${SIM_LOG}" 2>/dev/null || true)
else
    echo -e "${RED}[FAIL] 仿真日志不存在，仿真可能异常退出${NC}"
fi

PASSED=0
if [ "${SIM_EXIT}" -eq 0 ] && [ "${UVM_FATAL}" = "0" ] && \
   [ "${UVM_ERROR}" = "0" ] && [ "${TIMED_OUT}" = "0" ]; then
    PASSED=1
    echo -e "${GREEN}[PASS] 仿真通过${NC}"
else
    echo -e "${RED}[FAIL] 仿真失败${NC}"
    [ "${TIMED_OUT}" = "1" ] && echo -e "${RED}[INFO] 原因: 超时${NC}"
    echo -e "${RED}[INFO] UVM_FATAL: ${UVM_FATAL}  UVM_ERROR: ${UVM_ERROR}${NC}"
fi

echo -e "[INFO] 测试: ${TC}  种子: ${SEED_DIR}  耗时: ${DURATION}s"
[ -n "${CASE_ID}" ] && echo -e "[INFO] Case ID: ${CASE_ID}"
echo -e "[INFO] 仿真日志: ${SIM_LOG}"
if [ "${WAVE}" = "1" ] && [ -f "${FSDB_FILE}" ]; then
    echo -e "[INFO] 波形文件: ${FSDB_FILE}"
fi
echo "============================================================"

#-----------------------------------------------------------------------------
# 写入 result.json（供 run_cases.py 汇总使用）
#-----------------------------------------------------------------------------
python3 - <<EOF
import json, datetime
result = {
    "case_id":   "${CASE_ID}",
    "case_name": "${TC}",
    "seed":      ${SEED_DIR},
    "passed":    ${PASSED} == 1,
    "uvm_fatal": ${UVM_FATAL},
    "uvm_error": ${UVM_ERROR},
    "timed_out": ${TIMED_OUT} == 1,
    "duration":  ${DURATION},
    "log":       "${SIM_LOG}",
    "fsdb":      "${FSDB_FILE}" if "${WAVE}" == "1" else "",
    "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
}
with open("${RESULT_JSON}", "w") as f:
    json.dump(result, f, indent=2)
EOF

#-----------------------------------------------------------------------------
# 自动打开波形调试工具（AUTO_DEBUG=1 且 WAVE=1 时触发）
#-----------------------------------------------------------------------------
if [ "${AUTO_DEBUG}" = "1" ]; then
    if [ "${WAVE}" != "1" ]; then
        echo -e "${YELLOW}[WARN] AUTO_DEBUG=1 但 WAVE=0，跳过自动打开波形${NC}"
    elif [ ! -f "${FSDB_FILE}" ]; then
        echo -e "${YELLOW}[WARN] FSDB 文件不存在，跳过自动打开波形${NC}"
    else
        echo -e "${GREEN}[INFO] 自动打开波形调试工具...${NC}"
        bash "${REPO_ROOT}/scripts/vcs_debug.sh"
    fi
fi

exit ${SIM_EXIT}
