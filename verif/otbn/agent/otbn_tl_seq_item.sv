// ============================================================
// OTBN TL-UL Sequence Item
// ============================================================
class otbn_tl_seq_item extends uvm_sequence_item;
  `uvm_object_utils(otbn_tl_seq_item)

  // Request fields
  rand bit        write;       // 1=write, 0=read
  rand bit [31:0] addr;
  rand bit [31:0] wdata;
  rand bit [3:0]  mask;

  // Response fields (populated by driver)
  bit [31:0] rdata;
  bit        error;

  constraint mask_full_c { mask == 4'hF; }

  function new(string name = "otbn_tl_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%s addr=0x%08x data=0x%08x mask=0x%x err=%0b",
      write ? "WR" : "RD", addr, write ? wdata : rdata, mask, error);
  endfunction

endclass
