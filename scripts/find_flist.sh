#!/bin/bash
#=============================================================================
# find_flist.sh - 自动扫描验证项目的 dut.flist 文件
#
# 功能：
#   1. 在 verif/${PROJ}/ 目录下查找 dut.flist
#   2. 验证文件存在性
#   3. 解析文件列表中的路径变量（如 ${REPO_ROOT}）
#   4. 生成合并后的文件列表供 VCS 编译使用
#
# 依赖环境变量：REPO_ROOT, PROJ, OUTPUT_ROOT
#=============================================================================

set -euo pipefail

#-----------------------------------------------------------------------------
# 颜色定义（用于终端输出）
#-----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 恢复默认

#-----------------------------------------------------------------------------
# 检查必要的环境变量
#-----------------------------------------------------------------------------
if [ -z "${REPO_ROOT:-}" ]; then
    echo -e "${RED}[ERROR] REPO_ROOT 未设置${NC}"
    exit 1
fi

if [ -z "${PROJ:-}" ]; then
    echo -e "${RED}[ERROR] PROJ 未设置${NC}"
    exit 1
fi

#-----------------------------------------------------------------------------
# 路径定义
#-----------------------------------------------------------------------------
VERIF_DIR="${REPO_ROOT}/verif"
PROJ_DIR="${VERIF_DIR}/${PROJ}"
DUT_FLIST="${PROJ_DIR}/dut.flist"
OUTPUT_DIR="${OUTPUT_ROOT}/${PROJ}/compile"

#-----------------------------------------------------------------------------
# 检查项目目录和 dut.flist 是否存在
#-----------------------------------------------------------------------------
if [ ! -d "${PROJ_DIR}" ]; then
    echo -e "${RED}[ERROR] 项目目录不存在: ${PROJ_DIR}${NC}"
    echo -e "${YELLOW}[INFO]  当前可用的项目:${NC}"
    # 列出 verif/ 下所有包含 dut.flist 的子目录
    if [ -d "${VERIF_DIR}" ]; then
        find "${VERIF_DIR}" -name "dut.flist" -type f 2>/dev/null | while read -r f; do
            dirname "$f" | sed "s|${VERIF_DIR}/||"
        done
    else
        echo "  (verif/ 目录不存在)"
    fi
    exit 1
fi

if [ ! -f "${DUT_FLIST}" ]; then
    echo -e "${RED}[ERROR] dut.flist 不存在: ${DUT_FLIST}${NC}"
    echo -e "${YELLOW}[INFO]  请在项目目录下创建 dut.flist 文件，格式示例:${NC}"
    echo ""
    echo "  // DUT RTL 文件列表"
    echo "  +incdir+\${REPO_ROOT}/design/example/rtl"
    echo "  \${REPO_ROOT}/design/example/rtl/example.sv"
    echo ""
    exit 1
fi

#-----------------------------------------------------------------------------
# 创建输出目录
#-----------------------------------------------------------------------------
mkdir -p "${OUTPUT_DIR}"

#-----------------------------------------------------------------------------
# 解析 dut.flist，展开 ${REPO_ROOT} 变量，生成合并文件列表
#-----------------------------------------------------------------------------
MERGED_FLIST="${OUTPUT_DIR}/merged.flist"

echo "// 自动生成的合并文件列表（请勿手动修改）" > "${MERGED_FLIST}"
echo "// 来源: ${DUT_FLIST}" >> "${MERGED_FLIST}"
echo "" >> "${MERGED_FLIST}"

# 逐行处理 dut.flist，跳过空行和注释行，展开变量
while IFS= read -r line || [ -n "$line" ]; do
    # 去除行首尾空白
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 跳过空行和注释行
    if [ -z "$line" ] || [[ "$line" == //* ]]; then
        continue
    fi

    # 展开 ${REPO_ROOT} 变量
    resolved_line=$(echo "$line" | sed "s|\${REPO_ROOT}|${REPO_ROOT}|g")
    resolved_line=$(echo "$resolved_line" | sed "s|\$REPO_ROOT|${REPO_ROOT}|g")

    echo "$resolved_line" >> "${MERGED_FLIST}"
done < "${DUT_FLIST}"

#-----------------------------------------------------------------------------
# 同样处理 tb.flist（如果存在）
#-----------------------------------------------------------------------------
TB_FLIST="${PROJ_DIR}/tb.flist"
if [ -f "${TB_FLIST}" ]; then
    echo "" >> "${MERGED_FLIST}"
    echo "// 来源: ${TB_FLIST}" >> "${MERGED_FLIST}"
    echo "" >> "${MERGED_FLIST}"

    while IFS= read -r line || [ -n "$line" ]; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$line" ] || [[ "$line" == //* ]]; then
            continue
        fi
        resolved_line=$(echo "$line" | sed "s|\${REPO_ROOT}|${REPO_ROOT}|g")
        resolved_line=$(echo "$resolved_line" | sed "s|\$REPO_ROOT|${REPO_ROOT}|g")
        echo "$resolved_line" >> "${MERGED_FLIST}"
    done < "${TB_FLIST}"
fi

echo -e "${GREEN}[INFO] 文件列表扫描完成: ${MERGED_FLIST}${NC}"
