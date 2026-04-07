#!/bin/bash
#=============================================================================
# setup.sh - EDA 环境初始化脚本
#
# 功能：
#   1. 配置 Synopsys VCS 2020、Verdi 工具路径
#   2. 配置 License 服务器
#   3. 检查工具可用性并给出提示
#
# 使用方式（在 shell 中 source，不可直接执行）：
#   source scripts/setup.sh
#   source scripts/setup.sh --site <站点名>    # 多站点时指定
#
# 注意：本脚本需根据实际服务器环境修改工具安装路径
#=============================================================================

# 防止直接执行（需要 source 才能使环境变量生效）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] 请使用 source 执行本脚本: source scripts/setup.sh"
    exit 1
fi

#-----------------------------------------------------------------------------
# 颜色定义
#-----------------------------------------------------------------------------
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[0;33m'
_NC='\033[0m'

#-----------------------------------------------------------------------------
# 解析参数（--site 用于多站点环境切换）
#-----------------------------------------------------------------------------
_SITE="default"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --site) _SITE="$2"; shift 2 ;;
        *)      shift ;;
    esac
done

echo -e "${_GREEN}[SETUP] 初始化 EDA 环境 (site: ${_SITE})${_NC}"

#=============================================================================
# EDA 工具路径配置
# 根据实际安装路径修改以下变量
#=============================================================================
case "${_SITE}" in
    default)
        # ---------- VCS 2020 ----------
        export VCS_HOME="/usr/Synopsys/vcs/Q-2020.03-SP2-7"
        # ---------- Verdi ----------
        export VERDI_HOME="/usr/Synopsys/verdi/R-2020.12-SP1"
        ;;
    site_a)
        export VCS_HOME="/eda/synopsys/vcs-mx/O-2018.09"
        export VERDI_HOME="/eda/synopsys/verdi/S-2021.09"
        ;;
    # 按需添加更多站点配置
    *)
        echo -e "${_RED}[SETUP] 未知站点: ${_SITE}，使用 default 配置${_NC}"
        ;;
esac

#-----------------------------------------------------------------------------
# 将工具 bin 目录加入 PATH
#-----------------------------------------------------------------------------
if [ -d "${VCS_HOME}/bin" ]; then
    export PATH="${VCS_HOME}/bin:${PATH}"
else
    echo -e "${_YELLOW}[SETUP][WARN] VCS_HOME 路径不存在: ${VCS_HOME}${_NC}"
fi

if [ -d "${VERDI_HOME}/bin" ]; then
    export PATH="${VERDI_HOME}/bin:${PATH}"
else
    echo -e "${_YELLOW}[SETUP][WARN] VERDI_HOME 路径不存在: ${VERDI_HOME}${_NC}"
fi

#-----------------------------------------------------------------------------
# 仓库根目录（自动推导）
#-----------------------------------------------------------------------------
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OUTPUT_ROOT="${REPO_ROOT}/output"

#-----------------------------------------------------------------------------
# Python3 检查
#-----------------------------------------------------------------------------
if ! command -v python3 &> /dev/null; then
    echo -e "${_YELLOW}[SETUP][WARN] python3 未找到，run_cases.py 相关功能不可用${_NC}"
fi

#-----------------------------------------------------------------------------
# 验证工具可用性
#-----------------------------------------------------------------------------
_ALL_OK=1

_check_tool() {
    local tool="$1"
    if command -v "${tool}" &> /dev/null; then
        local ver
        ver=$(${tool} -ID 2>&1 | head -1 || echo "unknown")
        echo -e "${_GREEN}[SETUP]  ✓ ${tool}${_NC}"
    else
        echo -e "${_RED}[SETUP]  ✗ ${tool} 未找到，请检查安装路径${_NC}"
        _ALL_OK=0
    fi
}

echo -e "[SETUP] 检查工具可用性..."
_check_tool vcs
_check_tool verdi
_check_tool urg        # 覆盖率合并工具

if [ "${_ALL_OK}" = "1" ]; then
    echo -e "${_GREEN}[SETUP] 环境初始化完成${_NC}"
else
    echo -e "${_YELLOW}[SETUP] 部分工具未找到，请修改 setup.sh 中的路径配置${_NC}"
fi

echo -e "[SETUP] REPO_ROOT = ${REPO_ROOT}"

# 清理临时变量
unset _RED _GREEN _YELLOW _NC _SITE _ALL_OK
