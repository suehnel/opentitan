// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class edn_genbits_test extends edn_base_test;

  `uvm_component_utils(edn_genbits_test)
  `uvm_component_new

  function void configure_env();
    super.configure_env();

    cfg.boot_req_mode_pct = 30;
    cfg.auto_req_mode_pct = 30;
    cfg.min_num_boot_genbits = 1;
    cfg.max_num_boot_genbits = 4;
    cfg.min_num_reqs_between_reseeds = 1;
    cfg.max_num_reqs_between_reseeds = 1;
    cfg.min_num_requests = 4;
    cfg.max_num_requests = 16;

    `DV_CHECK_RANDOMIZE_FATAL(cfg)
    `uvm_info(`gfn, $sformatf("%s", cfg.convert2string()), UVM_HIGH)
  endfunction
endclass : edn_genbits_test
