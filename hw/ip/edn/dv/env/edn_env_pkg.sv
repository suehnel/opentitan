// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package edn_env_pkg;
  // dep packages
  import uvm_pkg::*;
  import top_pkg::*;
  import dv_utils_pkg::*;
  import push_pull_agent_pkg::*;
  import csrng_agent_pkg::*;
  import dv_lib_pkg::*;
  import tl_agent_pkg::*;
  import cip_base_pkg::*;
  import csr_utils_pkg::*;
  import edn_ral_pkg::*;
  import prim_mubi_pkg::*;
  import edn_pkg::*;

  // macro includes
  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  // parameters
  parameter uint     MIN_NUM_ENDPOINTS = 1;
  parameter uint     MAX_NUM_ENDPOINTS = 7;
  parameter uint     MIN_GLEN = 1;
  parameter string   LIST_OF_ALERTS[]  = {"recov_alert","fatal_alert"};
  parameter uint     NUM_ALERTS        = 2;

  // types
  typedef enum int {
    CmdReqDone  = 0,
    FifoErr     = 1
  } edn_intr_e;

  typedef enum int {
    AutoReqMode = 1,
    BootReqMode = 2
  } hw_req_mode_e;

  // package sources
  `include "edn_env_cfg.sv"
  `include "edn_env_cov.sv"
  `include "edn_virtual_sequencer.sv"
  `include "edn_scoreboard.sv"
  `include "edn_env.sv"
  `include "edn_vseq_list.sv"

endpackage
