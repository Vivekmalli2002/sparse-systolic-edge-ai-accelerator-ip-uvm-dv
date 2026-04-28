`ifndef ACCEL_ENV_SV
`define ACCEL_ENV_SV

class accel_env extends uvm_env;

    `uvm_component_utils(accel_env)

    // Agents
    axil_csr_agent axil_a;
    axis_weight_agent weight_a;
    axis_act_agent act_a;
    axis_result_agent result_a;

    // Scoreboard — public so test can call set_expected()
    accel_scoreboard  sco;

    function new(string name = "accel_env",uvm_component parent = null);
      
        super.new(name, parent);
      
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
      
        axil_a   = axil_csr_agent::type_id::create("axil_a",this);
        weight_a = axis_weight_agent::type_id::create("weight_a",this);
        act_a    = axis_act_agent::type_id::create("act_a",this);
        result_a = axis_result_agent::type_id::create("result_a",this);
        sco      = accel_scoreboard::type_id::create("sco",this);
      
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
      
        axil_a.aport.connect(sco.axil_imp);
        weight_a.aport.connect(sco.weight_imp);
        act_a.aport.connect(sco.act_imp);
        result_a.aport.connect(sco.result_imp);
      
    endfunction

endclass

`endif