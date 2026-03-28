#=============================================================================
# Makefile - UVM 验证框架自动化脚本主入口
#
# 用法:
#   make compile  PROJ=<项目名>                     编译指定项目
#   make run      PROJ=<项目名> TC=<测试名>         单条仿真
#   make all      PROJ=<项目名> TC=<测试名>         编译 + 单条仿真
#   make regress  PROJ=<项目名> [TAG=<标签>]        回归（JSON 激励管理）
#   make debug    PROJ=<项目名> TC=<测试名>         打开波形调试
#   make clean    PROJ=<项目名>                     清理指定项目输出
#   make clean_all                                  清理所有输出
#   make help                                       显示帮助信息
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
TC        ?= base_test       # UVM 测试类名（用于 make run/all）
SEED      ?= random          # 随机种子，random 表示自动生成
VERBOSITY ?= UVM_MEDIUM      # UVM 打印级别
WAVE      ?= 1               # 1=转储 FSDB 波形，0=不转储
CODE_COV   ?= 0              # 1=开启代码覆盖率（line/cond/fsm/tgl/branch）
FUNC_COV   ?= 0              # 1=开启功能覆盖率（UVM covergroup）
AUTO_DEBUG ?= 0              # 1=仿真结束后自动打开波形（需同时 WAVE=1）
GUI        ?= 0              # 1=以 GUI 模式打开调试工具

# 回归过滤选项（仅 make regress 使用，由 run_cases.py 解析）
TAG        ?=                # 按 case_tag 过滤，多个标签用空格分隔
CASE_ID    ?=                # 按 case_id 过滤，多个 ID 用空格分隔
CASE_NAME  ?=                # 按 case_name 精确过滤
CASE_REGEX ?=                # 按正则表达式匹配 case_name 过滤

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
RUN_CASES    := $(SCRIPT_DIR)/run_cases.py

#-----------------------------------------------------------------------------
# 导出变量，供 Shell 脚本使用
#-----------------------------------------------------------------------------
export REPO_ROOT
export PROJ
export TC
export SEED
export VERBOSITY
export WAVE
export CODE_COV
export FUNC_COV
export AUTO_DEBUG
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

#-----------------------------------------------------------------------------
# 构建回归脚本的过滤参数
#-----------------------------------------------------------------------------
REGRESS_ARGS :=
ifneq ($(TAG),)
    REGRESS_ARGS += --tag $(TAG)
endif
ifneq ($(CASE_ID),)
    REGRESS_ARGS += --id $(CASE_ID)
endif
ifneq ($(CASE_NAME),)
    REGRESS_ARGS += --name $(CASE_NAME)
endif
ifneq ($(CASE_REGEX),)
    REGRESS_ARGS += --regex '$(CASE_REGEX)'
endif
ifeq ($(WAVE),1)
    REGRESS_ARGS += --wave
endif
ifeq ($(CODE_COV),1)
    REGRESS_ARGS += --code_cov
endif
ifeq ($(FUNC_COV),1)
    REGRESS_ARGS += --func_cov
endif

#=============================================================================
# 目标定义
#=============================================================================

.PHONY: compile run all regress debug clean clean_all help

## 编译：扫描 dut.flist 并调用 VCS 编译
compile:
	$(call check_proj,compile)
	@bash $(FIND_FLIST)
	@bash $(VCS_COMPILE)

## 运行：单条测试仿真（通过 TC 指定测试名）
run:
	$(call check_proj,run)
	@bash $(VCS_RUN)

## 编译 + 单条仿真
all:
	$(call check_proj,all)
	@bash $(FIND_FLIST)
	@bash $(VCS_COMPILE)
	@bash $(VCS_RUN)

## 回归：从 case_list.json 读取激励批量运行
##   支持按 TAG/CASE_ID/CASE_NAME 过滤，不指定则运行全部激励
regress:
	$(call check_proj,regress)
	@python3 $(RUN_CASES) --proj $(PROJ) \
		--seed $(SEED) \
		--verbose $(VERBOSITY) \
		$(REGRESS_ARGS)

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
	@echo "   make compile  PROJ=<项目名>                    编译"
	@echo "   make run      PROJ=<项目名> TC=<测试名>        单条仿真"
	@echo "   make all      PROJ=<项目名> TC=<测试名>        编译+仿真"
	@echo "   make regress  PROJ=<项目名> [过滤选项]         批量回归"
	@echo "   make debug    PROJ=<项目名> TC=<测试名>        波形调试"
	@echo "   make clean    PROJ=<项目名>                    清理输出"
	@echo "   make clean_all                                 清理所有"
	@echo ""
	@echo " 可配置变量:"
	@echo "   PROJ       项目名称 (必填，verif/ 下的子目录名)"
	@echo "   TC         UVM 测试类名   (默认: base_test，make run/all 使用)"
	@echo "   SEED       随机种子       (默认: random)"
	@echo "   VERBOSITY  UVM 打印级别   (默认: UVM_MEDIUM)"
	@echo "   WAVE       转储波形       (默认: 1, 可选 0)"
	@echo "   CODE_COV   代码覆盖率     (默认: 0, 可选 1)"
	@echo "   FUNC_COV   功能覆盖率     (默认: 0, 可选 1)"
	@echo "   AUTO_DEBUG 仿真后自动打开波形 (默认: 0, 可选 1，需同时 WAVE=1)"
	@echo ""
	@echo " 回归过滤变量 (make regress 使用):"
	@echo "   TAG        按 case_tag 过滤，多值用空格分隔"
	@echo "   CASE_ID    按 case_id 过滤"
	@echo "   CASE_NAME  按 case_name 精确过滤"
	@echo "   CASE_REGEX 按正则表达式匹配 case_name 过滤"
	@echo ""
	@echo " 使用示例:"
	@echo "   make all PROJ=apb_slave TC=apb_write_test SEED=12345"
	@echo "   make regress PROJ=apb_slave TAG='smoke write' CODE_COV=1"
	@echo "   make regress PROJ=apb_slave CASE_ID='TC_001 TC_003'"
	@echo "   make regress PROJ=apb_slave CASE_REGEX='write.*test'"
	@echo "   make debug PROJ=apb_slave TC=apb_write_test"
	@echo "============================================================"
