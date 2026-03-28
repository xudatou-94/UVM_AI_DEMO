#=============================================================================
# Makefile - UVM 验证框架自动化脚本主入口
#
# 用法:
#   make compile    PROJ=<项目名>                     编译指定项目
#   make run        PROJ=<项目名> TC=<测试名>         单条仿真
#   make all        PROJ=<项目名> TC=<测试名>         编译 + 单条仿真
#   make regress    PROJ=<项目名> [过滤/运行选项]     批量回归
#   make rerun      PROJ=<项目名>                     重跑上次失败的激励
#   make merge_cov  PROJ=<项目名>                     合并覆盖率并生成报告
#   make report     PROJ=<项目名>                     从最新结果生成报告
#   make debug      PROJ=<项目名> TC=<测试名>         打开波形调试
#   make clean      PROJ=<项目名>                     清理指定项目输出
#   make clean_all                                    清理所有输出
#   make setup                                        显示环境初始化方法
#   make help                                         显示帮助信息
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
PROJ        ?=               # 项目名称（verif/ 下的子目录名，必填）
TC          ?= base_test     # UVM 测试类名（make run/all 使用）
SEED        ?= random        # 随机种子，random 表示自动生成
VERBOSITY   ?= UVM_MEDIUM    # UVM 打印级别
WAVE        ?= 1             # 1=转储 FSDB 波形，0=不转储
WAVE_SCOPE  ?=               # 波形转储范围（空=全量；如 tb_top.u_dut）
CODE_COV    ?= 0             # 1=开启代码覆盖率（line/cond/fsm/tgl/branch）
FUNC_COV    ?= 0             # 1=开启功能覆盖率（UVM covergroup）
CASE_TIMEOUT?= 3600          # 单条激励超时秒数（默认 1 小时）
AUTO_DEBUG  ?= 0             # 1=仿真结束后自动打开波形（需同时 WAVE=1）
JOBS        ?= 1             # 本地并行作业数
SUBMIT      ?= local         # 提交方式：local / lsf / sge
GUI         ?= 0             # 1=以 GUI 模式打开调试工具

# 回归过滤选项（make regress 使用）
TAG         ?=               # 按 case_tag 过滤，多个标签用空格分隔
CASE_ID     ?=               # 按 case_id 过滤
CASE_NAME   ?=               # 按 case_name 精确过滤
CASE_REGEX  ?=               # 按正则表达式匹配 case_name 过滤

#-----------------------------------------------------------------------------
# 输出目录
#-----------------------------------------------------------------------------
OUTPUT_ROOT := $(REPO_ROOT)/output

#-----------------------------------------------------------------------------
# 脚本路径
#-----------------------------------------------------------------------------
SCRIPT_DIR  := $(REPO_ROOT)/scripts
FIND_FLIST  := $(SCRIPT_DIR)/find_flist.sh
VCS_COMPILE := $(SCRIPT_DIR)/vcs_compile.sh
VCS_RUN     := $(SCRIPT_DIR)/vcs_run.sh
VCS_DEBUG   := $(SCRIPT_DIR)/vcs_debug.sh
RUN_CASES   := $(SCRIPT_DIR)/run_cases.py
MERGE_COV   := $(SCRIPT_DIR)/merge_cov.sh
GEN_REPORT  := $(SCRIPT_DIR)/gen_report.py

#-----------------------------------------------------------------------------
# 导出变量，供 Shell 脚本使用
#-----------------------------------------------------------------------------
export REPO_ROOT OUTPUT_ROOT
export PROJ TC SEED VERBOSITY
export WAVE WAVE_SCOPE CODE_COV FUNC_COV
export CASE_TIMEOUT AUTO_DEBUG GUI

#-----------------------------------------------------------------------------
# 检查 PROJ 是否指定
#-----------------------------------------------------------------------------
define check_proj
	@if [ -z "$(PROJ)" ]; then \
		echo "[ERROR] 请指定项目名称，例如: make $(1) PROJ=apb_slave"; \
		exit 1; \
	fi
endef

#-----------------------------------------------------------------------------
# 构建回归脚本参数
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
ifneq ($(WAVE_SCOPE),)
    REGRESS_ARGS += --wave_scope $(WAVE_SCOPE)
endif
ifeq ($(CODE_COV),1)
    REGRESS_ARGS += --code_cov
endif
ifeq ($(FUNC_COV),1)
    REGRESS_ARGS += --func_cov
endif
ifeq ($(AUTO_DEBUG),1)
    REGRESS_ARGS += --auto_debug
endif

#=============================================================================
# 目标定义
#=============================================================================

.PHONY: compile run all regress rerun merge_cov report debug \
        clean clean_all setup help

## 编译：扫描 dut.flist 并调用 VCS 编译
compile:
	$(call check_proj,compile)
	@bash $(FIND_FLIST)
	@bash $(VCS_COMPILE)

## 运行：单条测试仿真（TC 指定测试名）
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
##   支持 TAG/CASE_ID/CASE_NAME/CASE_REGEX 过滤，JOBS 并行，SUBMIT 提交方式
regress:
	$(call check_proj,regress)
	@python3 $(RUN_CASES) --proj $(PROJ) \
		--seed $(SEED) \
		--verbose $(VERBOSITY) \
		--timeout $(CASE_TIMEOUT) \
		--jobs $(JOBS) \
		--submit $(SUBMIT) \
		$(REGRESS_ARGS)

## 重跑：重跑上次回归中失败的激励（保留原种子）
rerun:
	$(call check_proj,rerun)
	@python3 $(RUN_CASES) --proj $(PROJ) \
		--verbose $(VERBOSITY) \
		--jobs $(JOBS) \
		--submit $(SUBMIT) \
		$(REGRESS_ARGS) \
		--rerun

## 合并覆盖率：汇总所有仿真的代码/功能覆盖率并生成报告
merge_cov:
	$(call check_proj,merge_cov)
	@bash $(MERGE_COV)

## 报告：从最新回归结果生成 HTML/CSV 报告
report:
	$(call check_proj,report)
	@LATEST=$$(ls -td $(OUTPUT_ROOT)/$(PROJ)/reports/*/results.json 2>/dev/null | head -1); \
	if [ -z "$$LATEST" ]; then \
		echo "[ERROR] 未找到回归结果，请先运行 make regress PROJ=$(PROJ)"; \
		exit 1; \
	fi; \
	REPORT_DIR=$$(dirname $$LATEST); \
	echo "[INFO] 使用结果文件: $$LATEST"; \
	python3 $(GEN_REPORT) --results $$LATEST --output $$REPORT_DIR

## 调试：打开 Verdi/DVE 查看波形
debug:
	$(call check_proj,debug)
	@bash $(VCS_DEBUG)

## 显示环境初始化方法
setup:
	@echo "============================================================"
	@echo " 环境初始化"
	@echo "============================================================"
	@echo " 请在 shell 中执行以下命令（不可 make，需 source）："
	@echo ""
	@echo "   source scripts/setup.sh"
	@echo "   source scripts/setup.sh --site <站点名>"
	@echo ""
	@echo " 首次使用请编辑 scripts/setup.sh，"
	@echo " 配置 VCS_HOME、VERDI_HOME、SNPSLMD_LICENSE_FILE"
	@echo "============================================================"

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
	@echo "   make compile   PROJ=<项目名>                   编译"
	@echo "   make run       PROJ=<项目名> TC=<测试名>       单条仿真"
	@echo "   make all       PROJ=<项目名> TC=<测试名>       编译+仿真"
	@echo "   make regress   PROJ=<项目名> [过滤选项]        批量回归"
	@echo "   make rerun     PROJ=<项目名>                   重跑失败激励"
	@echo "   make merge_cov PROJ=<项目名>                   合并覆盖率"
	@echo "   make report    PROJ=<项目名>                   生成回归报告"
	@echo "   make debug     PROJ=<项目名> TC=<测试名>       波形调试"
	@echo "   make clean     PROJ=<项目名>                   清理输出"
	@echo "   make clean_all                                 清理全部"
	@echo "   make setup                                     环境初始化说明"
	@echo ""
	@echo " 仿真控制变量:"
	@echo "   TC           UVM 测试类名        (默认: base_test)"
	@echo "   SEED         随机种子            (默认: random)"
	@echo "   VERBOSITY    UVM 打印级别        (默认: UVM_MEDIUM)"
	@echo "   WAVE         转储波形            (默认: 1)"
	@echo "   WAVE_SCOPE   波形转储范围        (默认: 全量)"
	@echo "   CODE_COV     代码覆盖率          (默认: 0, 可选 1)"
	@echo "   FUNC_COV     功能覆盖率          (默认: 0, 可选 1)"
	@echo "   CASE_TIMEOUT 单条超时秒数        (默认: 3600)"
	@echo "   AUTO_DEBUG   仿真后自动开波形    (默认: 0, 可选 1)"
	@echo "   JOBS         本地并行数          (默认: 1)"
	@echo "   SUBMIT       提交方式            (默认: local, 可选 lsf/sge)"
	@echo ""
	@echo " 回归过滤变量:"
	@echo "   TAG          按 case_tag 过滤    (多值空格分隔)"
	@echo "   CASE_ID      按 case_id 过滤"
	@echo "   CASE_NAME    按 case_name 精确过滤"
	@echo "   CASE_REGEX   按正则匹配 case_name"
	@echo ""
	@echo " 使用示例:"
	@echo "   make all     PROJ=apb_slave TC=write_test SEED=12345"
	@echo "   make regress PROJ=apb_slave TAG=smoke CODE_COV=1 JOBS=4"
	@echo "   make regress PROJ=apb_slave CASE_REGEX='write.*' SUBMIT=lsf"
	@echo "   make rerun   PROJ=apb_slave"
	@echo "   make merge_cov PROJ=apb_slave"
	@echo "============================================================"
