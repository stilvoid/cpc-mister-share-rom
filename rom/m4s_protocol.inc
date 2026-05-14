; CPC MiSTer Mass Storage protocol constants
; Experimental placeholder port range. Verify against core I/O decode before committing.

M4S_PORT_DATA    equ &FBD0
M4S_PORT_STATUS  equ &FBD1
M4S_PORT_COMMAND equ &FBD2
M4S_PORT_PARAM   equ &FBD3

M4S_ST_DATA_READY    equ %00000001
M4S_ST_CAN_WRITE     equ %00000010
M4S_ST_BUSY          equ %00000100
M4S_ST_ERROR         equ %00001000
M4S_ST_END_OF_STREAM equ %00010000

M4S_CMD_NOP        equ &00
M4S_CMD_PING       equ &01
M4S_CMD_DIR_BEGIN  equ &02
M4S_CMD_CD         equ &03
M4S_CMD_LOAD_OPEN  equ &04
M4S_CMD_LOAD_READ  equ &05
M4S_CMD_SAVE_OPEN  equ &06
M4S_CMD_SAVE_WRITE equ &07
M4S_CMD_CLOSE      equ &08
M4S_CMD_GET_CWD    equ &09
