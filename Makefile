#=============================================================================
# Makefile - 仓库根目录入口
#
# 委托 scripts/Makefile 执行所有目标，PROJ 需显式指定。
#
# 用法：
#   make regress  PROJ=<项目名> TAG=<标签>          按标签批量回归
#   make regress  PROJ=<项目名> CASE_NAME=<名称>    按用例名回归
#   make regress  PROJ=<项目名> CASE_REGEX=<正则>   按正则匹配回归
#   make run      PROJ=<项目名> TC=<测试类名>        单条运行
#   make compile  PROJ=<项目名>                      编译
#   make all      PROJ=<项目名> TC=<测试类名>        编译 + 运行
#   make rerun    PROJ=<项目名>                      重跑上次失败
#   make merge_cov PROJ=<项目名>                     合并覆盖率
#   make report   PROJ=<项目名>                      生成报告
#   make debug    PROJ=<项目名> TC=<测试类名>        波形调试
#   make clean    PROJ=<项目名>                      清理项目输出
#   make clean_all                                   清理所有输出
#   make help                                        显示帮助
#=============================================================================

SCRIPTS := $(abspath scripts)

TARGETS := compile run all regress rerun merge_cov report debug \
           clean clean_all setup help

.PHONY: $(TARGETS)

$(TARGETS):
	@$(MAKE) -C $(SCRIPTS) $@

.DEFAULT_GOAL := help
