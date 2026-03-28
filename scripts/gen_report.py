#!/usr/bin/env python3
# =============================================================================
# gen_report.py - 回归报告生成工具
#
# 功能：
#   1. 读取回归结果（JSON 格式）
#   2. 生成 HTML 可视化报告（含 PASS/FAIL 彩色表格、统计摘要）
#   3. 生成 CSV 报告（便于脚本处理或导入 Excel）
#
# 使用方式：
#   python3 gen_report.py --results <results.json> --output <报告目录>
#   python3 gen_report.py --results <results.json> --output <报告目录> --title "APB 回归报告"
#
# results.json 格式（由 run_cases.py 生成）：
#   {
#     "proj": "apb_slave",
#     "start_time": "2026-03-28 13:00:00",
#     "end_time": "2026-03-28 14:30:00",
#     "cases": [
#       {
#         "case_id": "TC_001",
#         "case_name": "write_test",
#         "seed": 12345,
#         "passed": true,
#         "uvm_fatal": 0,
#         "uvm_error": 0,
#         "duration": 42.3,
#         "log": "/path/to/sim.log",
#         "tags": ["smoke", "write"]
#       }
#     ]
#   }
# =============================================================================

import os
import sys
import csv
import json
import argparse
import datetime
from typing import Any


# =============================================================================
# HTML 报告生成器
# =============================================================================
class HtmlReportGenerator:
    """生成 HTML 格式的回归报告"""

    def __init__(self, data: dict[str, Any], title: str):
        self.data   = data
        self.title  = title
        self.cases  = data.get("cases", [])
        self.passed = [c for c in self.cases if c.get("passed")]
        self.failed = [c for c in self.cases if not c.get("passed")]

    def generate(self, output_path: str) -> None:
        """生成 HTML 文件"""
        html = self._build_html()
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(html)
        print(f"[INFO] HTML 报告已生成: {output_path}")

    def _build_html(self) -> str:
        total      = len(self.cases)
        pass_count = len(self.passed)
        fail_count = len(self.failed)
        pass_rate  = f"{pass_count/total*100:.1f}%" if total > 0 else "N/A"

        proj       = self.data.get("proj", "unknown")
        start_time = self.data.get("start_time", "")
        end_time   = self.data.get("end_time", "")

        rows = ""
        for c in self.cases:
            bg    = "#d4edda" if c.get("passed") else "#f8d7da"
            badge = '<span style="color:#155724;font-weight:bold">PASS</span>' \
                    if c.get("passed") else \
                    '<span style="color:#721c24;font-weight:bold">FAIL</span>'
            log_link = ""
            if c.get("log") and os.path.isfile(c["log"]):
                log_link = f'<a href="{c["log"]}">log</a>'
            tags = ", ".join(c.get("tags", []))
            duration = f'{c.get("duration", 0):.1f}s'
            rows += f"""
            <tr style="background:{bg}">
                <td>{c.get("case_id","")}</td>
                <td>{c.get("case_name","")}</td>
                <td>{tags}</td>
                <td>{c.get("seed","")}</td>
                <td>{badge}</td>
                <td>{c.get("uvm_fatal",0)}</td>
                <td>{c.get("uvm_error",0)}</td>
                <td>{duration}</td>
                <td>{log_link}</td>
            </tr>"""

        return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{self.title}</title>
    <style>
        body  {{ font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }}
        h1    {{ color: #333; }}
        .summary {{
            display: flex; gap: 20px; margin-bottom: 20px; flex-wrap: wrap;
        }}
        .card {{
            background: white; border-radius: 8px; padding: 16px 24px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center;
            min-width: 120px;
        }}
        .card .num  {{ font-size: 2em; font-weight: bold; }}
        .card .label {{ color: #666; font-size: 0.9em; }}
        .pass-card .num {{ color: #28a745; }}
        .fail-card .num {{ color: #dc3545; }}
        .info-card .num {{ color: #007bff; }}
        table {{
            width: 100%; border-collapse: collapse;
            background: white; border-radius: 8px;
            overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        th {{
            background: #343a40; color: white;
            padding: 10px 12px; text-align: left;
        }}
        td {{ padding: 8px 12px; border-bottom: 1px solid #dee2e6; }}
        tr:hover {{ filter: brightness(0.97); }}
        .meta {{ color: #666; font-size: 0.9em; margin-bottom: 16px; }}
    </style>
</head>
<body>
    <h1>{self.title}</h1>
    <div class="meta">
        项目: <b>{proj}</b> &nbsp;|&nbsp;
        开始: {start_time} &nbsp;|&nbsp;
        结束: {end_time}
    </div>

    <div class="summary">
        <div class="card info-card">
            <div class="num">{total}</div>
            <div class="label">总计</div>
        </div>
        <div class="card pass-card">
            <div class="num">{pass_count}</div>
            <div class="label">PASS</div>
        </div>
        <div class="card fail-card">
            <div class="num">{fail_count}</div>
            <div class="label">FAIL</div>
        </div>
        <div class="card">
            <div class="num">{pass_rate}</div>
            <div class="label">通过率</div>
        </div>
    </div>

    <table>
        <thead>
            <tr>
                <th>Case ID</th>
                <th>Case Name</th>
                <th>Tags</th>
                <th>Seed</th>
                <th>Result</th>
                <th>FATAL</th>
                <th>ERROR</th>
                <th>耗时</th>
                <th>日志</th>
            </tr>
        </thead>
        <tbody>
            {rows}
        </tbody>
    </table>

    <p style="color:#999;font-size:0.8em;margin-top:16px;">
        生成时间: {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
    </p>
</body>
</html>"""


# =============================================================================
# CSV 报告生成器
# =============================================================================
class CsvReportGenerator:
    """生成 CSV 格式的回归报告"""

    FIELDS = ["case_id", "case_name", "tags", "seed",
              "result", "uvm_fatal", "uvm_error", "duration", "log"]

    def __init__(self, data: dict[str, Any]):
        self.cases = data.get("cases", [])

    def generate(self, output_path: str) -> None:
        with open(output_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=self.FIELDS)
            writer.writeheader()
            for c in self.cases:
                writer.writerow({
                    "case_id":   c.get("case_id", ""),
                    "case_name": c.get("case_name", ""),
                    "tags":      "|".join(c.get("tags", [])),
                    "seed":      c.get("seed", ""),
                    "result":    "PASS" if c.get("passed") else "FAIL",
                    "uvm_fatal": c.get("uvm_fatal", 0),
                    "uvm_error": c.get("uvm_error", 0),
                    "duration":  f'{c.get("duration", 0):.1f}',
                    "log":       c.get("log", ""),
                })
        print(f"[INFO] CSV 报告已生成: {output_path}")


# =============================================================================
# 种子记录 CSV 工具
# =============================================================================
class SeedRecorder:
    """
    将每次仿真的种子记录到 seed_record.csv，便于失败重现。

    CSV 格式：
        case_id, case_name, seed, result, timestamp, log
    """

    FIELDS = ["case_id", "case_name", "seed", "result", "timestamp", "log"]

    def __init__(self, record_path: str):
        self.record_path = record_path

    def append(self, case_result: dict[str, Any]) -> None:
        """追加一条种子记录"""
        write_header = not os.path.isfile(self.record_path)
        with open(self.record_path, "a", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=self.FIELDS)
            if write_header:
                writer.writeheader()
            writer.writerow({
                "case_id":   case_result.get("case_id", ""),
                "case_name": case_result.get("case_name", ""),
                "seed":      case_result.get("seed", ""),
                "result":    "PASS" if case_result.get("passed") else "FAIL",
                "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "log":       case_result.get("log", ""),
            })

    def get_last_seed(self, case_id: str) -> str | None:
        """查询指定 case_id 最近一次的仿真种子"""
        if not os.path.isfile(self.record_path):
            return None
        last_seed = None
        with open(self.record_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get("case_id") == case_id:
                    last_seed = row.get("seed")  # 保留最后一条
        return last_seed

    def get_failed_cases(self) -> list[dict]:
        """获取最近一次回归中所有失败的用例（按 case_id 去重，保留最新）"""
        if not os.path.isfile(self.record_path):
            return []
        latest: dict[str, dict] = {}
        with open(self.record_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                latest[row["case_id"]] = row
        return [r for r in latest.values() if r.get("result") == "FAIL"]


# =============================================================================
# 入口（独立调用时使用）
# =============================================================================
def main():
    parser = argparse.ArgumentParser(description="回归报告生成工具")
    parser.add_argument("--results", required=True,
                        help="回归结果 JSON 文件路径")
    parser.add_argument("--output",  required=True,
                        help="报告输出目录")
    parser.add_argument("--title",   default="UVM 回归报告",
                        help="报告标题（默认: UVM 回归报告）")
    args = parser.parse_args()

    if not os.path.isfile(args.results):
        print(f"[ERROR] results 文件不存在: {args.results}", file=sys.stderr)
        sys.exit(1)

    with open(args.results, "r", encoding="utf-8") as f:
        data = json.load(f)

    os.makedirs(args.output, exist_ok=True)

    HtmlReportGenerator(data, args.title).generate(
        os.path.join(args.output, "report.html"))
    CsvReportGenerator(data).generate(
        os.path.join(args.output, "report.csv"))


if __name__ == "__main__":
    main()
