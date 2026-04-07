// =============================================================================
// apb_sequencer.sv - APB Sequencer
//
// 标准 UVM sequencer，参数化为 apb_seq_item。
// Master 和 Slave 模式复用同一个 sequencer 类型，由 agent 按角色选择。
// =============================================================================

class apb_sequencer extends uvm_sequencer #(apb_seq_item);
  `uvm_component_utils(apb_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : apb_sequencer
