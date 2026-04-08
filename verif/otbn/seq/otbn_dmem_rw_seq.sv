// ============================================================
// OTBN DMEM Read-Write Sequence
//
// Loads a minimal program that halts immediately (ECALL).
// Before execution:
//   - Writes test patterns into DMEM
// After execution (DMEM contents preserved):
//   - Reads back DMEM and checks vs written values
//
// This verifies:
//   - DMEM is accessible via TL-UL before and after execution
//   - OTBN preserves DMEM across a clean run
// ============================================================
class otbn_dmem_rw_seq extends otbn_tb_base_seq;
  `uvm_object_utils(otbn_dmem_rw_seq)

  localparam bit [31:0] ECALL      = 32'h0000_0073;
  localparam int        N_WORDS    = 16;  // 64 bytes of DMEM
  localparam bit [31:0] BASE_ADDR  = 32'h0;

  function new(string name = "otbn_dmem_rw_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] imem_prog[];
    bit [31:0] wr_data[];
    bit [31:0] rd_data[];
    bit        done;

    `uvm_info(`gfn, "=== otbn_dmem_rw_seq: START ===", UVM_NONE)

    // --- 1. Load program (ECALL) ---
    imem_prog    = new[1];
    imem_prog[0] = ECALL;
    load_imem(imem_prog);

    // --- 2. Write test patterns to DMEM ---
    wr_data = new[N_WORDS];
    foreach (wr_data[i]) begin
      wr_data[i] = 32'hA5A5_0000 | (i & 32'hFFFF);
    end
    write_dmem(.byte_offset(BASE_ADDR), .data_words(wr_data));
    `uvm_info(`gfn, $sformatf("Wrote %0d words to DMEM", N_WORDS), UVM_MEDIUM)

    // --- 3. Execute ---
    run_otbn();
    wait_done(.timeout_cycles(10_000), .success(done));

    if (!done) begin
      `uvm_error(`gfn, "=== otbn_dmem_rw_seq: FAILED (timeout) ===")
      return;
    end

    check_no_errors();

    // --- 4. Readback DMEM and compare ---
    read_dmem(.byte_offset(BASE_ADDR), .n_words(N_WORDS), .data_words(rd_data));

    foreach (rd_data[i]) begin
      if (rd_data[i] !== wr_data[i]) begin
        `uvm_error(`gfn, $sformatf(
          "DMEM[%0d] mismatch: got 0x%08x exp 0x%08x", i, rd_data[i], wr_data[i]))
      end else begin
        `uvm_info(`gfn, $sformatf(
          "DMEM[%0d] OK: 0x%08x", i, rd_data[i]), UVM_HIGH)
      end
    end

    `uvm_info(`gfn, "=== otbn_dmem_rw_seq: DONE ===", UVM_NONE)
  endtask

endclass
