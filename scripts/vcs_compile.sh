#!/bin/bash
#=============================================================================
# vcs_compile.sh - VCS 编译脚本
#
# 功能：
#   1. 读取合并后的文件列表（由 find_flist.sh 生成）
#   2. 根据配置选项构建 VCS 编译命令
#   3. 执行编译并检查结果
#
# 依赖环境变量：REPO_ROOT, PROJ, WAVE, COV, OUTPUT_ROOT
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
# 路径定义
#-----------------------------------------------------------------------------
COMPILE_DIR="${OUTPUT_ROOT}/${PROJ}/compile"
MERGED_FLIST="${COMPILE_DIR}/merged.flist"
COMPILE_LOG="${COMPILE_DIR}/vcs_compile.log"
SIMV="${COMPILE_DIR}/simv"

#-----------------------------------------------------------------------------
# 检查合并后的文件列表是否存在
#-----------------------------------------------------------------------------
if [ ! -f "${MERGED_FLIST}" ]; then
    echo -e "${RED}[ERROR] 合并文件列表不存在: ${MERGED_FLIST}${NC}"
    echo -e "${YELLOW}[INFO]  请先运行 find_flist.sh 或 make compile${NC}"
    exit 1
fi

#-----------------------------------------------------------------------------
# 构建 VCS 编译命令
#-----------------------------------------------------------------------------
echo -e "${GREEN}[INFO] ===== 开始编译项目: ${PROJ} =====${NC}"

VCS_CMD="vcs"
VCS_CMD+=" -full64"                              # 64 位模式
VCS_CMD+=" -sverilog"                            # 支持 SystemVerilog
VCS_CMD+=" +v2k"                                 # Verilog-2001 兼容
VCS_CMD+=" -ntb_opts uvm-1.2"                    # 使用 VCS 内置 UVM 1.2
VCS_CMD+=" -timescale=1ns/1ps"                   # 默认时间精度
VCS_CMD+=" +define+UVM_NO_DEPRECATED"            # 屏蔽 UVM 弃用警告
VCS_CMD+=" +define+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR"
VCS_CMD+=" -f ${MERGED_FLIST}"                   # 合并后的文件列表
VCS_CMD+=" +incdir+${REPO_ROOT}/vip"             # VIP 目录加入搜索路径
VCS_CMD+=" -l ${COMPILE_LOG}"                    # 编译日志
VCS_CMD+=" -o ${SIMV}"                           # 输出 simv 路径
VCS_CMD+=" -Mdir=${COMPILE_DIR}/csrc"            # 中间文件目录

# 波形调试支持
if [ "${WAVE}" = "1" ]; then
    VCS_CMD+=" -debug_access+all"                # 完整调试权限（FSDB/Verdi）
    VCS_CMD+=" -lca"                             # 启用增强功能
    VCS_CMD+=" -kdb"                             # Verdi KDB 数据库支持
else
    VCS_CMD+=" -debug_access+pp"                 # 仅后处理调试
fi

# 覆盖率收集
if [ "${COV}" = "1" ]; then
    VCS_CMD+=" -cm line+cond+fsm+tgl+branch"     # 覆盖率类型
    VCS_CMD+=" -cm_dir ${COMPILE_DIR}/coverage"   # 覆盖率数据目录
fi

#-----------------------------------------------------------------------------
# 打印编译命令（便于调试）
#-----------------------------------------------------------------------------
echo -e "${YELLOW}[CMD]${NC} ${VCS_CMD}"
echo ""

#-----------------------------------------------------------------------------
# 执行编译
#-----------------------------------------------------------------------------
mkdir -p "${COMPILE_DIR}"

eval ${VCS_CMD}
VCS_EXIT=$?

#-----------------------------------------------------------------------------
# 检查编译结果
#-----------------------------------------------------------------------------
if [ ${VCS_EXIT} -eq 0 ] && [ -f "${SIMV}" ]; then
    echo ""
    echo -e "${GREEN}[INFO] ===== 编译成功 =====${NC}"
    echo -e "${GREEN}[INFO] simv 路径: ${SIMV}${NC}"
    echo -e "${GREEN}[INFO] 编译日志: ${COMPILE_LOG}${NC}"
else
    echo ""
    echo -e "${RED}[ERROR] ===== 编译失败 =====${NC}"
    echo -e "${RED}[ERROR] 请查看编译日志: ${COMPILE_LOG}${NC}"
    exit 1
fi
