#!/usr/bin/env python3
# =============================================================================
# run_cases.py - 验证激励管理与回归运行脚本
#
# 功能：
#   1. 解析 verif/<PROJ>/case_list.json 获取激励列表
#   2. 支持按 tag、case_id、case_name 过滤激励
#   3. 调用 vcs_run.sh 执行每条激励，汇总结果
#
# JSON 字段说明：
#   case_id     : 激励唯一 ID（全局唯一）
#   case_name   : 激励名称（对应 UVM test 类名）
#   case_tag    : 激励标签列表，支持多标签过滤
#   case_seq    : 激励对应的 UVM sequence 类名
#   case_define : 激励运行时需要的 plusarg 列表（如 ["+WIDTH=32"]）
#
# 使用方法：
#   python3 run_cases.py --proj <项目名> [过滤选项] [运行选项]
#
#   过滤选项（不指定则运行全部）：
#     --tag      <标签>    按 tag 过滤，多个 tag 用逗号分隔（取并集）
#     --id       <ID>      按 case_id 过滤，多个 ID 用逗号分隔
#     --name     <名称>    按 case_name 过滤，多个名称用逗号分隔
#
#   运行选项：
#     --seed     <种子>    指定仿真种子（默认 random）
#     --verbose  <级别>    UVM 打印级别（默认 UVM_MEDIUM）
#     --wave              开启波形转储
#     --code_cov          开启代码覆盖率
#     --func_cov          开启功能覆盖率
#     --jobs     <N>      并行运行数量（默认 1，暂不支持）
#     --dry_run           仅打印命令，不实际执行
#
# =============================================================================

import os
import sys
import json
import argparse
import subprocess
import datetime
from typing import Any

# -----------------------------------------------------------------------------
# 颜色定义（ANSI 转义码）
# -----------------------------------------------------------------------------
RED    = "\033[0;31m"
GREEN  = "\033[0;32m"
YELLOW = "\033[0;33m"
CYAN   = "\033[0;36m"
NC     = "\033[0m"

def log_info(msg):    print(f"{GREEN}[INFO]{NC} {msg}")
def log_warn(msg):    print(f"{YELLOW}[WARN]{NC} {msg}")
def log_error(msg):   print(f"{RED}[ERROR]{NC} {msg}", file=sys.stderr)
def log_cmd(msg):     print(f"{CYAN}[CMD]{NC} {msg}")


# =============================================================================
# CaseParser - 负责加载和解析 case_list.json
# 设计原则：字段解析集中于此类，新增字段只需在此处扩展
# =============================================================================
class CaseParser:
    """
    解析 case_list.json 文件，返回激励列表。

    JSON 格式：
    {
        "cases": [
            {
                "case_id":     "TC_001",
                "case_name":   "write_test",
                "case_tag":    ["smoke", "write"],
                "case_seq":    "apb_write_seq",
                "case_define": ["+APB_WIDTH=32"]
            }
        ]
    }

    扩展说明：
        若需新增字段（如 case_priority、case_timeout 等），
        只需在 _parse_case() 方法中添加对应字段的解析逻辑即可，
        其余代码无需修改。
    """

    # 必填字段
    REQUIRED_FIELDS = ["case_id", "case_name", "case_tag", "case_seq"]

    def __init__(self, json_path: str):
        self.json_path = json_path
        self.cases: list[dict[str, Any]] = []

    def load(self) -> "CaseParser":
        """加载并解析 JSON 文件"""
        if not os.path.isfile(self.json_path):
            log_error(f"case_list.json 不存在: {self.json_path}")
            log_warn("请在项目目录下创建 case_list.json，参考 README 中的格式说明")
            sys.exit(1)

        with open(self.json_path, "r", encoding="utf-8") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError as e:
                log_error(f"JSON 格式错误: {e}")
                sys.exit(1)

        if "cases" not in data:
            log_error("JSON 中缺少 'cases' 字段")
            sys.exit(1)

        self.cases = [self._parse_case(c, idx) for idx, c in enumerate(data["cases"])]
        log_info(f"共加载 {len(self.cases)} 条激励")
        return self

    def _parse_case(self, raw: dict, idx: int) -> dict[str, Any]:
        """
        解析单条激励。

        若需新增字段，在此处添加解析逻辑：
            case["new_field"] = raw.get("new_field", <默认值>)
        """
        # 检查必填字段
        for field in self.REQUIRED_FIELDS:
            if field not in raw:
                log_error(f"第 {idx+1} 条激励缺少必填字段: '{field}'")
                sys.exit(1)

        case = {}
        case["case_id"]     = str(raw["case_id"])
        case["case_name"]   = str(raw["case_name"])
        case["case_tag"]    = list(raw["case_tag"])          # 标签列表
        case["case_seq"]    = str(raw["case_seq"])           # UVM sequence 类名
        case["case_define"] = list(raw.get("case_define", []))  # plusarg 列表（可选）

        # ------------------------------------------------------------------
        # 扩展点：在此处添加新字段解析（示例）
        # case["case_timeout"] = int(raw.get("case_timeout", 1000000))
        # case["case_priority"] = str(raw.get("case_priority", "normal"))
        # ------------------------------------------------------------------

        return case


# =============================================================================
# CaseFilter - 按条件过滤激励列表
# =============================================================================
class CaseFilter:
    """对激励列表进行过滤，支持按 tag、case_id、case_name 组合筛选"""

    def __init__(self, cases: list[dict]):
        self.cases = cases

    def filter(self,
               tags: list[str] | None = None,
               ids: list[str] | None = None,
               names: list[str] | None = None) -> list[dict]:
        """
        过滤激励。多个条件同时指定时取交集。
        单个条件内（如多个 tag）取并集。
        """
        result = self.cases

        if tags:
            tag_set = set(t.strip() for t in tags)
            result = [c for c in result if tag_set & set(c["case_tag"])]

        if ids:
            id_set = set(i.strip() for i in ids)
            result = [c for c in result if c["case_id"] in id_set]

        if names:
            name_set = set(n.strip() for n in names)
            result = [c for c in result if c["case_name"] in name_set]

        return result


# =============================================================================
# CaseRunner - 驱动仿真执行
# =============================================================================
class CaseRunner:
    """调用 vcs_run.sh 运行激励，汇总 PASS/FAIL 结果"""

    def __init__(self, args: argparse.Namespace, env: dict[str, str]):
        self.args = args
        self.env  = env                  # 传递给子进程的环境变量
        self.script = os.path.join(
            os.environ["REPO_ROOT"], "scripts", "vcs_run.sh"
        )
        self.results: list[dict] = []   # 每条激励的运行结果

    def run_all(self, cases: list[dict]) -> bool:
        """依次运行所有激励，返回是否全部通过"""
        total = len(cases)
        if total == 0:
            log_warn("没有匹配的激励，请检查过滤条件")
            return False

        log_info(f"准备运行 {total} 条激励")
        print("")

        for i, case in enumerate(cases, 1):
            print(f"{'='*60}")
            log_info(f"[{i}/{total}] case_id={case['case_id']}  "
                     f"case_name={case['case_name']}")
            result = self._run_one(case)
            self.results.append(result)

        print("")
        return self._print_summary()

    def _run_one(self, case: dict) -> dict:
        """运行单条激励，返回结果字典"""
        env = self._build_env(case)
        cmd = ["bash", self.script]

        log_cmd(" ".join(f"{k}={v}" for k, v in {
            "TC":         env["TC"],
            "SEED":       env["SEED"],
            "CASE_SEQ":   env["CASE_SEQ"],
            "CODE_COV":   env["CODE_COV"],
            "FUNC_COV":   env["FUNC_COV"],
        }.items()))

        if self.args.dry_run:
            log_warn("[DRY RUN] 跳过实际执行")
            return {"case": case, "passed": True, "returncode": 0}

        ret = subprocess.run(cmd, env=env)
        passed = (ret.returncode == 0)

        return {"case": case, "passed": passed, "returncode": ret.returncode}

    def _build_env(self, case: dict) -> dict[str, str]:
        """构建子进程的环境变量，将 case 信息注入"""
        env = dict(self.env)

        # 基本仿真参数
        env["TC"]         = case["case_name"]     # UVM 测试类名
        env["CASE_SEQ"]   = case["case_seq"]       # UVM sequence 类名（供 TB 使用）
        env["CASE_ID"]    = case["case_id"]
        env["SEED"]       = str(self.args.seed)
        env["VERBOSITY"]  = self.args.verbose
        env["WAVE"]       = "1" if self.args.wave else "0"
        env["CODE_COV"]   = "1" if self.args.code_cov else "0"
        env["FUNC_COV"]   = "1" if self.args.func_cov else "0"

        # case_define：将 plusarg 列表拼接为空格分隔的字符串
        env["CASE_DEFINE"] = " ".join(case.get("case_define", []))

        return env

    def _print_summary(self) -> bool:
        """打印汇总结果，返回是否全部通过"""
        passed = [r for r in self.results if r["passed"]]
        failed = [r for r in self.results if not r["passed"]]

        print(f"{'='*60}")
        print(f" 回归结果汇总  ({datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')})")
        print(f"{'='*60}")
        print(f" 总计: {len(self.results)}  "
              f"{GREEN}PASS: {len(passed)}{NC}  "
              f"{RED}FAIL: {len(failed)}{NC}")
        print("")

        if failed:
            print(f"{RED} 失败的激励:{NC}")
            for r in failed:
                c = r["case"]
                print(f"   [{c['case_id']}] {c['case_name']}")
        else:
            print(f"{GREEN} 全部激励通过！{NC}")

        print(f"{'='*60}")
        return len(failed) == 0


# =============================================================================
# 入口
# =============================================================================
def parse_args():
    parser = argparse.ArgumentParser(
        description="UVM 验证激励管理与回归运行脚本",
        formatter_class=argparse.RawTextHelpFormatter
    )

    # 必填参数
    parser.add_argument("--proj", required=True,
                        help="项目名称（verif/ 下的子目录名）")

    # 过滤选项
    filter_group = parser.add_argument_group("过滤选项（不指定则运行全部激励）")
    filter_group.add_argument("--tag",  nargs="+", metavar="TAG",
                              help="按 case_tag 过滤，多个 tag 取并集")
    filter_group.add_argument("--id",   nargs="+", metavar="ID",
                              help="按 case_id 过滤")
    filter_group.add_argument("--name", nargs="+", metavar="NAME",
                              help="按 case_name 过滤")

    # 运行选项
    run_group = parser.add_argument_group("运行选项")
    run_group.add_argument("--seed",      default="random",
                           help="仿真随机种子（默认: random）")
    run_group.add_argument("--verbose",   default="UVM_MEDIUM",
                           help="UVM 打印级别（默认: UVM_MEDIUM）")
    run_group.add_argument("--wave",      action="store_true",
                           help="开启波形转储（FSDB）")
    run_group.add_argument("--code_cov",  action="store_true",
                           help="开启代码覆盖率统计（line/cond/fsm/tgl/branch）")
    run_group.add_argument("--func_cov",  action="store_true",
                           help="开启功能覆盖率统计（UVM covergroup）")
    run_group.add_argument("--dry_run",   action="store_true",
                           help="仅打印命令，不实际执行仿真")

    return parser.parse_args()


def main():
    args = parse_args()

    # 检查 REPO_ROOT 环境变量
    repo_root = os.environ.get("REPO_ROOT", "")
    if not repo_root:
        log_error("REPO_ROOT 环境变量未设置，请通过 Makefile 调用本脚本")
        sys.exit(1)

    # case_list.json 路径
    json_path = os.path.join(repo_root, "verif", args.proj, "case_list.json")

    # 加载激励列表
    parser_obj = CaseParser(json_path)
    parser_obj.load()

    # 过滤激励
    case_filter = CaseFilter(parser_obj.cases)
    matched = case_filter.filter(
        tags=args.tag,
        ids=args.id,
        names=args.name,
    )
    log_info(f"过滤后匹配激励数量: {len(matched)}")

    # 构建环境变量
    env = dict(os.environ)
    env["PROJ"]       = args.proj
    env["OUTPUT_ROOT"] = os.path.join(repo_root, "output")

    # 运行激励
    runner = CaseRunner(args, env)
    success = runner.run_all(matched)

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
