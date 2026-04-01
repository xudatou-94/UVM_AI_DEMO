# sjtag2apb 调试记录

---

## 问题一：vcs_compile.sh 覆盖率开关变量错误

**文件**：`scripts/vcs_compile.sh`

**错误现象**：  
编译时覆盖率相关代码使用了未定义的 `COV` 环境变量，导致编译失败。

**根因**：  
Makefile 中覆盖率分为 `CODE_COV`（代码覆盖率）和 `FUNC_COV`（功能覆盖率）两个独立开关，但 `vcs_compile.sh` 中统一使用了 `COV`，与 Makefile 传入的变量名不匹配。

**修复**：  
将原来的单一 `COV` 判断拆分为两个独立分支：

```bash
# 修复前
if [ "${COV}" = "1" ]; then
    VCS_CMD+=" -cm line+cond+fsm+tgl+branch"
    VCS_CMD+=" -cm_dir ${COMPILE_DIR}/coverage"
fi

# 修复后
if [ "${CODE_COV}" = "1" ]; then
    VCS_CMD+=" -cm line+cond+fsm+tgl+branch"
    VCS_CMD+=" -cm_dir ${COMPILE_DIR}/coverage"
fi
if [ "${FUNC_COV}" = "1" ]; then
    VCS_CMD+=" -ntb_opts cover"
fi
```

---

## 问题二：apb_if.sv 中使用了 UVM 宏

**文件**：`vip/apb/apb_if.sv`

**错误信息**：
```
error-[IND] Identifier not declared
/vip/apb/apb_if.sv, 123
  Identifier 'UVM_NONE' has not been declared yet.
```

**根因**：  
Interface 文件在 `package` 之外单独编译，无法 `import uvm_pkg`，因此 `` `uvm_error `` 等 UVM 宏在 interface 中不可用。

**修复**：  
将 SVA assertion 的 else 分支中的 `` `uvm_error `` 替换为标准 SystemVerilog 的 `$error`：

```systemverilog
// 修复前
assert property (p_setup_penable)
  else `uvm_error("APB_IF", "APB 违例：SETUP 阶段 PENABLE 不为 0")

// 修复后
assert property (p_setup_penable)
  else $error("APB_IF: APB 违例：SETUP 阶段 PENABLE 不为 0");
```

三处 SVA（`p_setup_penable`、`p_access_penable`、`p_addr_stable`）均做了相同修改。
