#=============================================================================
# proj.mk - 模块级 Makefile 通用委托模板
#
# 使用方法：
#   将本文件复制到 verif/<module>/Makefile，无需任何修改。
#   PROJ 由当前目录名自动推导，所有目标委托给 scripts/Makefile。
#
# 示例：
#   cd verif/otbn
#   make compile
#   make run   TC=otbn_smoke_test
#   make all   TC=otbn_smoke_test SEED=12345
#   make regress TAG=smoke JOBS=4
#   make debug TC=otbn_smoke_test
#=============================================================================

# 从当前目录名自动推导项目名
PROJ     := $(notdir $(abspath .))
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../..)
SCRIPTS  := $(REPO_ROOT)/scripts

# 所有支持的目标列表
TARGETS := compile run all regress rerun merge_cov report debug \
           clean clean_all setup help

.PHONY: $(TARGETS)

# 将所有目标委托给 scripts/Makefile，透传命令行变量
$(TARGETS):
	@$(MAKE) -C $(SCRIPTS) $@ PROJ=$(PROJ)

# 默认目标
.DEFAULT_GOAL := help
