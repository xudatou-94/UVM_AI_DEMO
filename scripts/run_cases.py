#!/usr/bin/env python3
# =============================================================================
# run_cases.py - 验证激励管理与回归运行脚本
#
# 功能：
#   1. 解析 verif/<PROJ>/case_list.json 获取激励列表
#   2. 支持按 tag、case_id、case_name、正则表达式过滤激励
#   3. 本地顺序/并行执行、LSF/SGE 集群提交
#   4. 回归结束后生成 HTML + CSV 报告
#   5. 记录每条激励的种子到 seed_record.csv，支持失败重现（--rerun）
#
# JSON 字段说明：
#   case_id       激励唯一 ID（全局唯一）
#   case_name     激励名称（对应 UVM test 类名）
#   case_tag      激励标签列表，支持多标签过滤
#   case_seq      激励对应的 UVM sequence 类名
#   case_define   激励运行时需要的 plusarg 列表（如 ["+WIDTH=32"]）
#   case_timeout  激励超时秒数（可选，覆盖默认值）
#
# 使用方法：
#   python3 run_cases.py --proj <项目名> [过滤选项] [运行选项]
#
#   过滤选项（不指定则运行全部）：
#     --tag      <标签>    按 case_tag 过滤（多值取并集）
#     --id       <ID>      按 case_id 精确过滤
#     --name     <名称>    按 case_name 精确过滤
#     --regex    <正则>    按正则表达式匹配 case_name
#     --rerun             重跑上次回归中失败的用例（保留原种子）
#
#   运行选项：
#     --seed     <种子>    指定仿真种子（默认 random）
#     --verbose  <级别>    UVM 打印级别（默认 UVM_MEDIUM）
#     --timeout  <秒>      单条激励超时秒数（默认 3600）
#     --wave              开启波形转储
#     --wave_scope <范围> 波形转储范围（默认全量，如 tb_top.u_dut）
#     --code_cov          开启代码覆盖率
#     --func_cov          开启功能覆盖率
#     --auto_debug        仿真结束后自动打开波形
#     --jobs     <N>      本地并行数（默认 1）
#     --submit   <方式>   提交方式: local（默认）/ lsf / sge
#     --dry_run           仅打印命令，不实际执行
#
# =============================================================================

import os
import re
import sys
import csv
import json
import time
import argparse
import datetime
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

# 导入报告生成模块（同目录）
sys.path.insert(0, os.path.dirname(__file__))
from gen_report import HtmlReportGenerator, CsvReportGenerator, SeedRecorder

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
# =============================================================================
class CaseParser:
    """
    解析 case_list.json 文件，返回激励列表。

    扩展说明：
        若需新增字段，只需在 _parse_case() 中添加对应解析逻辑，
        其余代码无需修改。
    """

    REQUIRED_FIELDS = ["case_id", "case_name", "case_tag", "case_seq"]

    def __init__(self, json_path: str):
        self.json_path = json_path
        self.cases: list[dict[str, Any]] = []

    def load(self) -> "CaseParser":
        if not os.path.isfile(self.json_path):
            log_error(f"case_list.json 不存在: {self.json_path}")
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
        self.cases = [self._parse_case(c, i) for i, c in enumerate(data["cases"])]
        log_info(f"共加载 {len(self.cases)} 条激励")
        return self

    def _parse_case(self, raw: dict, idx: int) -> dict[str, Any]:
        """
        解析单条激励。
        扩展新字段：在此处添加 case["new_field"] = raw.get("new_field", <默认值>)
        """
        for field in self.REQUIRED_FIELDS:
            if field not in raw:
                log_error(f"第 {idx+1} 条激励缺少必填字段: '{field}'")
                sys.exit(1)
        case = {}
        case["case_id"]      = str(raw["case_id"])
        case["case_name"]    = str(raw["case_name"])
        case["case_tag"]     = list(raw["case_tag"])
        case["case_seq"]     = str(raw["case_seq"])
        case["case_define"]  = list(raw.get("case_define", []))
        case["case_timeout"] = int(raw.get("case_timeout", 0))  # 0=使用全局默认值

        # ------------------------------------------------------------------
        # 扩展点：在此处添加新字段解析
        # case["case_priority"] = str(raw.get("case_priority", "normal"))
        # ------------------------------------------------------------------
        return case


# =============================================================================
# CaseFilter - 按条件过滤激励列表
# =============================================================================
class CaseFilter:
    """对激励列表进行过滤，支持按 tag、case_id、case_name、正则表达式组合筛选"""

    def __init__(self, cases: list[dict]):
        self.cases = cases

    def filter(self,
               tags: list[str] | None = None,
               ids: list[str] | None = None,
               names: list[str] | None = None,
               regex: str | None = None) -> list[dict]:
        """
        过滤激励。多个条件同时指定时取交集；单条件内多值取并集。

        参数：
            tags  : 按 case_tag 过滤，多个 tag 取并集
            ids   : 按 case_id 精确匹配
            names : 按 case_name 精确匹配
            regex : 按正则表达式匹配 case_name
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

        if regex:
            try:
                pattern = re.compile(regex)
            except re.error as e:
                log_error(f"正则表达式无效: '{regex}' -> {e}")
                sys.exit(1)
            result = [c for c in result if pattern.search(c["case_name"])]

        return result


# =============================================================================
# LocalRunner - 本地顺序/并行执行
# =============================================================================
class LocalRunner:
    """在本地运行激励，支持顺序和多进程并行"""

    def __init__(self, script: str, args: argparse.Namespace,
                 base_env: dict[str, str]):
        self.script   = script
        self.args     = args
        self.base_env = base_env

    def run_all(self, cases: list[dict]) -> list[dict]:
        """运行所有激励，返回结果列表"""
        jobs = min(self.args.jobs, len(cases))
        if jobs > 1:
            log_info(f"本地并行执行，jobs={jobs}")
            return self._run_parallel(cases, jobs)
        else:
            log_info("本地顺序执行")
            return [self._run_one(c, i+1, len(cases))
                    for i, c in enumerate(cases)]

    def _run_parallel(self, cases: list[dict], jobs: int) -> list[dict]:
        results = [None] * len(cases)
        with ThreadPoolExecutor(max_workers=jobs) as executor:
            future_map = {
                executor.submit(self._run_one, c, i+1, len(cases)): i
                for i, c in enumerate(cases)
            }
            for future in as_completed(future_map):
                idx = future_map[future]
                results[idx] = future.result()
        return results

    def _run_one(self, case: dict, seq: int, total: int) -> dict:
        print(f"\n{'='*60}")
        log_info(f"[{seq}/{total}] {case['case_id']}  {case['case_name']}")

        env = self._build_env(case)
        if self.args.dry_run:
            log_warn("[DRY RUN] 跳过实际执行")
            return self._make_result(case, True, env)

        start = time.time()
        ret = subprocess.run(["bash", self.script], env=env)
        duration = time.time() - start

        # 优先从 result.json 读取结果（vcs_run.sh 写入）
        sim_dir  = self._get_sim_dir(env)
        result   = self._read_result_json(sim_dir, case, duration)
        return result

    def _build_env(self, case: dict) -> dict[str, str]:
        env = dict(self.base_env)
        env["TC"]           = case["case_name"]
        env["CASE_SEQ"]     = case["case_seq"]
        env["CASE_ID"]      = case["case_id"]
        env["CASE_DEFINE"]  = " ".join(case.get("case_define", []))
        env["SEED"]         = str(self.args.seed)
        env["VERBOSITY"]    = self.args.verbose
        env["WAVE"]         = "1" if self.args.wave else "0"
        env["WAVE_SCOPE"]   = self.args.wave_scope or ""
        env["CODE_COV"]     = "1" if self.args.code_cov else "0"
        env["FUNC_COV"]     = "1" if self.args.func_cov else "0"
        env["AUTO_DEBUG"]   = "1" if self.args.auto_debug else "0"
        # case 级别的 timeout 优先于全局设置
        timeout = case.get("case_timeout") or self.args.timeout
        env["CASE_TIMEOUT"] = str(timeout)
        return env

    def _get_sim_dir(self, env: dict) -> str:
        return os.path.join(
            env["OUTPUT_ROOT"], env["PROJ"], "sim",
            f"{env['TC']}_{env['SEED']}"
        )

    def _read_result_json(self, sim_dir: str, case: dict,
                          fallback_duration: float) -> dict:
        result_json = os.path.join(sim_dir, "result.json")
        if os.path.isfile(result_json):
            with open(result_json, "r") as f:
                return json.load(f)
        # fallback：若 result.json 不存在（脚本异常退出）
        return {
            "case_id":   case["case_id"],
            "case_name": case["case_name"],
            "seed":      self.args.seed,
            "passed":    False,
            "uvm_fatal": -1,
            "uvm_error": -1,
            "timed_out": False,
            "duration":  fallback_duration,
            "log":       "",
            "fsdb":      "",
            "tags":      case.get("case_tag", []),
        }

    def _make_result(self, case: dict, passed: bool, env: dict) -> dict:
        return {
            "case_id":   case["case_id"],
            "case_name": case["case_name"],
            "seed":      env["SEED"],
            "passed":    passed,
            "uvm_fatal": 0,
            "uvm_error": 0,
            "timed_out": False,
            "duration":  0,
            "log":       "",
            "fsdb":      "",
            "tags":      case.get("case_tag", []),
        }


# =============================================================================
# LsfRunner - LSF 集群提交
# =============================================================================
class LsfRunner:
    """
    将每条激励提交到 LSF 集群（bsub），等待全部完成后汇总结果。

    常用 LSF 资源配置（可通过 LSF_ARGS 环境变量覆盖）：
        LSF_ARGS="-q normal -n 1 -R 'rusage[mem=4096]'"
    """

    POLL_INTERVAL = 30  # 轮询间隔（秒）

    def __init__(self, script: str, args: argparse.Namespace,
                 base_env: dict[str, str]):
        self.script   = script
        self.args     = args
        self.base_env = base_env
        # 额外的 LSF 资源参数，可通过环境变量配置
        self.lsf_extra = os.environ.get("LSF_ARGS", "-q normal -n 1")

    def run_all(self, cases: list[dict]) -> list[dict]:
        log_info(f"LSF 模式：提交 {len(cases)} 个作业")
        job_ids = []
        job_info = []  # 存储 (job_id, case, env) 三元组

        # 提交所有作业
        for i, case in enumerate(cases):
            env  = self._build_env(case)
            jid  = self._submit_job(case, env, i)
            if jid:
                job_ids.append(jid)
                job_info.append((jid, case, env))
            else:
                log_error(f"作业提交失败: {case['case_id']}")

        if not job_ids:
            log_error("所有作业提交失败")
            return []

        log_info(f"已提交 {len(job_ids)} 个作业，开始等待...")

        # 等待所有作业完成
        self._wait_for_jobs(job_ids)

        # 收集结果
        results = []
        for jid, case, env in job_info:
            sim_dir = os.path.join(
                env["OUTPUT_ROOT"], env["PROJ"], "sim",
                f"{env['TC']}_{env['SEED']}"
            )
            result_json = os.path.join(sim_dir, "result.json")
            if os.path.isfile(result_json):
                with open(result_json) as f:
                    results.append(json.load(f))
            else:
                results.append({
                    "case_id":   case["case_id"],
                    "case_name": case["case_name"],
                    "seed":      env["SEED"],
                    "passed":    False,
                    "uvm_fatal": -1,
                    "uvm_error": -1,
                    "timed_out": False,
                    "duration":  0,
                    "log":       "",
                    "fsdb":      "",
                    "tags":      case.get("case_tag", []),
                })
        return results

    def _build_env(self, case: dict) -> dict[str, str]:
        """复用 LocalRunner 的环境构建逻辑"""
        env = LocalRunner(self.script, self.args, self.base_env)._build_env(case)
        return env

    def _submit_job(self, case: dict, env: dict, idx: int) -> str | None:
        """提交单个作业，返回 LSF Job ID"""
        job_name   = f"uvm_{env['PROJ']}_{case['case_id']}"
        log_file   = os.path.join(
            env["OUTPUT_ROOT"], env["PROJ"], "lsf_logs",
            f"{job_name}.lsf.log"
        )
        os.makedirs(os.path.dirname(log_file), exist_ok=True)

        # 构建 bsub 命令
        bsub_cmd = ["bsub"]
        bsub_cmd += self.lsf_extra.split()
        bsub_cmd += ["-J", job_name, "-o", log_file]
        bsub_cmd += ["bash", self.script]

        log_cmd(f"bsub -J {job_name}")

        try:
            result = subprocess.run(
                bsub_cmd, env=env,
                capture_output=True, text=True
            )
            # bsub 输出格式：Job <12345> is submitted to queue <normal>.
            match = re.search(r"Job <(\d+)>", result.stdout)
            if match:
                jid = match.group(1)
                log_info(f"作业提交成功: {job_name} (Job ID: {jid})")
                return jid
            else:
                log_error(f"无法解析 Job ID: {result.stdout}")
                return None
        except FileNotFoundError:
            log_error("bsub 命令未找到，请确认 LSF 环境已配置")
            return None

    def _wait_for_jobs(self, job_ids: list[str]) -> None:
        """轮询等待所有 LSF 作业完成"""
        pending = set(job_ids)
        while pending:
            time.sleep(self.POLL_INTERVAL)
            try:
                result = subprocess.run(
                    ["bjobs", "-noheader"] + list(pending),
                    capture_output=True, text=True
                )
                # 仍在运行的作业（RUN/PEND/WAIT 状态）
                still_running = set()
                for line in result.stdout.splitlines():
                    parts = line.split()
                    if len(parts) >= 3 and parts[2] in ("RUN", "PEND", "WAIT", "SSUSP"):
                        still_running.add(parts[0])
                done = pending - still_running
                if done:
                    log_info(f"已完成 {len(done)} 个作业，"
                             f"剩余 {len(still_running)} 个")
                pending = still_running
            except FileNotFoundError:
                log_error("bjobs 命令未找到，停止等待")
                break


# =============================================================================
# SgeRunner - SGE 集群提交（结构与 LSF 类似）
# =============================================================================
class SgeRunner:
    """将每条激励提交到 SGE 集群（qsub），等待全部完成后汇总结果。"""

    POLL_INTERVAL = 30

    def __init__(self, script: str, args: argparse.Namespace,
                 base_env: dict[str, str]):
        self.script   = script
        self.args     = args
        self.base_env = base_env
        self.sge_extra = os.environ.get("SGE_ARGS", "-q normal.q -pe smp 1")

    def run_all(self, cases: list[dict]) -> list[dict]:
        log_info(f"SGE 模式：提交 {len(cases)} 个作业")
        job_ids  = []
        job_info = []

        for i, case in enumerate(cases):
            env  = LocalRunner(self.script, self.args, self.base_env)._build_env(case)
            jid  = self._submit_job(case, env)
            if jid:
                job_ids.append(jid)
                job_info.append((jid, case, env))

        self._wait_for_jobs(job_ids)

        results = []
        for jid, case, env in job_info:
            sim_dir = os.path.join(
                env["OUTPUT_ROOT"], env["PROJ"], "sim",
                f"{env['TC']}_{env['SEED']}"
            )
            result_json = os.path.join(sim_dir, "result.json")
            if os.path.isfile(result_json):
                with open(result_json) as f:
                    results.append(json.load(f))
        return results

    def _submit_job(self, case: dict, env: dict) -> str | None:
        job_name = f"uvm_{env['PROJ']}_{case['case_id']}"
        log_dir  = os.path.join(env["OUTPUT_ROOT"], env["PROJ"], "sge_logs")
        os.makedirs(log_dir, exist_ok=True)

        qsub_cmd = ["qsub"]
        qsub_cmd += self.sge_extra.split()
        qsub_cmd += ["-N", job_name, "-o", log_dir, "-e", log_dir]
        qsub_cmd += ["bash", self.script]

        log_cmd(f"qsub -N {job_name}")

        try:
            result = subprocess.run(
                qsub_cmd, env=env,
                capture_output=True, text=True
            )
            # qsub 输出格式：Your job 12345 ("job_name") has been submitted
            match = re.search(r"job (\d+)", result.stdout)
            if match:
                return match.group(1)
        except FileNotFoundError:
            log_error("qsub 命令未找到，请确认 SGE 环境已配置")
        return None

    def _wait_for_jobs(self, job_ids: list[str]) -> None:
        pending = set(job_ids)
        while pending:
            time.sleep(self.POLL_INTERVAL)
            try:
                result = subprocess.run(
                    ["qstat", "-j"] + list(pending),
                    capture_output=True, text=True
                )
                # qstat 返回空或 error 表示作业已完成
                still_running = set()
                for jid in pending:
                    if jid in result.stdout:
                        still_running.add(jid)
                pending = still_running
            except FileNotFoundError:
                break


# =============================================================================
# RegressionSession - 管理一次完整的回归执行
# =============================================================================
class RegressionSession:
    """
    协调一次完整回归：选择运行器、执行用例、记录种子、生成报告。
    """

    def __init__(self, args: argparse.Namespace, base_env: dict[str, str]):
        self.args     = args
        self.base_env = base_env
        self.script   = os.path.join(
            os.environ["REPO_ROOT"], "scripts", "vcs_run.sh"
        )
        self.start_time = datetime.datetime.now()

        # 报告输出目录（按时间戳隔离，保留历史）
        ts = self.start_time.strftime("%Y%m%d_%H%M%S")
        self.report_dir = os.path.join(
            base_env["OUTPUT_ROOT"], args.proj, "reports", ts
        )
        os.makedirs(self.report_dir, exist_ok=True)

        # 种子记录文件（全项目共用，追加写入）
        self.seed_record_path = os.path.join(
            base_env["OUTPUT_ROOT"], args.proj, "seed_record.csv"
        )

    def run(self, cases: list[dict]) -> bool:
        """执行回归，返回是否全部通过"""
        total = len(cases)
        if total == 0:
            log_warn("没有匹配的激励，请检查过滤条件")
            return False

        log_info(f"准备运行 {total} 条激励，提交方式: {self.args.submit}")

        # 选择运行器
        runner = self._get_runner()
        results = runner.run_all(cases)

        # 补全 tags 字段（result.json 中可能没有 tags）
        case_map = {c["case_id"]: c for c in cases}
        for r in results:
            if not r.get("tags"):
                c = case_map.get(r.get("case_id"), {})
                r["tags"] = c.get("case_tag", [])

        end_time = datetime.datetime.now()

        # 写入种子记录
        self._record_seeds(results)

        # 生成报告
        self._generate_reports(results, end_time)

        # 打印汇总
        return self._print_summary(results)

    def _get_runner(self):
        submit = self.args.submit
        if submit == "lsf":
            return LsfRunner(self.script, self.args, self.base_env)
        elif submit == "sge":
            return SgeRunner(self.script, self.args, self.base_env)
        else:
            return LocalRunner(self.script, self.args, self.base_env)

    def _record_seeds(self, results: list[dict]) -> None:
        """将本次运行的种子记录到 seed_record.csv"""
        recorder = SeedRecorder(self.seed_record_path)
        for r in results:
            recorder.append(r)
        log_info(f"种子记录已更新: {self.seed_record_path}")

    def _generate_reports(self, results: list[dict],
                          end_time: datetime.datetime) -> None:
        """生成 HTML + CSV 报告，并保存 results.json"""
        data = {
            "proj":       self.args.proj,
            "start_time": self.start_time.strftime("%Y-%m-%d %H:%M:%S"),
            "end_time":   end_time.strftime("%Y-%m-%d %H:%M:%S"),
            "cases":      results,
        }
        # 保存原始结果 JSON（便于后续独立调用 gen_report.py）
        results_json = os.path.join(self.report_dir, "results.json")
        with open(results_json, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)

        HtmlReportGenerator(data, f"{self.args.proj} 回归报告").generate(
            os.path.join(self.report_dir, "report.html"))
        CsvReportGenerator(data).generate(
            os.path.join(self.report_dir, "report.csv"))

    def _print_summary(self, results: list[dict]) -> bool:
        passed = [r for r in results if r.get("passed")]
        failed = [r for r in results if not r.get("passed")]
        total  = len(results)

        print(f"\n{'='*60}")
        print(f" 回归汇总  ({datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')})")
        print(f"{'='*60}")
        print(f" 总计: {total}  "
              f"{GREEN}PASS: {len(passed)}{NC}  "
              f"{RED}FAIL: {len(failed)}{NC}  "
              f"通过率: {len(passed)/total*100:.1f}%" if total else "")

        if failed:
            print(f"\n{RED} 失败的激励:{NC}")
            for r in failed:
                to_str = " [TIMEOUT]" if r.get("timed_out") else ""
                print(f"   [{r['case_id']}] {r['case_name']}  "
                      f"seed={r.get('seed','?')}{to_str}")

        print(f"\n 报告目录: {self.report_dir}")
        print(f" 种子记录: {self.seed_record_path}")
        print(f"{'='*60}")
        return len(failed) == 0


# =============================================================================
# 参数解析
# =============================================================================
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="UVM 验证激励管理与回归运行脚本",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("--proj", required=True,
                        help="项目名称（verif/ 下的子目录名）")

    # 过滤选项
    f = parser.add_argument_group("过滤选项（不指定则运行全部激励）")
    f.add_argument("--tag",   nargs="+", metavar="TAG",
                   help="按 case_tag 过滤，多个 tag 取并集")
    f.add_argument("--id",    nargs="+", metavar="ID",
                   help="按 case_id 过滤")
    f.add_argument("--name",  nargs="+", metavar="NAME",
                   help="按 case_name 精确匹配过滤")
    f.add_argument("--regex", metavar="PATTERN",
                   help="按正则表达式匹配 case_name 过滤\n"
                        "示例: --regex 'write.*test'  --regex '^base'")
    f.add_argument("--rerun", action="store_true",
                   help="重跑上次回归中失败的用例（保留原种子）")

    # 运行选项
    r = parser.add_argument_group("运行选项")
    r.add_argument("--seed",       default="random",
                   help="仿真随机种子（默认: random）")
    r.add_argument("--verbose",    default="UVM_MEDIUM",
                   help="UVM 打印级别（默认: UVM_MEDIUM）")
    r.add_argument("--timeout",    type=int, default=3600,
                   help="单条激励超时秒数（默认: 3600）")
    r.add_argument("--wave",       action="store_true",
                   help="开启波形转储（FSDB）")
    r.add_argument("--wave_scope", default="",
                   help="波形转储范围（默认全量，如 tb_top.u_dut）")
    r.add_argument("--code_cov",   action="store_true",
                   help="开启代码覆盖率统计")
    r.add_argument("--func_cov",   action="store_true",
                   help="开启功能覆盖率统计")
    r.add_argument("--auto_debug", action="store_true",
                   help="仿真结束后自动打开波形（需同时 --wave）")
    r.add_argument("--jobs",       type=int, default=1,
                   help="本地并行作业数（默认: 1）")
    r.add_argument("--submit",     default="local",
                   choices=["local", "lsf", "sge"],
                   help="提交方式: local（默认）/ lsf / sge")
    r.add_argument("--dry_run",    action="store_true",
                   help="仅打印命令，不实际执行仿真")

    return parser.parse_args()


# =============================================================================
# 入口
# =============================================================================
def main():
    args = parse_args()

    repo_root = os.environ.get("REPO_ROOT", "")
    if not repo_root:
        log_error("REPO_ROOT 未设置，请通过 Makefile 调用或手动 export REPO_ROOT")
        sys.exit(1)

    # 基础环境变量
    base_env = dict(os.environ)
    base_env["PROJ"]        = args.proj
    base_env["OUTPUT_ROOT"] = os.path.join(repo_root, "output")

    # --rerun：从种子记录中读取上次失败的用例
    seed_record_path = os.path.join(
        base_env["OUTPUT_ROOT"], args.proj, "seed_record.csv"
    )

    if args.rerun:
        recorder = SeedRecorder(seed_record_path)
        failed   = recorder.get_failed_cases()
        if not failed:
            log_warn("没有找到失败记录，请先运行一次回归")
            sys.exit(0)
        log_info(f"rerun 模式：重跑 {len(failed)} 条失败激励（保留原种子）")

        # 加载完整 case_list.json
        json_path = os.path.join(repo_root, "verif", args.proj, "case_list.json")
        parser    = CaseParser(json_path).load()
        case_map  = {c["case_id"]: c for c in parser.cases}

        # 将失败记录中的种子注入 case，并以此种子运行
        cases_to_run = []
        for row in failed:
            case = dict(case_map.get(row["case_id"], {}))
            if case:
                case["_rerun_seed"] = row["seed"]
                cases_to_run.append(case)
            else:
                log_warn(f"case_id={row['case_id']} 在 case_list.json 中未找到，跳过")

        # 覆盖全局种子为各自的历史种子（在 LocalRunner 中通过 SEED env 传递）
        # 此处通过逐条设置 SEED 来实现
        session = RegressionSession(args, base_env)
        results = []
        runner  = LocalRunner(session.script, args, base_env)
        for i, case in enumerate(cases_to_run):
            rerun_seed = case.pop("_rerun_seed", args.seed)
            # 临时修改 args.seed（线程安全问题在此场景可忽略，rerun 默认串行）
            orig_seed  = args.seed
            args.seed  = rerun_seed
            result = runner._run_one(case, i+1, len(cases_to_run))
            args.seed = orig_seed
            results.append(result)

        # 补全 tags
        for r in results:
            if not r.get("tags"):
                c = case_map.get(r.get("case_id"), {})
                r["tags"] = c.get("case_tag", [])

        session._record_seeds(results)
        session._generate_reports(results, datetime.datetime.now())
        ok = session._print_summary(results)
        sys.exit(0 if ok else 1)

    # 正常回归流程
    json_path = os.path.join(repo_root, "verif", args.proj, "case_list.json")
    cases     = CaseParser(json_path).load().cases
    matched   = CaseFilter(cases).filter(
        tags=args.tag, ids=args.id, names=args.name, regex=args.regex
    )
    log_info(f"过滤后匹配激励: {len(matched)} 条")

    session = RegressionSession(args, base_env)
    ok      = session.run(matched)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
