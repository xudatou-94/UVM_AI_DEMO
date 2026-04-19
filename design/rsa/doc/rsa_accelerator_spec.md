# RSA 硬件加速器 规格说明书

**版本**：v0.1 草稿  
**最后更新**：2026-04-19  
**场景定位**：安全加速卡（已确认）

---

## 决策记录

| # | 决策项 | 状态 | 结论 |
|---|--------|------|------|
| 1 | 产品定位 | ✅ 已确认 | 安全加速卡 |
| 2 | 支持算法范围 | ⬜ TBD | — |
| 3 | 支持 Key 长度 | ⬜ TBD | — |
| 4 | 支持操作类型 | ⬜ TBD | — |
| 5 | Padding 方案 | ⬜ TBD | — |
| 6 | 性能目标（ops/s） | ⬜ TBD | — |
| 7 | 工艺节点 / 目标频率 | ⬜ TBD | — |
| 8 | 主机接口类型 | ⬜ TBD | — |
| 9 | 密钥槽数量 | ⬜ TBD | — |
| 10 | 安全等级（FIPS 140-3 Level） | ⬜ TBD | — |
| 11 | 是否内置 TRNG | ⬜ TBD | — |
| 12 | 是否内置 Hash 引擎 | ⬜ TBD | — |
| 13 | 功耗预算 | ⬜ TBD | — |
| A | 私钥模幂算法 | ✅ 已确认 | Montgomery Ladder + CRT + exponent/message blinding |
| B | 公钥模幂算法 | ⬜ TBD | — |
| C | 模乘算法 | ⬜ TBD | — |
| D | 数据通路位宽（MAC） | ⬜ TBD | — |
| E | 控制方式（FSM / 微码） | ⬜ TBD | — |

---

## 1. 产品定位

**安全加速卡**：以独立硬件卡形式插入服务器，通过主机接口（TBD）卸载 CPU 的非对称加密运算。典型场景（待决策后进一步细化）：TLS 握手卸载、PKI 证书签发、代码签名、密钥管理。

---

## 2. 算法层

### 2.1 私钥模幂算法（已确认）

**选定：Montgomery Ladder + CRT + exponent/message blinding**

```
私钥路径（签名 / 解密）：
  1. Exponent blinding：d' = d + r · λ(n)，r 为每次新鲜随机数
  2. Message blinding ：m' = m · r_m^e mod n
  3. CRT 分解：
       mp = m'^dp mod p   （1024-bit 或 TBD-bit 模幂）
       mq = m'^dq mod q
  4. 每一次模幂采用 Montgomery Ladder 实现（常数时间）
  5. CRT 合并：s' = CRT_combine(mp, mq, p, q, qInv)
  6. 去除 blinding：s = s' / r_m mod n
  7. Fault check（Bellcore 防护）：验证 s^e mod n == H(m)，
     不通过则 zeroize 并触发 FATAL 告警，禁止输出
```

安全属性：
- 常数时间执行（无 key-bit 分支）→ 抵抗 SPA / timing attack
- Exponent blinding → 抵抗 DPA / template attack
- Message blinding → 抵抗 chosen-ciphertext DPA
- CRT fault check → 抵抗 Bellcore 故障注入攻击

### 2.2 公钥模幂算法（TBD）

待决策。候选：
- Square-and-Multiply（e=65537 公开，无需防护，极快）
- 其他

### 2.3 其余算法参数（TBD）

- 模乘算法：TBD（候选：Montgomery Multiplication）
- 数据通路位宽：TBD
- 控制方式（FSM / 微码）：TBD

---

## 3. 微架构（TBD）

待算法层决策完成后填写。

---

## 4. 安全设计（TBD）

威胁模型和防护措施将在确认安全等级（FIPS 140-3 Level）后细化。
私钥模幂路径的防护已在 2.1 节明确。

---

## 5. 主机接口（TBD）

接口类型、寄存器映射、DMA 设计待决策 #8 确认后填写。

---

## 6. 验证计划（TBD）

待 RTL 架构基本成形后，参考 sjtag2apb 验证框架制定。

---

---

# 附录 A：模幂算法对比（参考资料）

## A.1 背景

RSA 的核心操作是 `c = m^e mod n`，其中 `e` 和 `n` 为 2048~4096 bit 大数。
不可先算 `m^e` 后取模（中间值为天文数字），必须按 `e` 的二进制位逐步迭代，
每步做**平方**和**乘法**并立刻模 `n`。
一次模幂 ≈ O(log e) 次模乘，对 2048-bit key 约 **3000 次大数模乘**。
算法目标：用最少模乘次数、最安全的方式完成这一迭代。

---

## A.2 Square-and-Multiply（平方-乘法法）

逐 bit 扫描指数，每位做一次平方，bit=1 时再做一次乘法。

```python
result = 1
for bit in bits(d, high_to_low):
    result = result^2 mod n          # 每轮必做
    if bit == 1:
        result = result * m mod n    # 仅 bit=1 时做
```

| 项 | 评价 |
|----|------|
| 2048-bit 模乘次数 | 平均 ~3072 次 |
| 硬件实现 | 极简，小型 FSM |
| **致命缺陷** | 分支依赖 key bit，SPA 可直接读出私钥 d |
| 适用 | 公钥路径（e=65537 公开，无需防护）✅；私钥路径 ❌ |

---

## A.3 Montgomery Ladder（蒙哥马利阶梯法）

无论 bit 为 0 还是 1，操作序列完全相同，只是变量互换。

```python
R0, R1 = 1, m
for bit in bits(d, high_to_low):
    if bit == 0:
        R1 = R0 * R1 mod n;  R0 = R0^2 mod n
    else:
        R0 = R0 * R1 mod n;  R1 = R1^2 mod n
```

| 项 | 评价 |
|----|------|
| 2048-bit 模乘次数 | 恒定 ~4096 次（比 S&M 慢 ~30%） |
| 抗 SPA | ✅ 天然常数时间 |
| 抗 DPA | △（需配合 blinding） |
| 硬件实现 | 需两组寄存器，控制简单 |
| 适用 | **私钥路径首选** ✅ |

---

## A.4 Sliding Window（滑动窗口法）

一次处理 `w` 个 bit，预计算 `m^1, m^3, m^5...` 存表，遇到 1-run 整体乘一次。

| 项 | 评价 |
|----|------|
| 2048-bit 模乘次数（w=4） | ~2560 次（比 S&M 快 ~17%，比 Ladder 快 ~37%） |
| 预计算开销 | 2^(w-1) 个表项，需额外 SRAM |
| **安全缺陷** | 0-run 跳过长度与 d 相关 → timing leak；表地址泄露 key |
| 适用 | 需配合 blinding + 固定访问模式，适合性能优先场景 |

---

## A.5 Fixed Window / m-ary（固定窗口法）

Sliding Window 变体：强制窗口宽度固定，不跳 0-run。

| 项 | 评价 |
|----|------|
| 2048-bit 模乘次数（w=4） | ~2560 次 |
| 抗 SPA | △（无跳 0 分支，比 Sliding Window 好） |
| 抗 DPA | △（查表地址仍和 key 相关，需 cache 混淆） |
| 适用 | 高吞吐 TLS 场景，配合访问混淆 |

---

## A.6 Montgomery Ladder + Randomization（最高防护级别）

Ladder 的增强版：每步增加"哑操作"扰动功耗/时序。

| 项 | 评价 |
|----|------|
| 2048-bit 模乘次数 | ~4500 次（比 Ladder 再慢 10~20%） |
| 抗 SPA / DPA / 高阶攻击 | ✅ 最强 |
| 适用 | FIPS 140-3 Level 4 / CC EAL 5+ 场景 |

---

## A.7 CRT（中国剩余定理）加速

**不是独立的模幂算法，而是私钥侧的分解加速技巧**：

```
mp = m^dp mod p    （≈1/4 的计算量）
mq = m^dq mod q   （≈1/4 的计算量）
s  = CRT_combine(mp, mq)
```

| 项 | 评价 |
|----|------|
| 性能提升 | **~4×**（两个半长模幂并行时可接近） |
| **安全风险** | Bellcore CRT 故障攻击：单 bit 错误可还原私钥 |
| 必备防护 | 输出前校验 `s^e mod n == m`，失败则 FATAL |
| 适用 | 私钥路径几乎必选（业界标准）✅ |

---

## A.8 综合对比

| 算法 | 2048-bit 模乘次数 | 抗 SPA | 抗 DPA | 硬件复杂度 | 推荐场景 |
|------|:----------------:|:------:|:------:|:---------:|---------|
| Square-and-Multiply | ~3072 | ❌ | ❌ | ⭐ | 公钥路径 |
| Montgomery Ladder | ~4096 | ✅ | △ | ⭐⭐ | **私钥路径（本项目选定）** |
| Sliding Window (w=4) | ~2560 | ❌ | ❌ | ⭐⭐ | 不推荐（安全加速卡） |
| Fixed Window (w=4) | ~2560 | △ | △ | ⭐⭐⭐ | 高吞吐 TLS 场景 |
| Ladder + Randomization | ~4500 | ✅ | ✅ | ⭐⭐⭐⭐ | 最高安全等级 |
| CRT（组合 Ladder 使用） | 含 CRT 后 ~2×faster | — | — | 需 Fault Check | **私钥路径标配加速** |

> **本项目私钥路径最终选定**：**Montgomery Ladder + CRT + exponent/message blinding**（A 方案）
> 安全与性能的最佳平衡，为业界安全加速卡主流方案。
