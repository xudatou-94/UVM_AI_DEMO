#!/bin/bash
#=============================================================================
# vcs_run.sh - VCS 仿真运行脚本
#
# 功能：
#   1. 执行编译生成的 simv 进行仿真
#   2. 支持 UVM 测试选择、随机种子、波形转储
#   3. 支持 case_define（运行时 plusarg）和 case_seq（UVM sequence 注入）
#   4. 支持代码覆盖率（CODE_COV）和功能覆盖率（FUNC_COV）独立开关
#   5. 仿真结束后自动检测 PASS/FAIL
#
# 依赖环境变量（由 Makefile 或 run_cases.py 设置）：
#   必填：REPO_ROOT, PROJ, TC, OUTPUT_ROOT
#   可选：SEED        随机种子（默认 random）
#         VERBOSITY   UVM 打印级别（默认 UVM_MEDIUM）
#         WAVE        波形转储开关（默认 1）
#         CODE_COV    代码覆盖率开关（默认 0）
#         FUNC_COV    功能覆盖率开关（默认 0）
#         CASE_SEQ    UVM sequence 类名（传递给 TB）
#         CASE_DEFINE 激励自定义 plusarg 列表（空格分隔）
#         CASE_ID     激励唯一 ID（用于日志标记）
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
CODE_COV="${CODE_COV:-0}"
FUNC_COV="${FUNC_COV:-0}"
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
# 处理随机种子
#-----------------------------------------------------------------------------
if [ "${SEED}" = "random" ]; then
    SEED=$((RANDOM * RANDOM))
fi

#-----------------------------------------------------------------------------
# 仿真输出目录（按 测试名_种子 隔离，每次运行结果独立存放）
#-----------------------------------------------------------------------------
SIM_DIR="${OUTPUT_ROOT}/${PROJ}/sim/${TC}_${SEED}"
SIM_LOG="${SIM_DIR}/${TC}.log"
FSDB_FILE="${SIM_DIR}/${TC}.fsdb"

mkdir -p "${SIM_DIR}"

#-----------------------------------------------------------------------------
# 打印运行信息
#-----------------------------------------------------------------------------
echo -e "${GREEN}[INFO] ===== 开始仿真 =====${NC}"
echo -e "[INFO] 项目:    ${PROJ}"
echo -e "[INFO] 测试:    ${TC}"
echo -e "[INFO] 种子:    ${SEED}"
[ -n "${CASE_ID}"  ] && echo -e "[INFO] Case ID: ${CASE_ID}"
[ -n "${CASE_SEQ}" ] && echo -e "[INFO] Seq:     ${CASE_SEQ}"
echo -e "[INFO] 代码覆盖率: ${CODE_COV}  功能覆盖率: ${FUNC_COV}"

#-----------------------------------------------------------------------------
# 构建仿真命令
#-----------------------------------------------------------------------------
SIM_CMD="${SIMV}"

# UVM 基本参数
SIM_CMD+=" +UVM_TESTNAME=${TC}"                  # UVM 测试类名
SIM_CMD+=" +UVM_VERBOSITY=${VERBOSITY}"          # UVM 打印级别
SIM_CMD+=" +ntb_random_seed=${SEED}"             # 随机种子
SIM_CMD+=" -l ${SIM_LOG}"                        # 仿真日志

# 传递 UVM sequence 类名（由 TB 通过 plusarg 读取并注册）
if [ -n "${CASE_SEQ}" ]; then
    SIM_CMD+=" +UVM_SEQ=${CASE_SEQ}"
fi

# 传递激励自定义 plusarg（case_define 字段中的每个条目）
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
fi

# 代码覆盖率（line/condition/fsm/toggle/branch）
if [ "${CODE_COV}" = "1" ]; then
    SIM_CMD+=" -cm line+cond+fsm+tgl+branch"     # 覆盖率收集类型
    SIM_CMD+=" -cm_dir ${SIM_DIR}/code_cov"      # 覆盖率数据存储目录
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
echo -e "${YELLOW}[CMD]${NC} ${SIM_CMD}"
echo ""

#-----------------------------------------------------------------------------
# 切换到仿真目录并执行（确保相对路径一致性）
#-----------------------------------------------------------------------------
cd "${SIM_DIR}"
eval ${SIM_CMD}
SIM_EXIT=$?

#-----------------------------------------------------------------------------
# 仿真结果判定（扫描 UVM 报告行）
#-----------------------------------------------------------------------------
echo ""
echo "============================================================"

if [ ! -f "${SIM_LOG}" ]; then
    echo -e "${RED}[FAIL] 仿真日志不存在，仿真可能异常退出${NC}"
    exit 1
fi

# 提取 UVM 报告：UVM_FATAL / UVM_ERROR 出现次数
UVM_FATAL=$(grep -c "UVM_FATAL" "${SIM_LOG}" 2>/dev/null || true)
UVM_ERROR=$(grep -c "UVM_ERROR" "${SIM_LOG}" 2>/dev/null || true)

if [ "${SIM_EXIT}" -eq 0 ] && [ "${UVM_FATAL}" = "0" ] && [ "${UVM_ERROR}" = "0" ]; then
    echo -e "${GREEN}[PASS] 仿真通过${NC}"
else
    echo -e "${RED}[FAIL] 仿真失败${NC}"
    echo -e "${RED}[INFO] UVM_FATAL: ${UVM_FATAL}  UVM_ERROR: ${UVM_ERROR}${NC}"
fi

echo -e "[INFO] 测试: ${TC}  种子: ${SEED}"
[ -n "${CASE_ID}" ] && echo -e "[INFO] Case ID: ${CASE_ID}"
echo -e "[INFO] 仿真日志: ${SIM_LOG}"

if [ "${WAVE}" = "1" ] && [ -f "${FSDB_FILE}" ]; then
    echo -e "[INFO] 波形文件: ${FSDB_FILE}"
fi

echo "============================================================"

exit ${SIM_EXIT}
