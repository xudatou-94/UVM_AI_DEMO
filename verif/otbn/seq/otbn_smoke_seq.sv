// ============================================================
// OTBN Smoke Sequence
//
// Loads the minimal 1-instruction program:
//   ECALL  (0x00000073) — halts OTBN cleanly
//
// Verifies:
//   - STATUS returns to IDLE
//   - ERR_BITS == 0
//   - INSN_CNT >= 1
// ============================================================
class otbn_smoke_seq extends otbn_tb_base_seq;
  `uvm_object_utils(otbn_smoke_seq)

  // ECALL instruction encoding (RISC-V / OTBN base ISA)
  localparam bit [31:0] ECALL = 32'h0000_0073;

  function new(string name = "otbn_smoke_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] imem_prog[];
    bit        done;

    `uvm_info(`gfn, "=== otbn_smoke_seq: START ===", UVM_NONE)

    // Build minimal program: just ECALL
    imem_prog = new[1];
    imem_prog[0] = ECALL;

    // Load program into IMEM
    load_imem(imem_prog);

    // Start execution
    run_otbn();

    // Wait for completion
    wait_done(.timeout_cycles(10_000), .success(done));

    if (done) begin
      // Verify no errors
      check_no_errors();
      check_insn_cnt(.min_count(1));
      `uvm_info(`gfn, "=== otbn_smoke_seq: PASSED ===", UVM_NONE)
    end else begin
      `uvm_error(`gfn, "=== otbn_smoke_seq: FAILED (timeout) ===")
    end
  endtask

endclass
