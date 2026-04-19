# RSA 硬件加速器 规格说明书

**版本**：v0.1 草稿  
**最后更新**：2026-04-19  
**场景定位**：安全加速卡（已确认）

---

## 决策记录

| # | 决策项 | 状态 | 结论 |
|---|--------|------|------|
| 1 | 产品定位 | ✅ 已确认 | 安全加速卡（**本版聚焦简单电路原型**） |
| 2 | 支持算法范围 | ✅ 已确认 | **仅 RSA**（ECC/PQC 等后续新建工程） |
| 3 | 支持 Key 长度 | ✅ 已确认 | **仅 RSA-2048** |
| 4 | 支持操作类型 | ✅ 已确认 | **Sign / Verify / Encrypt / Decrypt 全支持**（共用两条硬件路径） |
| 5 | Padding 方案 | ✅ 已确认 | **仅 Raw 模幂**（padding/Hash/RNG 由软件处理） |
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

**安全加速卡**：以独立硬件卡形式插入服务器，通过主机接口（TBD）卸载 CPU 的
非对称加密运算。

### 1.1 本版本范围（v0.1 原型）

- **仅支持 RSA**，不包含 ECC、EdDSA、PQC 等其他非对称算法
- **目标：出一个功能完整但结构简单的 RSA 电路**，验证算法正确性与微架构思路
- ECC、多算法支持、通用大数协处理器形态等扩展，**新建独立工程处理**（不在本 spec 范围内）

### 1.2 设计取向

- **简单优先**：控制器倾向固定 FSM 而非微码（待决策 E 确认）
- **功能优先**：先跑通签名/验签，性能/安全指标后续逐步加强
- **可扩展性后置**：不为将来 ECC/PQC 预留通用接口

### 1.3 支持操作类型（已确认：Sign / Verify / Encrypt / Decrypt 全支持）

| 操作 | 数学运算 | 硬件路径 | 用途 |
|------|---------|---------|------|
| **Sign**（签名） | `s = m^d mod n` | 私钥路径 | 签发证书、签代码、签 TLS 握手 |
| **Verify**（验签） | `m = s^e mod n` | 公钥路径 | 验证签名真实性 |
| **Encrypt**（加密） | `c = m^e mod n` | 公钥路径 | 发送密文给私钥持有者 |
| **Decrypt**（解密） | `m = c^d mod n` | 私钥路径 | 解密接收到的密文 |

**硬件路径分析**：Sign ≡ Decrypt（都是 `^d mod n`）；Verify ≡ Encrypt（都是 `^e mod n`）。
实际只有**两条硬件路径**：

- **私钥路径**：Montgomery Ladder + CRT + blinding，用于 Sign / Decrypt
- **公钥路径**：Square-and-Multiply + e=65537 快速路径，用于 Verify / Encrypt

四种操作共用底层电路，差异仅在 CMD 编码与顶层数据流。

### 1.4 Padding 方案（已确认：Raw 模幂，硬件不做 padding）

硬件仅提供**纯粹的模幂引擎**，接口即是数学定义：

- 私钥路径输入：`(m, d, n, p, q, dp, dq, qInv)` → 输出 `s = m^d mod n`
- 公钥路径输入：`(m, e, n)` → 输出 `c = m^e mod n`

不在硬件范围内的任务（**由软件完成**）：
- PKCS#1 v1.5 / PSS / OAEP padding 的字节编排
- 消息 Hash（SHA-2/3 等）
- MGF1 掩码生成
- padding 所需随机数生成

优势：
- 硬件最简单，只做一件事（模幂）
- 无需 Hash / MGF1 / RNG 协处理，面积最小
- 验证简单：直接对数学函数对拍即可
- 未来产品化时，padding 逻辑可在更高层（软件驱动 / FW / wrapper）加，
  不影响核心电路稳定性

### 1.5 Key 长度（已确认：仅 RSA-2048）

| 参数 | 值 |
|------|----|
| 模数 n 位宽 | 2048 bit |
| 公钥 e 位宽 | 固定 17 bit（65537，硬编码） |
| 私钥 d 位宽 | 2048 bit |
| CRT 半宽 p / q | 1024 bit |
| CRT 半指数 dp / dq | 1024 bit |
| 签名 / 密文位宽 | 2048 bit |

原因：
- 原型阶段单一 bit 宽，FSM 迭代计数可硬编码，控制最简单
- 2048-bit 是 TLS / PKI 主流，2030 年前仍满足 NIST SP 800-57 安全
- 3072 / 4096 / 1024 的支持留给后续新工程扩展

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

---

# 附录 B：ECC 背景与 RSA vs ECC 对比（参考资料）

## B.1 ECC 是什么

**ECC = Elliptic Curve Cryptography（椭圆曲线密码学）**，和 RSA 一样属于非对称加密
（公钥/私钥），但数学基础完全不同：

- **RSA**：基于大整数分解难题（`n = p·q`，已知 n 难分解出 p、q）
- **ECC**：基于椭圆曲线离散对数难题（ECDLP，已知 `Q = k·P` 难反推标量 k）

核心运算：
- RSA：**模幂** `m^e mod n`（大整数乘法）
- ECC：**点乘** `k·P`（曲线上点的反复加/倍）

## B.2 RSA vs ECC 全面对比

| 项 | RSA | ECC |
|---|-----|-----|
| 数学基础 | 大整数分解 | 椭圆曲线离散对数 |
| 核心运算 | 模幂（大数乘法） | 点乘（点加 + 倍点） |
| 操作数位宽 | 2048 / 3072 / 4096 bit | **256 / 384 bit** |
| 等效安全强度 | RSA-2048 ≈ ECC-224 | ECC-256 ≈ RSA-3072 |
| 签名速度 | 慢（大数模幂） | **快 5~10×** |
| 验签速度 | 快（e=65537） | 慢（无类似 e 的捷径） |
| 密钥长度 | 2048-bit = 256 字节 | 256-bit = **32 字节（小 8×）** |
| 签名长度 | ~256 字节 | **~64 字节（小 4×）** |
| 抗量子 | ❌ Shor 算法可破 | ❌ Shor 算法可破 |

## B.3 ECC 的主流使用场景

**TLS 1.3 握手几乎全部使用 ECC**：
- `ECDHE`（椭圆曲线 Diffie-Hellman）做密钥协商
- `ECDSA` 或 `EdDSA`（Ed25519）做签名
- 传统 `RSA key exchange` 已被 TLS 1.3 废弃
- 不支持 ECC 的加速卡在 TLS 卸载市场基本失去竞争力

**常见曲线**：

| 曲线 | 位宽 | 说明 |
|------|------|------|
| P-256（secp256r1） | 256-bit | NIST 标准，硬件加速最广 |
| P-384 | 384-bit | NSA Suite B 高强度要求 |
| P-521 | 521-bit | 最高强度，业界用得少 |
| Curve25519 / Ed25519 | 256-bit | Google/Signal/OpenSSH，设计抗实现错误 |
| secp256k1 | 256-bit | 比特币、以太坊专用 |

## B.4 ECC 的硬件实现差异

ECC 点乘本质上是**大量小位宽模乘**（以 256-bit 为主）：

- 一次点乘 ≈ 256 次点加 + 256 次倍点
- 每次点加/倍点内部 ≈ 十几次 256-bit 模乘
- **底层 Montgomery 模乘单元与 RSA 可复用**，仅位宽和指令序列不同

这就是为什么商用加速器（Thales、Cavium、OpenTitan OTBN）多选"**通用大数协处理器**"
路线：底层硬件共用，上层微码/软件决定算 RSA 还是 ECC。

## B.5 对本项目"决策 #2（算法范围）"的影响

| 选项 | 说明 | 硬件影响 | 市场适应性 |
|------|------|---------|-----------|
| A. 仅 RSA | 只支持 2048/3072/4096-bit 模幂 | MAC 位宽固定 64-bit，FSM 简单 | PKI 签发/代码签名 OK；TLS 卸载市场受限 |
| B. RSA + ECC (P-256/P-384) | 覆盖主流 TLS 算法 | 可复用 Montgomery 单元，面积 +20~30%；需参数化控制器 | TLS 卸载主流需求 |
| C. 通用大数协处理器 | 指令可编程 | 面积 +40~60%；控制复杂度高 | 覆盖 RSA/ECC/Ed25519/未来 PQC 过渡 |

> 决策 #2 待定。
