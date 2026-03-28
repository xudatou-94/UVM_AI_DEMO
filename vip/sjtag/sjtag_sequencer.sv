// =============================================================================
// sjtag_sequencer.sv - SJTAG Sequencer
//
// 标准 UVM sequencer，直接参数化为 sjtag_seq_item。
// 无额外定制逻辑，继承 uvm_sequencer 全部功能。
// =============================================================================

class sjtag_sequencer extends uvm_sequencer #(sjtag_seq_item);
  `uvm_component_utils(sjtag_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : sjtag_sequencer
