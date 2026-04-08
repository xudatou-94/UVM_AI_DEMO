// ============================================================
// OTBN Smoke Test
// ============================================================
class otbn_smoke_test extends otbn_base_test;
  `uvm_component_utils(otbn_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    otbn_smoke_seq seq;

    phase.raise_objection(this);

    seq            = otbn_smoke_seq::type_id::create("seq");
    seq.tl_seqr    = get_tl_seqr();
    seq.scoreboard = get_scoreboard();
    seq.start(null);

    phase.drop_objection(this);
  endtask

endclass
