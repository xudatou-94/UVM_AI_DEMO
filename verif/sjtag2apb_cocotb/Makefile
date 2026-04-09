#=============================================================================
# cocotb Makefile for sjtag2apb
#
# 用法:
#   make SIM=icarus              使用 Icarus Verilog（免费，推荐本地测试）
#   make SIM=vcs                 使用 Synopsys VCS
#   make SIM=icarus MODULE=tests.test_smoke   只运行 smoke 测试
#   make SIM=icarus TESTCASE=test_tap_reset_idcode  只运行单个测试函数
#   make clean
#=============================================================================

# 仓库根目录
REPO_ROOT  ?= $(abspath ../..)

# 仿真器选择（默认 icarus，也支持 vcs/questa/xcelium）
SIM        ?= icarus

# 顶层模块名
TOPLEVEL   := sjtag2apb_bridge
TOPLEVEL_LANG := verilog

# 默认运行所有测试模块
MODULE     ?= tests.test_smoke,tests.test_apb_basic,tests.test_apb_advanced,tests.test_bypass

# Python 路径（让 cocotb 能找到 tb/ 和 tests/）
export PYTHONPATH := $(abspath .):$(PYTHONPATH)

# RTL 源文件列表
VERILOG_SOURCES  = $(REPO_ROOT)/design/sjtag2apb/rtl/sjtag2apb_pkg.sv
VERILOG_SOURCES += $(REPO_ROOT)/design/sjtag2apb/rtl/sjtag_tap_ctrl.sv
VERILOG_SOURCES += $(REPO_ROOT)/design/sjtag2apb/rtl/sjtag2apb_bridge.sv

# VCS 额外编译选项
ifeq ($(SIM),vcs)
  COMPILE_ARGS += -sverilog -full64
  COMPILE_ARGS += +incdir+$(REPO_ROOT)/design/sjtag2apb/rtl
  SIM_ARGS     += +ntb_random_seed=1
endif

# Icarus 额外编译选项
ifeq ($(SIM),icarus)
  COMPILE_ARGS += -g2012
  COMPILE_ARGS += -I$(REPO_ROOT)/design/sjtag2apb/rtl
endif

# cocotb 框架入口（必须放最后）
include $(shell cocotb-config --makefiles)/Makefile.sim

#-----------------------------------------------------------------------------
# 便捷目标
#-----------------------------------------------------------------------------

## 只运行 smoke 测试
smoke:
	$(MAKE) MODULE=tests.test_smoke

## 只运行 APB 基本测试
apb_basic:
	$(MAKE) MODULE=tests.test_apb_basic

## 只运行 APB 高级测试
apb_advanced:
	$(MAKE) MODULE=tests.test_apb_advanced

## 只运行 bypass 测试
bypass:
	$(MAKE) MODULE=tests.test_bypass

## 运行所有测试（带覆盖率，仅 VCS）
cov:
	$(MAKE) SIM=vcs COMPILE_ARGS="-sverilog -full64 -cm line+cond+fsm+tgl"

## 显示帮助
help:
	@echo "============================================================"
	@echo " sjtag2apb cocotb 验证环境"
	@echo "============================================================"
	@echo " make               运行所有测试 (默认 SIM=icarus)"
	@echo " make SIM=vcs       使用 VCS 运行"
	@echo " make smoke         只运行 smoke 测试"
	@echo " make apb_basic     只运行 APB 基本读写测试"
	@echo " make apb_advanced  只运行 APB 高级测试（wait_state/slverr/burst）"
	@echo " make bypass        只运行 BYPASS 测试"
	@echo " make clean         清理编译输出"
	@echo ""
	@echo " 运行单个测试函数:"
	@echo "   make MODULE=tests.test_smoke TESTCASE=test_tap_reset_idcode"
	@echo "============================================================"
