// ============================================================
// OTBN TB Base Virtual Sequence
// Provides helpers: tl_write, tl_read, load_imem, load_dmem,
// run_otbn, wait_done, read_dmem
// ============================================================
class otbn_tb_base_seq extends uvm_sequence;
  `uvm_object_utils(otbn_tb_base_seq)

  // Handle to the TL-UL sequencer (set by test or parent seq)
  uvm_sequencer #(otbn_tl_seq_item) tl_seqr;

  // Handle to scoreboard for expected value injection
  otbn_scoreboard scoreboard;

  function new(string name = "otbn_tb_base_seq");
    super.new(name);
  endfunction

  // ----------------------------------------------------------
  // TL-UL single write (blocking)
  // ----------------------------------------------------------
  task tl_write(input bit [31:0] addr, input bit [31:0] data);
    otbn_tl_seq_item item;
    item        = otbn_tl_seq_item::type_id::create("tl_wr");
    item.write  = 1'b1;
    item.addr   = addr;
    item.wdata  = data;
    item.mask   = 4'hF;
    item.start_item(tl_seqr);
    item.finish_item(tl_seqr);
    if (item.error)
      `uvm_error(`gfn, $sformatf("TL write error addr=0x%08x data=0x%08x", addr, data))
  endtask

  // ----------------------------------------------------------
  // TL-UL single read (blocking)
  // ----------------------------------------------------------
  task tl_read(input bit [31:0] addr, output bit [31:0] rdata);
    otbn_tl_seq_item item;
    item        = otbn_tl_seq_item::type_id::create("tl_rd");
    item.write  = 1'b0;
    item.addr   = addr;
    item.wdata  = '0;
    item.mask   = 4'hF;
    item.start_item(tl_seqr);
    item.finish_item(tl_seqr);
    rdata = item.rdata;
    if (item.error)
      `uvm_error(`gfn, $sformatf("TL read error addr=0x%08x", addr))
  endtask

  // ----------------------------------------------------------
  // Load program words into IMEM
  // imem_words: array of 32-bit instruction words
  // ----------------------------------------------------------
  task load_imem(input bit [31:0] imem_words[]);
    import otbn_reg_pkg::OTBN_IMEM_OFFSET;
    foreach (imem_words[i]) begin
      tl_write(OTBN_IMEM_OFFSET + (i * 4), imem_words[i]);
    end
    `uvm_info(`gfn, $sformatf("Loaded %0d words into IMEM", imem_words.size()), UVM_MEDIUM)
  endtask

  // ----------------------------------------------------------
  // Write data words into DMEM
  // ----------------------------------------------------------
  task write_dmem(input bit [31:0] byte_offset, input bit [31:0] data_words[]);
    import otbn_reg_pkg::OTBN_DMEM_OFFSET;
    foreach (data_words[i]) begin
      tl_write(OTBN_DMEM_OFFSET + byte_offset + (i * 4), data_words[i]);
    end
  endtask

  // ----------------------------------------------------------
  // Read data words from DMEM
  // ----------------------------------------------------------
  task read_dmem(input bit [31:0] byte_offset, input int unsigned n_words,
                 output bit [31:0] data_words[]);
    import otbn_reg_pkg::OTBN_DMEM_OFFSET;
    data_words = new[n_words];
    foreach (data_words[i]) begin
      tl_read(OTBN_DMEM_OFFSET + byte_offset + (i * 4), data_words[i]);
    end
  endtask

  // ----------------------------------------------------------
  // Start OTBN execution (write CMD = Execute)
  // ----------------------------------------------------------
  task run_otbn();
    import otbn_reg_pkg::OTBN_CMD_OFFSET;
    import otbn_pkg::CmdExecute;
    tl_write(OTBN_CMD_OFFSET, 32'(CmdExecute));
    `uvm_info(`gfn, "OTBN CMD=Execute issued", UVM_MEDIUM)
  endtask

  // ----------------------------------------------------------
  // Poll STATUS until IDLE (or timeout)
  // Returns 1 if clean idle, 0 on timeout
  // ----------------------------------------------------------
  task wait_done(input int unsigned timeout_cycles = 100_000,
                 output bit success);
    import otbn_reg_pkg::OTBN_STATUS_OFFSET;
    import otbn_pkg::StatusIdle;
    bit [31:0] status;
    success = 0;
    repeat (timeout_cycles) begin
      tl_read(OTBN_STATUS_OFFSET, status);
      if (status[7:0] == 8'(StatusIdle)) begin
        success = 1;
        `uvm_info(`gfn, "OTBN reached IDLE status", UVM_MEDIUM)
        return;
      end
    end
    `uvm_error(`gfn, $sformatf(
      "wait_done timeout after %0d polls, STATUS=0x%02x", timeout_cycles, status[7:0]))
  endtask

  // ----------------------------------------------------------
  // Check ERR_BITS == 0 after execution
  // ----------------------------------------------------------
  task check_no_errors();
    import otbn_reg_pkg::OTBN_ERR_BITS_OFFSET;
    bit [31:0] err_bits;
    tl_read(OTBN_ERR_BITS_OFFSET, err_bits);
    if (err_bits != 0)
      `uvm_error(`gfn, $sformatf("ERR_BITS non-zero: 0x%08x", err_bits))
    else
      `uvm_info(`gfn, "ERR_BITS == 0: clean execution", UVM_MEDIUM)
  endtask

  // ----------------------------------------------------------
  // Check INSN_CNT > 0 (execution actually ran instructions)
  // ----------------------------------------------------------
  task check_insn_cnt(input int unsigned min_count = 1);
    import otbn_reg_pkg::OTBN_INSN_CNT_OFFSET;
    bit [31:0] cnt;
    tl_read(OTBN_INSN_CNT_OFFSET, cnt);
    if (cnt < min_count)
      `uvm_error(`gfn, $sformatf("INSN_CNT=%0d < min=%0d", cnt, min_count))
    else
      `uvm_info(`gfn, $sformatf("INSN_CNT=%0d OK", cnt), UVM_MEDIUM)
  endtask

endclass
