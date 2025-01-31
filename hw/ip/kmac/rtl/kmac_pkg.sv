// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// kmac_pkg

package kmac_pkg;
  parameter int MsgWidth = sha3_pkg::MsgWidth;
  parameter int MsgStrbW = sha3_pkg::MsgStrbW;

  // Message FIFO depth
  //
  // Assume entropy is ready always (if Share is reused as an entropy in Chi)
  // Then it takes 72 cycles to complete the Keccak round. While Keccak is in
  // operation, the module need to store the incoming messages to not degrade
  // the throughput.
  //
  // Based on the observation from HMAC case, the core usually takes 5 clocks
  // to fetch data and store into KMAC. So the core can push at most 14.5 X 4B
  // which is 58B. After that, Keccak can fetch the data from MSG_FIFO faster
  // rate than the core can push. To fetch 58B, it takes around 7~8 cycles.
  // For that time, the core only can push at most 2 DW. After that Keccak
  // waits the incoming message.
  //
  // So Message FIFO doesn't need full block size except the KMAC case, which
  // is delayed the operation by processing Function Name N, customization S,
  // and secret keys. But KMAC doesn't need high throughput anyway (72Mb/s).
  parameter int RegIntfWidth = 32; // 32bit interface
  parameter int RegLatency   = 5;  // 5 cycle to write one Word
  parameter int Sha3Latency  = 72; // Expected masked sha3 processing time 24x3

  // Total required buffer size while SHA3 is in processing
  parameter int BufferCycles   = (Sha3Latency + RegLatency - 1)/RegLatency;
  parameter int BufferSizeBits = RegIntfWidth * BufferCycles;

  // Required MsgFifoDepth. Adding slightly more buffer for margin
  parameter int MsgFifoDepth   = 2 + ((BufferSizeBits + MsgWidth - 1)/MsgWidth);
  parameter int MsgFifoDepthW  = $clog2(MsgFifoDepth+1);

  parameter int MsgWindowWidth = 32; // Register width
  parameter int MsgWindowDepth = 512; // 2kB space

  // Key related definitions
  // If this value is changed, please modify the logic inside kmac_core
  // that assigns the value into `encoded_key`
  parameter int MaxKeyLen = 512;

  // size of encode_string(Key)
  // $ceil($clog2(MaxKeyLen+1)/8)
  parameter int MaxEncodedKeyLenW = $clog2(MaxKeyLen+1);
  parameter int MaxEncodedKeyLenByte = (MaxEncodedKeyLenW + 8 - 1) / 8;
  parameter int MaxEncodedKeyLenSize = MaxEncodedKeyLenByte * 8;

  //                             Secret Key  left_encode(len(Key))
  //                             ----------  ------------------------
  parameter int MaxEncodedKeyW = MaxKeyLen + MaxEncodedKeyLenSize + 8;

  // key_len is SW configurable CSR.
  // Current KMAC allows 5 key length options.
  // This value determines the KMAC core how to map the value
  // from Secret Key register to key size block
  typedef enum logic [2:0] {
    Key128 = 3'b 000, // 128 bit secret key
    Key192 = 3'b 001, // 192 bit secret key
    Key256 = 3'b 010, // 256 bit secret key
    Key384 = 3'b 011, // 384 bit secret key
    Key512 = 3'b 100  // 512 bit secret key
  } key_len_e;


  // kmac_cmd_e defines the possible command sets that software issues via
  // !!CMD register. This is mainly to limit the error scenario that SW writes
  // multiple commands at once.
  typedef enum logic [3:0] {
    CmdNone      = 4'b 0000,
    CmdStart     = 4'b 0001,
    CmdProcess   = 4'b 0010,
    CmdManualRun = 4'b 0100,
    CmdDone      = 4'b 1000
  } kmac_cmd_e;

  // Timer
  parameter int unsigned TimerPrescalerW = 10;
  parameter int unsigned EdnWaitTimerW   = 16;

  // Entropy Mode Selection : Should be matched to register package Enum value
  typedef enum logic [1:0] {
    EntropyModeNone = 2'h 0,
    EntropyModeEdn  = 2'h 1,
    EntropyModeSw   = 2'h 2
  } entropy_mode_e;

  // entropy lfsr related
  parameter int unsigned EntropyLfsrW = 64;
  typedef logic [EntropyLfsrW-1:0][$clog2(EntropyLfsrW)-1:0] lfsr_perm_t;
  parameter lfsr_perm_t RndCnstLfsrPermDefault = {
    128'h810970222da1b1b1187551c3ff94574a,
    256'h970d171aa41948cbe3a58167d3b47c268acfcbb2fa627b9c0a2fdf578f4ed32b
  };

  ///////////////////////////
  // Application interface //
  ///////////////////////////

  // Number of the application interface
  // Currently KMAC has three interface.
  // 0: KeyMgr
  // 1: LC_CTRL
  // 2: ROM_CTRL
  // Make sure to change `width` of app inter-module signal definition
  // if this value is changed.
  parameter int unsigned NumAppIntf = 3;

  // Application Algorithm
  // Each interface can choose algorithms among SHA3, cSHAKE, KMAC
  typedef enum bit [1:0] {
    // SHA3 mode doer not nees any additional information.
    // Prefix will be tied to all zero and not used.
    AppSHA3   = 0,

    // In CShake/ KMAC mode, the Prefix can be determined by the compile-time
    // parameter or through CSRs.
    AppCShake = 1,

    // In KMAC mode, the secret key always comes from sideload.
    AppKMAC   = 2
  } app_mode_e;

  // Predefined encoded_string
  parameter logic [15:0] EncodedStringEmpty = 16'h 0001;
  parameter logic [47:0] EncodedStringKMAC = 48'h 4341_4D4B_2001;
  parameter int unsigned NSPrefixW = sha3_pkg::NSRegisterSize*8;

  typedef struct packed {
    app_mode_e Mode;

    sha3_pkg::keccak_strength_e Strength;

    // PrefixMode determines the origin value of Prefix that is used in KMAC
    // and cSHAKE operations.
    // Choose **0** for CSRs (!!PREFIX), or **1** to use `Prefix` parameter
    // below.
    bit PrefixMode;

    // If `PrefixMode` is 1'b 1, then this `Prefix` value will be used in
    // cSHAKE or KMAC operation.
    logic [NSPrefixW-1:0] Prefix;
  } app_config_t;

  parameter app_config_t AppCfg [NumAppIntf] = '{
    // KeyMgr
    '{
      Mode:       AppKMAC, // KeyMgr uses KMAC operation
      Strength:   sha3_pkg::L256,
      PrefixMode: 1'b 0,   // Use CSR for prefix
      Prefix:     '0       // Not used in CSR prefix mode
    },

    // LC_CTRL
    '{
      Mode:       AppCShake,
      Strength:   sha3_pkg::L128,
      PrefixMode: 1'b 1,     // Use prefix parameter
      // {fname: encode_string(""), custom_str: encode_string("LC_CTRL")}
      Prefix: NSPrefixW'(88'h 4c_5254_435f_434C_3801_0001)
    },

    // ROM_CTRL
    '{
      Mode:       AppCShake,
      Strength:   sha3_pkg::L256,
      PrefixMode: 1'b 1,     // Use prefix parameter
      // {fname: encode_string(""), custom_str: encode_string("ROM_CTRL")}
      Prefix: NSPrefixW'(96'h 4c52_5443_5f4d_4f52_4001_0001)
    }
  };

  // Exporting the app internal mux selection enum into the package. So that DV
  // can use this enum in its scoreboard.
  typedef enum logic [2:0] {
    SelNone   = 3'b 000,
    SelApp    = 3'b 101,
    SelOutLen = 3'b 110,
    SelSw     = 3'b 010
  } app_mux_sel_e ;



  // MsgWidth : 64
  // MsgStrbW : 8
  parameter int unsigned AppDigestW = 384;
  parameter int unsigned AppKeyW = 256;

  typedef struct packed {
    logic valid;
    logic [MsgWidth-1:0] data;
    logic [MsgStrbW-1:0] strb;
    // last indicates the last beat of the data. strb can be partial only with
    // last.
    logic last;
  } app_req_t;

  typedef struct packed {
    logic ready;
    logic done;
    logic [AppDigestW-1:0] digest_share0;
    logic [AppDigestW-1:0] digest_share1;
    // Error is valid when done is high. If any error occurs during KDF, KMAC
    // returns the garbage digest data with error. The KeyMgr discards the
    // digest and may re-initiate the process.
    logic error;
  } app_rsp_t;

  parameter app_req_t APP_REQ_DEFAULT = '{
    valid: 1'b 0,
    data: '0,
    strb: '0,
    last: 1'b 0
  };
  parameter app_rsp_t APP_RSP_DEFAULT = '{
    ready: 1'b1,
    done:  1'b1,
    digest_share0: AppDigestW'(32'hDEADBEEF),
    digest_share1: AppDigestW'(32'hFACEBEEF),
    error: 1'b1
  };


  ////////////////////
  // Error Handling //
  ////////////////////

  // Error structure is same to the SHA3 one. The codes do not overlap.
  typedef enum logic [7:0] {
    ErrNone = 8'h 00,

    // ErrSha3SwControl occurs when software sent wrong flow signal.
    // e.g) Sw set `process_i` without `start_i`. The state machine ignores
    //      the signal and report through the error FIFO.
    //ErrSha3SwControl = 8'h 80

    // ErrKeyNotValid: KeyMgr interface raises an error if the secret key is
    // not valid when KeyMgr initiates KDF.
    ErrKeyNotValid = 8'h 01,

    // ErrSwPushMsgFifo: Sw writes data into Msg FIFO abruptly.
    // This error occurs in below scenario:
    //   - Sw does not send "Start" command to KMAC then writes data into
    //     Msg FIFO
    //   - Sw writes data into Msg FIFO when KeyMgr is in operation
    ErrSwPushedMsgFifo = 8'h 02,

    // ErrSwIssuedCmdInAppActive
    //  - Sw writes any command while AppIntf is in active.
    ErrSwIssuedCmdInAppActive = 8'h 03,

    // ErrWaitTimerExpired
    // Entropy Wait timer expired. Something wrong on EDN i/f
    ErrWaitTimerExpired = 8'h 04,

    // ErrIncorrectEntropyMode
    // Incorrect Entropy mode when entropy is ready
    ErrIncorrectEntropyMode = 8'h 05,

    // ErrUnexpectedModeStrength
    ErrUnexpectedModeStrength = 8'h 06,

    // ErrIncorrectFunctionName "KMAC"
    ErrIncorrectFunctionName = 8'h 07,

    // ErrSwCmdSequence
    ErrSwCmdSequence = 8'h 08,

    // Error Shadow register update
    ErrShadowRegUpdate = 8'h C0
  } err_code_e;

  typedef struct packed {
    logic        valid;
    err_code_e   code; // Type of error
    logic [23:0] info; // Additional Debug info
  } err_t;

  typedef struct packed {
    logic [AppDigestW-1:0] digest_share0;
    logic [AppDigestW-1:0] digest_share1;
  } rsp_digest_t;
  ///////////////////////
  // Library Functions //
  ///////////////////////

  // Endian conversion functions (32-bit, 64-bit)
  function automatic logic [31:0] conv_endian32( input logic [31:0] v, input logic swap);
    logic [31:0] conv_data = {<<8{v}};
    conv_endian32 = (swap) ? conv_data : v ;
  endfunction : conv_endian32

  function automatic logic [63:0] conv_endian64( input logic [63:0] v, input logic swap);
    logic [63:0] conv_data = {<<8{v}};
    conv_endian64 = (swap) ? conv_data : v ;
  endfunction : conv_endian64

endpackage : kmac_pkg
