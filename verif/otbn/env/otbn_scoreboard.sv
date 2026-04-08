// ============================================================
// OTBN Scoreboard
// Monitors TL-UL transactions and checks:
//   - No bus errors on normal register accesses
//   - ERR_BITS == 0 after clean execution
//   - DMEM readback matches expected values (set by seq)
// ============================================================
class otbn_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(otbn_scoreboard)

  uvm_analysis_imp #(otbn_tl_seq_item, otbn_scoreboard) tl_ap;

  // Expected DMEM contents set by sequences for readback checks
  // Key: word address (byte_addr >> 2), Value: expected data
  bit [31:0] exp_dmem [bit [31:0]];

  // Statistics
  int unsigned num_writes;
  int unsigned num_reads;
  int unsigned num_errors;
  int unsigned num_checks_passed;
  int unsigned num_checks_failed;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tl_ap = new("tl_ap", this);
  endfunction

  function void write(otbn_tl_seq_item item);
    import otbn_reg_pkg::*;

    // Count bus errors
    if (item.error) begin
      num_errors++;
      `uvm_error(`gfn, $sformatf("TL bus error: %s", item.convert2string()))
      return;
    end

    if (item.write) begin
      num_writes++;
    end else begin
      num_reads++;
      // Check DMEM readback if address is in DMEM window
      if (item.addr >= OTBN_DMEM_OFFSET &&
          item.addr <  OTBN_DMEM_OFFSET + OTBN_DMEM_SIZE) begin
        bit [31:0] word_addr = item.addr >> 2;
        if (exp_dmem.exists(word_addr)) begin
          if (item.rdata === exp_dmem[word_addr]) begin
            num_checks_passed++;
            `uvm_info(`gfn, $sformatf("DMEM[0x%04x] readback OK: 0x%08x",
              item.addr, item.rdata), UVM_MEDIUM)
          end else begin
            num_checks_failed++;
            `uvm_error(`gfn, $sformatf(
              "DMEM[0x%04x] mismatch: got 0x%08x exp 0x%08x",
              item.addr, item.rdata, exp_dmem[word_addr]))
          end
        end
      end

      // Check ERR_BITS: should be 0 after clean execution
      if (item.addr == OTBN_ERR_BITS_OFFSET && item.rdata != 0) begin
        `uvm_error(`gfn, $sformatf("ERR_BITS non-zero after execution: 0x%06x",
          item.rdata))
      end
    end
  endfunction

  function void set_exp_dmem(bit [31:0] byte_addr, bit [31:0] data);
    exp_dmem[byte_addr >> 2] = data;
  endfunction

  function void clear_exp_dmem();
    exp_dmem.delete();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(`gfn, $sformatf(
      "Scoreboard summary: writes=%0d reads=%0d bus_errors=%0d checks_passed=%0d checks_failed=%0d",
      num_writes, num_reads, num_errors, num_checks_passed, num_checks_failed), UVM_NONE)
    if (num_checks_failed > 0 || num_errors > 0)
      `uvm_error(`gfn, "Scoreboard: FAILED")
    else
      `uvm_info(`gfn, "Scoreboard: PASSED", UVM_NONE)
  endfunction

endclass
