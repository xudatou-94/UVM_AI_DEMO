// =============================================================================
// sjtag2apb_apb_read_basic_seq.sv
// case_id: sjtag2apb_0007 | case_name: sjtag2apb_apb_read_basic
//
// 验证基本 APB 读操作：预加载 slave 内存，通过 JTAG 读回并校验。
// 覆盖：全 0 / 全 1 / 随机数据，以及地址边界（0x0、较大地址）。
// =============================================================================

class sjtag2apb_apb_read_basic_seq extends sjtag2apb_tb_base_seq;
  `uvm_object_utils(sjtag2apb_apb_read_basic_seq)

  function new(string name = "sjtag2apb_apb_read_basic_seq");
    super.new(name);
  endfunction

  task body();
    // 预置地址和对应期望数据（含边界和特殊值）
    logic [31:0] preload_addr [10] = '{
      32'h0000_0000,   // 地址边界：最低地址
      32'h0000_0004,
      32'h0000_0008,
      32'h0000_000C,
      32'h0000_0010,
      32'hFFFF_FFF0,   // 地址边界：接近最高地址
      32'hFFFF_FFF4,
      32'hFFFF_FFF8,
      32'hFFFF_FFFC,
      32'h5A5A_5A5C    // 随机中间地址
    };
    logic [31:0] preload_data [10] = '{
      32'h0000_0000,   // 全 0
      32'hFFFF_FFFF,   // 全 1
      32'hA5A5_A5A5,   // 特征值
      32'h5A5A_5A5A,
      32'hDEAD_BEEF,
      32'h1234_5678,
      32'h8765_4321,
      32'hCAFE_BABE,
      32'h0BAD_F00D,
      32'hFACE_CAFE
    };
    logic [31:0] rdata;
    int unsigned pass_cnt = 0, fail_cnt = 0;

    `uvm_info("APB_READ_BASIC", "=== TC sjtag2apb_0007: APB 基本读操作 ===", UVM_NONE)

    do_reset();

    // 预加载 slave 内存（通过 apb_slv_seq 的内置内存模型）
    for (int i = 0; i < 10; i++) begin
      preload_slave(preload_addr[i], preload_data[i]);
    end

    wait_apb_cycles(2);

    // 逐一读取并校验
    for (int i = 0; i < 10; i++) begin
      apb_read(preload_addr[i], rdata);
      if (rdata !== preload_data[i]) begin
        fail_cnt++;
        `uvm_error("APB_READ_BASIC",
          $sformatf("读取不一致 [%0d]：addr=0x%08x 期望=0x%08x 实际=0x%08x",
                    i, preload_addr[i], preload_data[i], rdata))
      end else begin
        pass_cnt++;
        `uvm_info("APB_READ_BASIC",
          $sformatf("读取正确 [%0d]：addr=0x%08x data=0x%08x", i, preload_addr[i], rdata),
          UVM_MEDIUM)
      end
    end

    `uvm_info("APB_READ_BASIC",
      $sformatf("=== TC sjtag2apb_0007 完成：%0d 通过 / %0d 失败 ===",
                pass_cnt, fail_cnt), UVM_NONE)
  endtask

endclass : sjtag2apb_apb_read_basic_seq

// =============================================================================
class sjtag2apb_apb_read_basic_test extends sjtag2apb_base_test;
  `uvm_component_utils(sjtag2apb_apb_read_basic_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_seq();
    sjtag2apb_apb_read_basic_seq seq;
    seq = sjtag2apb_apb_read_basic_seq::type_id::create("seq");
    sjtag_seq_start(seq);
  endtask

endclass : sjtag2apb_apb_read_basic_test
