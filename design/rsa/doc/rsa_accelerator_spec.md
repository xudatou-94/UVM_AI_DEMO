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
| 6 | 性能目标（ops/s） | ✅ 已确认 | **≥ 20 RSA-2048 Sign ops/s**（教学/Demo） |
| 7 | 工艺节点 / 目标频率 | ✅ 已确认 | **仅 RTL 仿真**，不绑定工艺；标称频率 100 MHz |
| 8 | 主机接口类型 | ✅ 已确认 | **纯 APB 32-bit**（控制 + operand 都走 APB） |
| 9 | 密钥槽数量 | ✅ 已确认 | **0 槽**（不做 Key Vault，operand 每次 APB 写入） |
| 10 | 安全等级（FIPS 140-3 Level） | ✅ 已确认 | **不声明 FIPS 等级**（仅保留 Ladder 常数时间属性） |
| 11 | 是否内置 TRNG | ✅ 已确认 | **不内置**，但顶层预留 `rand_in[31:0]` 接口 |
| 12 | 是否内置 Hash 引擎 | ✅ 已确认 | **不内置**，也不预留接口；Hash 由软件处理 |
| 13 | 功耗预算 | ⬜ TBD | — |
| A | 私钥模幂算法 | ✅ 已确认 | Montgomery Ladder + CRT + exponent/message blinding |
| B | 公钥模幂算法 | ✅ 已确认 | **复用 Montgomery Ladder**（零新增硬件） |
| C | 模乘算法 | ✅ 已确认 | **Montgomery Multiplication (CIOS)** |
| D | 数据通路位宽（MAC） | ✅ 已确认 | **32-bit MAC**（2048-bit 分 64 个 limb） |
| E | 控制方式（FSM / 微码） | ✅ 已确认 | **纯 FSM**（三层嵌套状态机） |

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

### 2.2 公钥模幂算法（已确认：复用 Montgomery Ladder）

```
公钥路径（验签 / 加密）：
  直接调用和私钥相同的 Montgomery Ladder 模幂电路，
  仅循环次数由 2048 bit（私钥）切换为 17 bit（e=65537）。
  不启用 blinding、不启用 CRT。
```

参数：

| 项 | 值 |
|----|----|
| 指数 e | 固定 65537（0x10001，17 bit） |
| 模幂位宽 | 2048 bit |
| 循环次数 | 17 次 Ladder 迭代（每次 2 个模乘） |
| 模乘次数 | ~34 次（相比 Square-and-Multiply 多一倍，但绝对延迟极小） |
| Blinding | 不启用（e 公开，无侧信道风险） |
| CRT | 不启用（公钥路径无 p/q） |

选型原因：

- **零新增硬件**：完全复用私钥路径的 Montgomery Ladder FSM 与模乘单元
- 仅需在顶层 FSM 通过 `key_type`（公钥/私钥）切换：
  * 循环计数（17 vs 2048）
  * Blinding 使能
  * CRT 使能
- 虽然理论上 Square-and-Multiply 只需 17 次模乘（比 Ladder 快 ~2×），
  但公钥路径总时长仍远小于私钥路径（~1/1000 量级），
  多做 17 次模乘对整体 latency 无实质影响
- 原型阶段"一套电路管两条路径"极大降低验证与调试复杂度

### 2.3 模乘算法（已确认：Montgomery Multiplication — CIOS 变种）

模乘是 RSA 的最热点基础操作：2048-bit 一次模幂 ≈ 4000 次 2048×2048 模乘（Ladder 下），
所有 Ladder 迭代最终都调用它。

**选定：Montgomery Multiplication — CIOS（Coarsely Integrated Operand Scanning）**

核心思想：将"求模"替换为"移位"。数据先进入 Montgomery 域（`ā = a·R mod n`，
`R = 2^k`），域内乘法时只需乘 + 加 + 右移，无需除法。

CIOS 伪码（k = limb 数；单次模乘 `c = MontMul(a, b)`）：

```
A[0..k]  = 0                       // 临时累加器，长度 k+1 limb
for i in 0..k-1:                   // 外层循环：逐 limb 扫描 b
    (Carry, A[0])   = A[0] + a[0]·b[i]
    for j in 1..k-1:               // 内层循环：乘法扩散
        (Carry, A[j]) = A[j] + a[j]·b[i] + Carry
    (Carry_h, A[k]) = A[k] + Carry
    m = A[0] · n'[0] mod 2^w       // 约简乘子（n' 预计算：n·n' ≡ -1 mod 2^w）
    (Carry, _)     = A[0] + m·n[0] // 使最低 limb 归零
    for j in 1..k-1:               // 约简扩散
        (Carry, A[j-1]) = A[j] + m·n[j] + Carry
    A[k-1] = A[k] + Carry
if A ≥ n:
    A = A - n                      // 条件减：使结果落在 [0, n)
return A[0..k-1]
```

### 2.4 CIOS 变种选型理由

| 对比 | 选择 | 说明 |
|------|------|------|
| **朴素"先乘后除"** | ❌ | 硬件除法器关键路径极长，业界已淘汰 |
| **Barrett Reduction** | ❌ | 每次模乘需 2 次全宽乘法；无明显优势 |
| **Montgomery SOS** | ❌ | 乘法全做完再约简，需要 2k-limb 中间存储 |
| **Montgomery CIOS** ✅ | 选用 | 乘/约简交替，中间仅 k+1 limb 寄存器；控制规则 |
| **Montgomery FIOS** | ❌ | 更细粒度流水，控制复杂度高，不适合原型 |
| **RNS Montgomery** | ❌ | 面积极大，服务器级吞吐卡方案，不适合原型 |

### 2.5 Montgomery 域进/出转换

- **入域**：`ā = a · R mod n`，等价于 `MontMul(a, R²)`，R² 预先计算
- **出域**：`a = ā · R⁻¹ mod n`，等价于 `MontMul(ā, 1)`
- 模幂主循环 ~4000 次模乘中，入/出域各 1 次，开销完全可忽略
- R 为 `2^k`（k = 模数位宽）；R² 可由硬件或软件在 key load 阶段预计算

### 2.6 数据通路位宽（已确认：32-bit MAC）

**limb 位宽 w = 32**，是 CIOS 乘加单元 `A[j] = A[j] + a[j]·b[i] + Carry` 的基本粒度。

| 项 | 值 |
|----|----|
| MAC 位宽 w | 32 bit |
| 乘法器规模 | 32×32 → 64 bit（单拍完成） |
| 加法器 | 64-bit 累加 + 32-bit Carry 链 |
| 2048-bit limb 数 k | 64 |
| 1024-bit（CRT 半宽）limb 数 | 32 |
| 单次 MontMul 周期（CIOS） | ~k² ≈ 4096（2048-bit）；~1024（1024-bit） |
| 单次 RSA-2048 签名模乘次数 | ≈ 4×1024 = 4096（Ladder×CRT 两半）|
| 单次 RSA-2048 签名总周期 | ≈ 4096 × 1024 ≈ 4.2M cycles（CRT 串行）|

### 2.7 选型理由

- **32×32 乘法器**是主流工艺中的"甜点"：单拍完成、面积适中、时序友好
- **64 个 limb** 让 CIOS 两层循环结构清晰，便于 FSM 实现和调试
- 性能虽非最高，但原型阶段"功能先行"：100 MHz 下 RSA-2048 签名 ~40 ms，
  demo 充分够用
- 后续升级 64-bit MAC 仅涉及乘法器和 limb 循环计数参数，CIOS 算法不变，扩展成本低
- 16-bit MAC 虽面积更小，但周期数翻 4 倍（~16M cycles），验证和功耗都不划算

### 2.8 控制方式（已确认：纯 FSM，三层嵌套状态机）

RSA 运算是天然的三层嵌套循环。本项目采用**三个分层 FSM** 实现，上层 FSM 通过
start / done 握手启动下层 FSM：

```
          start      start      start
 CMD ──▶ top_fsm ──▶ ladder_fsm ──▶ montmul_fsm
          ◀─done     ◀─done       ◀─done
```

| 层 | FSM | 职责 | 循环次数 |
|----|-----|------|---------|
| 顶层 | `rsa_top_fsm` | 解析 CMD，私/公钥路径分支，CRT 合并、fault check、zeroize | 1 次（整条命令生命周期） |
| 中层 | `ladder_fsm` | 扫描指数逐 bit 执行 Montgomery Ladder | 17 次（公钥）/ 1024 次（CRT 半，私钥）|
| 底层 | `montmul_fsm` | CIOS 双层 limb 循环（外 i / 内 j + 约简） | ~k² 次 limb 步 |

### 2.9 选型理由

- 与决策 #2（仅 RSA）、决策 #5（仅 Raw 模幂）完全契合：**流程固定，无需灵活性**
- 层次化 FSM 与嵌套循环结构一一对应，RTL 编写、仿真、调试都最直观
- 面积最小（无 ROM、无译码器、无 PC），也便于功耗估计
- 每层 FSM 状态数可控（~5~10 个状态），便于做形式化覆盖验证
- 未来若扩展到 ECC/多算法，再新建工程考虑升级为微码或指令集，不影响当前原型

---

## 3. 微架构与性能

### 3.1 性能目标（已确认：≥ 20 RSA-2048 Sign ops/s）

本版本定位为**教学/Demo 原型**，性能门槛以"跑通为先、验证友好"为准。

| 指标 | 目标 |
|------|------|
| RSA-2048 Sign（私钥路径，CRT + Ladder） | ≥ 20 ops/s |
| RSA-2048 Verify（公钥路径，e=65537） | ≥ 500 ops/s |
| RSA-2048 Decrypt | ≥ 20 ops/s（与 Sign 同路径） |
| RSA-2048 Encrypt | ≥ 500 ops/s（与 Verify 同路径） |

### 3.2 周期数估算（基于已确认参数）

| 运算 | 计算 | cycles |
|------|------|--------|
| MontMul 1024-bit（CRT 半宽，k=32 limb） | ~k² | ~1024 |
| MontMul 2048-bit（k=64 limb） | ~k² | ~4096 |
| 1024-bit 模幂（Ladder，1024 次迭代 × 2 MontMul） | 1024 × 2 × 1024 | ~2.1M |
| RSA-2048 Sign（CRT 两半 **串行** + 合并 + fault check） | 2 × 2.1M + ≲ 100K | **~4.3M** |
| RSA-2048 Verify（Ladder 17 次迭代 × 2 × 4096） | 17 × 2 × 4096 | **~140K** |

### 3.3 频率与吞吐映射

| 频率 | Sign ops/s | Verify ops/s |
|-----|:----------:|:------------:|
| 100 MHz | ≈ 24 | ≈ 700 |
| 200 MHz | ≈ 48 | ≈ 1,400 |

达成 ≥ 20 ops/s 目标**仅需 100 MHz 单 MAC、CRT 串行**，无需流水/并行优化。

### 3.4 微架构取向

- 单个 Montgomery MAC 单元（32×32 → 64-bit）
- CRT 两半**串行执行**（先 mp 后 mq，共享同一 MAC 单元）
- 无运算流水（montmul_fsm 顺序执行 CIOS 两层循环）
- 不为性能做额外优化，所有"余量"留给未来升级（提频 / CRT 并行 / MAC 扩宽）

### 3.5 工艺与综合范围（已确认：仅 RTL 仿真）

本版本**不做综合、不绑定工艺库、不做 FPGA/ASIC 物理实现**。

| 项 | 设定 |
|----|------|
| 工艺节点 | 不绑定 |
| 综合工具 | 不使用 |
| 标称频率 | 100 MHz（仅用于 timescale 与性能估算） |
| 面积估算 | 不提供 |
| 功耗估算 | 不提供 |
| 交付物 | RTL 源码 + UVM/cocotb Testbench + 功能波形 |

原因：
- 原型阶段聚焦**功能正确性**，不做产品化物理实现
- 无 EDA 商业 License / FPGA 板卡依赖，任何人拉源码即可仿真
- 100 MHz 是"假设值"：若后续真做综合，RTL 代码风格已按可综合规则编写
  （无 `initial` 驱动逻辑、无不可综合结构），迁移成本低
- 综合/FPGA 板验证可在后续新建工程中完成

---

## 4. 安全设计（已确认：不声明 FIPS 等级）

本版本**不对标任何 FIPS 140-3 安全等级**，仅保留 Montgomery Ladder 算法
本身天然具备的**常数时间**属性。所有商用 HSM 级别的硬件防护（KAT 自检、
寄存器 parity、sensor、Key Vault、故障检测、zeroize FSM 等）均**不实现**。

### 4.1 保留的安全属性

| 属性 | 提供来源 | 说明 |
|------|---------|------|
| 常数时间执行 | Montgomery Ladder（算法） | 无 key-bit 相关分支，无早退；天然抗 SPA / timing attack |
| 输入输出隔离 | APB 读写分窗口 | 结果必须通过显式读端口，不经其他通路泄露 |
| 运算结束自动清寄存器 | done 阶段硬件复位 operand 寄存器 | 减少残留 |

### 4.2 不实现的防护（有意留空）

- KAT 上电自检
- 寄存器 / SRAM parity 或 ECC
- Exponent / message blinding（依赖 TRNG，见决策 #11）
- CRT fault check（Bellcore 防护）
- 故障注入传感器（时钟、电压、温度）
- Key Vault（决策 #9 已确认无）
- zeroize 指令与安全状态机
- DFT 安全模式（scan chain 屏蔽）

原因：
- 匹配"简单电路原型"定位（决策 #1）
- 与决策 #5（仅 Raw 模幂）、#7（仅仿真）、#9（0 密钥槽）保持一致
- 所有防护都可在后续产品化工程（按 L1/L2/L3 逐级）新建模块补齐，
  不影响当前核心电路的正确性与稳定性

### 4.3 对 2.1 节私钥路径的更新

2.1 节中 blinding 与 fault check 的防护步骤，在本原型中**不实现**；
私钥路径的实际执行流程简化为：

```
私钥路径（签名 / 解密，原型简化版）：
  1. CRT 分解：
       mp = m^dp mod p
       mq = m^dq mod q
  2. 每一次模幂采用 Montgomery Ladder（常数时间）
  3. CRT 合并：s = CRT_combine(mp, mq, p, q, qInv)
  4. 输出 s
```

blinding / fault check 作为已知的扩展点，在决策 #11（TRNG）与后续产品化工程中再启用。

### 4.4 TRNG 接口（已确认：不内置，预留端口）

本版本**不实现 TRNG**，但顶层预留随机数输入接口，方便后续产品化工程挂载
外部 TRNG 模块（或 AES-CTR_DRBG）而**无须修改顶层 port 签名**。

顶层接口（RTL 设计阶段可按需调整命名，接口语义保持一致）：

| 信号 | 方向 | 位宽 | 说明 |
|------|------|-----|------|
| `rand_in` | in | 32 | 来自外部 TRNG 的随机字 |
| `rand_valid` | in | 1 | `rand_in` 有效（握手信号） |
| `rand_req` | out | 1 | 加速器请求一个新随机字 |

本版本中：

- 加速器内部**不产生 `rand_req` 脉冲**（blinding 未启用）
- `rand_in` / `rand_valid` 在 RTL 中仅作为未使用输入保留，顶层测试台可驱动固定值（如 `32'h0`）
- Lint 层面用 `unused_signal` 或 `/* verilator lint_off UNUSED */` 忽略告警

优点：
- 未来启用 blinding 时，顶层 port 列表不变，只需在内部 FSM 加 `rand_req` 驱动逻辑
  并消费 `rand_in`，接口协议稳定
- 测试台（UVM / cocotb）可提前建立随机数驱动，减少后续重构成本

### 4.5 Hash 引擎（已确认：不内置，不预留接口）

本版本**不实现 Hash 引擎**，顶层也**不预留**相关接口。

理由：
- Hash 通常作为独立 IP（如 `sha_core`）并列于 SoC 顶层，**不与 RSA 核共用内部信号**
- 预留端口对 RSA 核本身无意义（Hash 的消息/摘要不流经 RSA 核的端口）
- 决策 #5 已将 padding/Hash/MGF1 全部交软件层处理，硬件职责边界清晰
- 未来若系统需要硬件 Hash 加速，在 SoC 顶层另起 `sha_top` 模块即可，与 RSA 核接口无关

---

## 5. 主机接口（已确认：纯 APB 32-bit）

### 5.1 总线选型

| 项 | 值 |
|----|----|
| 协议 | AMBA APB（推荐 APB3/APB4） |
| 数据位宽 | 32-bit |
| 地址位宽 | 12-bit（覆盖 4 KB 地址空间） |
| 时钟域 | 单时钟（与加速器主时钟同步） |
| 信号 | PSEL / PENABLE / PWRITE / PADDR / PWDATA / PRDATA / PREADY / PSLVERR |

**选型理由**：
- 本仓库 `verif/sjtag2apb` 与 `verif/sjtag2apb_cocotb` 已有完整 APB 验证资产，可直接复用驱动/监控
- APB 协议无 burst、无 outstanding，最简单；读写逻辑几个 `always` 块即可
- 原型吞吐 20 ops/s 下，operand 搬运开销远小于运算开销，无须 DMA / AXI burst

### 5.2 地址空间总览（预规划，具体寄存器在 RTL 设计阶段细化）

```
0x000 ── 0x0FF : 控制 / 状态寄存器区
   CMD        操作命令（Sign/Verify/Encrypt/Decrypt）
   STATUS     当前状态（idle/busy/done/err）
   CTRL       启动 / 中断使能
   IRQ_STATUS 中断挂起 / W1C
   ERR_CODE   错误码

0x100 ── 0x3FF : Operand 写入窗口
   按 32-bit 分拍写入 n / e / d / p / q / dp / dq / qInv / m
   每个 2048-bit operand = 64 拍；每个 1024-bit operand = 32 拍

0x400 ── 0x5FF : 结果读出窗口
   32-bit 分拍读出 s / c（2048-bit，64 拍）
```

> 详细寄存器映射与偏移量将在 RTL 设计阶段（v0.2）给出。

### 5.3 典型操作时序（Sign 为例）

```
1. 软件配置 CTRL、写入 operand (n, d, p, q, dp, dq, qInv, m)  ← APB 多拍写
2. 软件写 CMD = SIGN                                              ← 一次 APB 写
3. 加速器 STATUS 变 busy，开始 CRT + Ladder 运算
4. 运算完成后 STATUS = done，若 IRQ_EN 触发 IRQ
5. 软件轮询或响应 IRQ，从结果窗口读 s                             ← APB 多拍读
6. 软件 W1C 清 IRQ_STATUS
```

### 5.4 PSLVERR 使用约定

- 非法地址访问 → PSLVERR=1
- busy 状态下试图重写 CMD → PSLVERR=1
- operand 未写全就启动运算 → 运算自行报 ERR_CODE（不通过 PSLVERR）

### 5.5 密钥存储（已确认：0 槽，不做 Key Vault）

本版本**不在芯片内保存任何密钥状态**。

| 项 | 设定 |
|----|------|
| 内置 Key Vault SRAM | 无 |
| 密钥槽数量 | 0 |
| 密钥生命周期管理 | 无 |
| ZEROIZE 指令 | 无（operand 寄存器在每次 `done` 后自动清零） |

行为：
- 每次 Sign / Decrypt / Verify / Encrypt，软件必须通过 APB **完整写入** 所有 operand
  （`n / e` 或 `n / p / q / dp / dq / qInv`，以及 `m` 或 `c`）
- 运算完成、结果读出后，硬件自动清除内部 operand 寄存器
- 下一次操作必须重新写入 key

理由：
- 匹配"简单电路"原型定位（决策 #1）
- 决策 #5（仅 Raw 模幂）已将密钥管理交给软件层
- 省去 Key Vault + 索引管理 + 密钥生命周期 FSM + zeroize 指令，RTL 复杂度大降
- 与决策 #10（安全等级）解耦：有无 slot 不影响算法正确性
- 后续产品化（如 HSM）时，可在新工程中增加 Key Vault 子模块，接口向前兼容

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
