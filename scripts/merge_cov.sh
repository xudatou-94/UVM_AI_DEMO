#!/bin/bash
#=============================================================================
# merge_cov.sh - 覆盖率合并与报告生成脚本
#
# 功能：
#   1. 扫描指定项目下所有仿真产生的代码覆盖率数据（.vdb）
#   2. 使用 urg 合并代码覆盖率，生成 HTML 报告
#   3. 扫描功能覆盖率数据，使用 verdi/dve 生成功能覆盖率报告
#
# 依赖环境变量：REPO_ROOT, PROJ, OUTPUT_ROOT
# 可选环境变量：COV_TYPES（代码覆盖率类型，默认 line+cond+fsm+tgl+branch）
#
# 基于 Synopsys VCS 2020 / urg
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
COV_TYPES="${COV_TYPES:-line+cond+fsm+tgl+branch}"

#-----------------------------------------------------------------------------
# 路径定义
#-----------------------------------------------------------------------------
PROJ_SIM_DIR="${OUTPUT_ROOT}/${PROJ}/sim"
COV_REPORT_DIR="${OUTPUT_ROOT}/${PROJ}/cov_report"
CODE_COV_REPORT="${COV_REPORT_DIR}/code_cov"
FUNC_COV_REPORT="${COV_REPORT_DIR}/func_cov"

#-----------------------------------------------------------------------------
# 检查仿真输出目录
#-----------------------------------------------------------------------------
if [ ! -d "${PROJ_SIM_DIR}" ]; then
    echo -e "${RED}[ERROR] 仿真输出目录不存在: ${PROJ_SIM_DIR}${NC}"
    echo -e "${YELLOW}[INFO]  请先运行回归: make regress PROJ=${PROJ} CODE_COV=1${NC}"
    exit 1
fi

mkdir -p "${COV_REPORT_DIR}"

#=============================================================================
# 代码覆盖率合并
#=============================================================================
echo -e "${GREEN}[INFO] ===== 开始合并代码覆盖率 =====${NC}"

# 收集所有 .vdb 目录
VDB_LIST=()
while IFS= read -r -d '' vdb; do
    VDB_LIST+=("${vdb}")
done < <(find "${PROJ_SIM_DIR}" -type d -name "*.vdb" -print0 2>/dev/null)

if [ ${#VDB_LIST[@]} -eq 0 ]; then
    echo -e "${YELLOW}[WARN] 未找到任何 .vdb 覆盖率数据${NC}"
    echo -e "${YELLOW}[INFO] 请确认回归时已开启 CODE_COV=1${NC}"
else
    echo -e "[INFO] 找到 ${#VDB_LIST[@]} 个覆盖率数据目录"

    # 构建 urg 命令
    URG_CMD="urg"
    URG_CMD+=" -full64"
    for vdb in "${VDB_LIST[@]}"; do
        URG_CMD+=" -dir ${vdb}"
    done
    URG_CMD+=" -metric ${COV_TYPES}"          # 覆盖率类型
    URG_CMD+=" -format both"                   # 同时生成 HTML 和 text 报告
    URG_CMD+=" -report ${CODE_COV_REPORT}"     # 报告输出目录
    URG_CMD+=" -log ${COV_REPORT_DIR}/urg_merge.log"

    echo -e "${YELLOW}[CMD]${NC} ${URG_CMD}"
    mkdir -p "${CODE_COV_REPORT}"
    eval ${URG_CMD}

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[INFO] 代码覆盖率报告已生成: ${CODE_COV_REPORT}/dashboard.html${NC}"
    else
        echo -e "${RED}[ERROR] urg 合并失败，请查看日志: ${COV_REPORT_DIR}/urg_merge.log${NC}"
        exit 1
    fi
fi

#=============================================================================
# 功能覆盖率合并（verdi -cov 或 dve -cov）
#=============================================================================
echo ""
echo -e "${GREEN}[INFO] ===== 检查功能覆盖率数据 =====${NC}"

# 功能覆盖率通常存储在 .vdb 或独立的 coverage 目录中
# VCS 2020 将功能覆盖率合并进同一 .vdb，urg 可一并处理
# 此处额外生成独立的功能覆盖率 HTML 报告

if [ ${#VDB_LIST[@]} -gt 0 ]; then
    mkdir -p "${FUNC_COV_REPORT}"

    FUNC_URG_CMD="urg"
    FUNC_URG_CMD+=" -full64"
    for vdb in "${VDB_LIST[@]}"; do
        FUNC_URG_CMD+=" -dir ${vdb}"
    done
    FUNC_URG_CMD+=" -metric group"             # 功能覆盖率 (covergroup)
    FUNC_URG_CMD+=" -format both"
    FUNC_URG_CMD+=" -report ${FUNC_COV_REPORT}"
    FUNC_URG_CMD+=" -log ${COV_REPORT_DIR}/urg_func.log"

    echo -e "${YELLOW}[CMD]${NC} ${FUNC_URG_CMD}"
    eval ${FUNC_URG_CMD} 2>/dev/null || \
        echo -e "${YELLOW}[WARN] 功能覆盖率合并不完整，可能无功能覆盖率数据${NC}"

    echo -e "${GREEN}[INFO] 功能覆盖率报告: ${FUNC_COV_REPORT}/dashboard.html${NC}"
fi

#=============================================================================
# 汇总
#=============================================================================
echo ""
echo "============================================================"
echo -e " 覆盖率报告汇总"
echo "============================================================"
[ -f "${CODE_COV_REPORT}/dashboard.html" ] && \
    echo -e " 代码覆盖率: ${CODE_COV_REPORT}/dashboard.html"
[ -f "${FUNC_COV_REPORT}/dashboard.html" ] && \
    echo -e " 功能覆盖率: ${FUNC_COV_REPORT}/dashboard.html"
echo "============================================================"
