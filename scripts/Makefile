#=============================================================================
# Makefile - UVM 验证框架自动化脚本主入口
#
# 用法:
#   make compile PROJ=<项目名>               编译指定项目
#   make run     PROJ=<项目名> TC=<测试名>   运行仿真
#   make all     PROJ=<项目名> TC=<测试名>   编译 + 运行
#   make debug   PROJ=<项目名> TC=<测试名>   打开波形调试
#   make clean   PROJ=<项目名>               清理指定项目输出
#   make clean_all                           清理所有输出
#   make help                                显示帮助信息
#
# 基于 Synopsys VCS 2020
#=============================================================================

#-----------------------------------------------------------------------------
# 仓库根目录（自动推导，scripts/ 的上一级）
#-----------------------------------------------------------------------------
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

#-----------------------------------------------------------------------------
# 用户可配置变量
#-----------------------------------------------------------------------------
PROJ      ?=                 # 项目名称（verif/ 下的子目录名，必填）
TC        ?= base_test       # UVM 测试类名（+UVM_TESTNAME）
SEED      ?= random          # 随机种子，random 表示自动生成
VERBOSITY ?= UVM_MEDIUM      # UVM 打印级别
WAVE      ?= 1               # 1=转储 FSDB 波形，0=不转储
COV       ?= 0               # 1=开启覆盖率收集，0=关闭
GUI       ?= 0               # 1=以 GUI 模式打开调试工具

#-----------------------------------------------------------------------------
# 输出目录
#-----------------------------------------------------------------------------
OUTPUT_ROOT := $(REPO_ROOT)/output

#-----------------------------------------------------------------------------
# 脚本路径
#-----------------------------------------------------------------------------
SCRIPT_DIR   := $(REPO_ROOT)/scripts
FIND_FLIST   := $(SCRIPT_DIR)/find_flist.sh
VCS_COMPILE  := $(SCRIPT_DIR)/vcs_compile.sh
VCS_RUN      := $(SCRIPT_DIR)/vcs_run.sh
VCS_DEBUG    := $(SCRIPT_DIR)/vcs_debug.sh

#-----------------------------------------------------------------------------
# 导出变量，供 Shell 脚本使用
#-----------------------------------------------------------------------------
export REPO_ROOT
export PROJ
export TC
export SEED
export VERBOSITY
export WAVE
export COV
export GUI
export OUTPUT_ROOT

#-----------------------------------------------------------------------------
# 检查 PROJ 是否指定（compile/run/debug/all/clean 均需要）
#-----------------------------------------------------------------------------
define check_proj
	@if [ -z "$(PROJ)" ]; then \
		echo "[ERROR] 请指定项目名称，例如: make $(1) PROJ=apb_slave"; \
		exit 1; \
	fi
endef

#=============================================================================
# 目标定义
#=============================================================================

.PHONY: compile run all debug clean clean_all help

## 编译：扫描 dut.flist 并调用 VCS 编译
compile:
	$(call check_proj,compile)
	@bash $(FIND_FLIST)
	@bash $(VCS_COMPILE)

## 运行：执行编译生成的 simv 进行仿真
run:
	$(call check_proj,run)
	@bash $(VCS_RUN)

## 编译 + 运行
all:
	$(call check_proj,all)
	@bash $(FIND_FLIST)
	@bash $(VCS_COMPILE)
	@bash $(VCS_RUN)

## 调试：打开 Verdi/DVE 查看波形
debug:
	$(call check_proj,debug)
	@bash $(VCS_DEBUG)

## 清理指定项目的输出
clean:
	$(call check_proj,clean)
	@echo "[INFO] 清理项目 $(PROJ) 的输出目录..."
	@rm -rf $(OUTPUT_ROOT)/$(PROJ)
	@echo "[INFO] 清理完成"

## 清理所有输出
clean_all:
	@echo "[INFO] 清理所有输出目录..."
	@rm -rf $(OUTPUT_ROOT)
	@echo "[INFO] 清理完成"

## 显示帮助信息
help:
	@echo "============================================================"
	@echo " UVM 验证框架 - 自动化脚本使用帮助"
	@echo "============================================================"
	@echo ""
	@echo " 基本用法:"
	@echo "   make compile PROJ=<项目名>              编译"
	@echo "   make run     PROJ=<项目名> TC=<测试名>  运行仿真"
	@echo "   make all     PROJ=<项目名> TC=<测试名>  编译+运行"
	@echo "   make debug   PROJ=<项目名> TC=<测试名>  波形调试"
	@echo "   make clean   PROJ=<项目名>              清理项目输出"
	@echo "   make clean_all                          清理所有输出"
	@echo ""
	@echo " 可配置变量:"
	@echo "   PROJ       项目名称 (必填，verif/ 下的子目录名)"
	@echo "   TC         UVM 测试类名   (默认: base_test)"
	@echo "   SEED       随机种子       (默认: random)"
	@echo "   VERBOSITY  UVM 打印级别   (默认: UVM_MEDIUM)"
	@echo "   WAVE       转储波形       (默认: 1, 可选 0)"
	@echo "   COV        覆盖率收集     (默认: 0, 可选 1)"
	@echo "   GUI        GUI 调试模式   (默认: 0, 可选 1)"
	@echo ""
	@echo " 示例:"
	@echo "   make all PROJ=apb_slave TC=apb_write_test SEED=12345"
	@echo "   make debug PROJ=apb_slave TC=apb_write_test"
	@echo "============================================================"
