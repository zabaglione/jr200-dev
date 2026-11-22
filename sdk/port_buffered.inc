; SPDX-License-Identifier: BSD-3-Clause
; Buffered gameplay input for the port runtime.
        .include "port_runtime.inc"
        .include "port_input.inc"
        JR_PORT_RUNTIME jr_input_read,jr_input_wait,JR_INPUT_CHECKPOINT,JR_INPUT_RESET_HOOK,JR_INPUT_BEGIN,JR_INPUT_END,JR_INPUT_MODAL_BEGIN,JR_INPUT_MODAL_END,JR_INPUT_ACTION_BEGIN,JR_INPUT_ACTION_END
