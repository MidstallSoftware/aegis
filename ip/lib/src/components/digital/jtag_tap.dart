import 'package:rohd/rohd.dart';

/// IEEE 1149.1 JTAG TAP controller.
///
/// Provides standard JTAG access to the FPGA configuration chain via
/// TCK, TMS, TDI, TDO pins. Supports BYPASS, IDCODE, and CONFIG
/// instructions.
///
/// Instruction register layout (4 bits):
///   0000 = EXTEST (mapped to BYPASS)
///   0001 = IDCODE
///   0010 = CONFIG (shift bits into fabric config chain)
///   1111 = BYPASS
///
/// The CONFIG instruction connects TDI directly to the config chain
/// input (cfgIn) during Shift-DR, and asserts cfgLoad on Update-DR.
class JtagTap extends Module {
  Logic get tdo => output('tdo');
  Logic get cfgIn => output('cfgIn');
  Logic get cfgLoad => output('cfgLoad');
  Logic get cfgReset => output('cfgReset');
  Logic get enableConfig => output('enableConfig');

  // User data register interface - exposed to fabric for debug
  Logic get userTdi => output('userTdi');
  Logic get userShift => output('userShift');
  Logic get userUpdate => output('userUpdate');
  Logic get userCapture => output('userCapture');
  Logic get userReset => output('userReset');
  Logic get enableUser => output('enableUser');

  /// 32-bit device ID code.
  final int idcode;

  static const int IR_WIDTH = 4;

  // Instruction opcodes
  static const int EXTEST = 0x0;
  static const int IDCODE_INST = 0x1;
  static const int CONFIG = 0x2;
  static const int USER = 0x3;
  static const int BYPASS = 0xF;

  // TAP states
  static const int TEST_LOGIC_RESET = 0;
  static const int RUN_TEST_IDLE = 1;
  static const int SELECT_DR_SCAN = 2;
  static const int CAPTURE_DR = 3;
  static const int SHIFT_DR = 4;
  static const int EXIT1_DR = 5;
  static const int PAUSE_DR = 6;
  static const int EXIT2_DR = 7;
  static const int UPDATE_DR = 8;
  static const int SELECT_IR_SCAN = 9;
  static const int CAPTURE_IR = 10;
  static const int SHIFT_IR = 11;
  static const int EXIT1_IR = 12;
  static const int PAUSE_IR = 13;
  static const int EXIT2_IR = 14;
  static const int UPDATE_IR = 15;

  JtagTap(
    Logic tck,
    Logic tms,
    Logic tdi,
    Logic trst, {
    this.idcode = 0x00000001,
    Logic? userTdo,
  }) : super(name: 'jtag_tap') {
    tck = addInput('tck', tck);
    tms = addInput('tms', tms);
    tdi = addInput('tdi', tdi);
    trst = addInput('trst', trst);

    if (userTdo != null) {
      userTdo = addInput('userTdoIn', userTdo);
    }

    addOutput('tdo');
    addOutput('cfgIn');
    addOutput('cfgLoad');
    addOutput('cfgReset');
    addOutput('enableConfig');
    addOutput('userTdi');
    addOutput('userShift');
    addOutput('userUpdate');
    addOutput('userCapture');
    addOutput('userReset');
    addOutput('enableUser');

    // TAP state machine
    final state = Logic(width: 4, name: 'state');

    // Instruction register
    final irShift = Logic(width: IR_WIDTH, name: 'irShift');
    final irReg = Logic(width: IR_WIDTH, name: 'irReg');

    // Data registers
    final bypassReg = Logic(name: 'bypassReg');
    final idcodeShift = Logic(width: 32, name: 'idcodeShift');

    // Config data register - just passes through to cfgIn
    final configBit = Logic(name: 'configBit');

    // TAP state machine transitions (IEEE 1149.1)
    final nextState = Logic(width: 4, name: 'nextState');

    Combinational([
      Case(
        state,
        [
          CaseItem(Const(TEST_LOGIC_RESET, width: 4), [
            nextState <
                mux(
                  tms,
                  Const(TEST_LOGIC_RESET, width: 4),
                  Const(RUN_TEST_IDLE, width: 4),
                ),
          ]),
          CaseItem(Const(RUN_TEST_IDLE, width: 4), [
            nextState <
                mux(
                  tms,
                  Const(SELECT_DR_SCAN, width: 4),
                  Const(RUN_TEST_IDLE, width: 4),
                ),
          ]),
          CaseItem(Const(SELECT_DR_SCAN, width: 4), [
            nextState <
                mux(
                  tms,
                  Const(SELECT_IR_SCAN, width: 4),
                  Const(CAPTURE_DR, width: 4),
                ),
          ]),
          CaseItem(Const(CAPTURE_DR, width: 4), [
            nextState <
                mux(tms, Const(EXIT1_DR, width: 4), Const(SHIFT_DR, width: 4)),
          ]),
          CaseItem(Const(SHIFT_DR, width: 4), [
            nextState <
                mux(tms, Const(EXIT1_DR, width: 4), Const(SHIFT_DR, width: 4)),
          ]),
          CaseItem(Const(EXIT1_DR, width: 4), [
            nextState <
                mux(tms, Const(UPDATE_DR, width: 4), Const(PAUSE_DR, width: 4)),
          ]),
          CaseItem(Const(PAUSE_DR, width: 4), [
            nextState <
                mux(tms, Const(EXIT2_DR, width: 4), Const(PAUSE_DR, width: 4)),
          ]),
          CaseItem(Const(EXIT2_DR, width: 4), [
            nextState <
                mux(tms, Const(UPDATE_DR, width: 4), Const(SHIFT_DR, width: 4)),
          ]),
          CaseItem(Const(UPDATE_DR, width: 4), [
            nextState <
                mux(
                  tms,
                  Const(SELECT_DR_SCAN, width: 4),
                  Const(RUN_TEST_IDLE, width: 4),
                ),
          ]),
          CaseItem(Const(SELECT_IR_SCAN, width: 4), [
            nextState <
                mux(
                  tms,
                  Const(TEST_LOGIC_RESET, width: 4),
                  Const(CAPTURE_IR, width: 4),
                ),
          ]),
          CaseItem(Const(CAPTURE_IR, width: 4), [
            nextState <
                mux(tms, Const(EXIT1_IR, width: 4), Const(SHIFT_IR, width: 4)),
          ]),
          CaseItem(Const(SHIFT_IR, width: 4), [
            nextState <
                mux(tms, Const(EXIT1_IR, width: 4), Const(SHIFT_IR, width: 4)),
          ]),
          CaseItem(Const(EXIT1_IR, width: 4), [
            nextState <
                mux(tms, Const(UPDATE_IR, width: 4), Const(PAUSE_IR, width: 4)),
          ]),
          CaseItem(Const(PAUSE_IR, width: 4), [
            nextState <
                mux(tms, Const(EXIT2_IR, width: 4), Const(PAUSE_IR, width: 4)),
          ]),
          CaseItem(Const(EXIT2_IR, width: 4), [
            nextState <
                mux(tms, Const(UPDATE_IR, width: 4), Const(SHIFT_IR, width: 4)),
          ]),
          CaseItem(Const(UPDATE_IR, width: 4), [
            nextState <
                mux(
                  tms,
                  Const(SELECT_DR_SCAN, width: 4),
                  Const(RUN_TEST_IDLE, width: 4),
                ),
          ]),
        ],
        defaultItem: [nextState < Const(TEST_LOGIC_RESET, width: 4)],
      ),
    ]);

    Sequential(
      tck,
      [
        If(
          trst,
          then: [
            state < Const(TEST_LOGIC_RESET, width: 4),
            irReg < Const(IDCODE_INST, width: IR_WIDTH),
          ],
          orElse: [
            state < nextState,

            // IR shift register
            If(
              state.eq(Const(CAPTURE_IR, width: 4)),
              then: [irShift < irReg],
              orElse: [
                If(
                  state.eq(Const(SHIFT_IR, width: 4)),
                  then: [
                    irShift < [tdi, irShift.slice(IR_WIDTH - 1, 1)].swizzle(),
                  ],
                ),
              ],
            ),

            // IR update
            If(state.eq(Const(UPDATE_IR, width: 4)), then: [irReg < irShift]),

            // DR shift registers
            If(
              state.eq(Const(CAPTURE_DR, width: 4)),
              then: [
                // Load capture values
                If(
                  irReg.eq(Const(IDCODE_INST, width: IR_WIDTH)),
                  then: [idcodeShift < Const(idcode, width: 32)],
                ),
                bypassReg < Const(0),
                configBit < Const(0),
              ],
              orElse: [
                If(
                  state.eq(Const(SHIFT_DR, width: 4)),
                  then: [
                    If(
                      irReg.eq(Const(IDCODE_INST, width: IR_WIDTH)),
                      then: [
                        idcodeShift < [tdi, idcodeShift.slice(31, 1)].swizzle(),
                      ],
                      orElse: [
                        If(
                          irReg.eq(Const(CONFIG, width: IR_WIDTH)),
                          then: [configBit < tdi],
                          orElse: [
                            // BYPASS and EXTEST
                            bypassReg < tdi,
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
      reset: trst,
      resetValues: {
        state: Const(TEST_LOGIC_RESET, width: 4),
        irShift: Const(IDCODE_INST, width: IR_WIDTH),
        irReg: Const(IDCODE_INST, width: IR_WIDTH),
        bypassReg: Const(0),
        idcodeShift: Const(idcode, width: 32),
        configBit: Const(0),
      },
    );

    // TDO mux - select based on current instruction
    final isShiftIr = state.eq(Const(SHIFT_IR, width: 4));
    final isShiftDr = state.eq(Const(SHIFT_DR, width: 4));

    Logic drOut = bypassReg;
    drOut = mux(
      irReg.eq(Const(IDCODE_INST, width: IR_WIDTH)),
      idcodeShift[0],
      drOut,
    );
    drOut = mux(irReg.eq(Const(CONFIG, width: IR_WIDTH)), configBit, drOut);
    // USER DR: TDO comes from the user design via userTdoIn
    drOut = mux(
      irReg.eq(Const(USER, width: IR_WIDTH)),
      userTdo != null ? input('userTdoIn') : Const(0),
      drOut,
    );

    tdo <= mux(isShiftIr, irShift[0], mux(isShiftDr, drOut, Const(0)));

    // Config chain outputs
    final inConfigMode = irReg.eq(Const(CONFIG, width: IR_WIDTH));
    final inShiftDr = state.eq(Const(SHIFT_DR, width: 4));
    final inUpdateDr = state.eq(Const(UPDATE_DR, width: 4));
    final inCaptureDr = state.eq(Const(CAPTURE_DR, width: 4));

    cfgIn <= mux(inConfigMode & inShiftDr, tdi, Const(0));
    cfgLoad <= inConfigMode & inUpdateDr;
    cfgReset <= state.eq(Const(TEST_LOGIC_RESET, width: 4)) | trst;
    enableConfig <= inConfigMode;

    // User data register interface - active when IR = USER
    final inUserMode = irReg.eq(Const(USER, width: IR_WIDTH));
    output('userTdi') <= tdi;
    output('userShift') <= inUserMode & inShiftDr;
    output('userUpdate') <= inUserMode & inUpdateDr;
    output('userCapture') <= inUserMode & inCaptureDr;
    output('userReset') <= state.eq(Const(TEST_LOGIC_RESET, width: 4)) | trst;
    output('enableUser') <= inUserMode;
  }

  static const int CONFIG_WIDTH = 0;

  static Map<String, dynamic> descriptor({required int idcode}) {
    return {
      'enabled': true,
      'idcode': '0x${idcode.toRadixString(16).padLeft(8, '0')}',
      'ir_width': IR_WIDTH,
      'instructions': {
        'EXTEST': EXTEST,
        'IDCODE': IDCODE_INST,
        'CONFIG': CONFIG,
        'USER': USER,
        'BYPASS': BYPASS,
      },
    };
  }
}
