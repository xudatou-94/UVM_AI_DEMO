#!/bin/bash
#=============================================================================
# vcs_debug.sh - 波形调试脚本
#
# 功能：
#   1. 自动查找指定项目/测试的 FSDB 波形文件
#   2. 优先使用 Verdi，备选 DVE
#   3. 支持 GUI 模式打开波形
#
# 依赖环境变量：REPO_ROOT, PROJ, TC, SEED, OUTPUT_ROOT
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
# 查找波形文件
# 策略：
#   1. 如果指定了 SEED，精确匹配 sim/${TC}_${SEED}/ 目录
#   2. 如果 SEED=random，查找最新的匹配 TC 的 FSDB 文件
#-----------------------------------------------------------------------------
SIM_BASE="${OUTPUT_ROOT}/${PROJ}/sim"

if [ ! -d "${SIM_BASE}" ]; then
    echo -e "${RED}[ERROR] 仿真输出目录不存在: ${SIM_BASE}${NC}"
    echo -e "${YELLOW}[INFO]  请先运行仿真: make run PROJ=${PROJ} TC=${TC}${NC}"
    exit 1
fi

FSDB_FILE=""

if [ "${SEED}" != "random" ]; then
    # 精确匹配指定种子的波形文件
    FSDB_FILE="${SIM_BASE}/${TC}_${SEED}/${TC}.fsdb"
fi

# 如果未找到，搜索最新的匹配波形
if [ -z "${FSDB_FILE}" ] || [ ! -f "${FSDB_FILE}" ]; then
    FSDB_FILE=$(find "${SIM_BASE}" -name "${TC}.fsdb" -type f 2>/dev/null \
                | xargs ls -t 2>/dev/null \
                | head -1)
fi

if [ -z "${FSDB_FILE}" ] || [ ! -f "${FSDB_FILE}" ]; then
    echo -e "${RED}[ERROR] 未找到波形文件${NC}"
    echo -e "${YELLOW}[INFO]  请确认已运行仿真并开启 WAVE=1:${NC}"
    echo -e "${YELLOW}        make run PROJ=${PROJ} TC=${TC} WAVE=1${NC}"
    exit 1
fi

echo -e "${GREEN}[INFO] 波形文件: ${FSDB_FILE}${NC}"

#-----------------------------------------------------------------------------
# 获取文件列表（用于源码关联）
#-----------------------------------------------------------------------------
VERIF_DIR="${REPO_ROOT}/verif/${PROJ}"
DUT_FLIST="${VERIF_DIR}/dut.flist"
TB_FLIST="${VERIF_DIR}/tb.flist"
MERGED_FLIST="${OUTPUT_ROOT}/${PROJ}/compile/merged.flist"

# 构建文件列表参数
FLIST_ARGS=""
if [ -f "${MERGED_FLIST}" ]; then
    FLIST_ARGS="-f ${MERGED_FLIST}"
elif [ -f "${DUT_FLIST}" ]; then
    FLIST_ARGS="-f ${DUT_FLIST}"
    if [ -f "${TB_FLIST}" ]; then
        FLIST_ARGS+=" -f ${TB_FLIST}"
    fi
fi

#-----------------------------------------------------------------------------
# 选择调试工具：优先 Verdi，备选 DVE
#-----------------------------------------------------------------------------
if command -v verdi &> /dev/null; then
    echo -e "${GREEN}[INFO] 使用 Verdi 打开波形${NC}"

    VERDI_CMD="verdi"
    VERDI_CMD+=" -sv"                            # SystemVerilog 模式
    VERDI_CMD+=" -nologo"                        # 不显示启动画面
    VERDI_CMD+=" ${FLIST_ARGS}"                  # 源码文件列表
    VERDI_CMD+=" -ssf ${FSDB_FILE}"              # 加载 FSDB 波形

    echo -e "${YELLOW}[CMD]${NC} ${VERDI_CMD}"
    eval ${VERDI_CMD} &

elif command -v dve &> /dev/null; then
    echo -e "${GREEN}[INFO] 使用 DVE 打开波形${NC}"

    DVE_CMD="dve"
    DVE_CMD+=" -full64"                          # 64 位模式
    DVE_CMD+=" ${FLIST_ARGS}"                    # 源码文件列表
    DVE_CMD+=" -vpd ${FSDB_FILE}"                # 加载波形文件

    echo -e "${YELLOW}[CMD]${NC} ${DVE_CMD}"
    eval ${DVE_CMD} &

else
    echo -e "${RED}[ERROR] 未找到 Verdi 或 DVE，请检查 EDA 工具安装${NC}"
    exit 1
fi

echo -e "${GREEN}[INFO] 调试工具已在后台启动${NC}"
