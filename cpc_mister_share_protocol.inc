; CPC MiSTer Share protocol constants
; Experimental placeholder port range. Verify against core I/O decode before committing.

CMS_PORT_DATA    equ &FBD0
CMS_PORT_STATUS  equ &FBD1
CMS_PORT_COMMAND equ &FBD2
CMS_PORT_PARAM   equ &FBD3

CMS_ST_DATA_READY    equ %00000001
CMS_ST_CAN_WRITE     equ %00000010
CMS_ST_BUSY          equ %00000100
CMS_ST_ERROR         equ %00001000
CMS_ST_END_OF_STREAM equ %00010000

CMS_CMD_NOP        equ &00
CMS_CMD_PING       equ &01
CMS_CMD_DIR_BEGIN  equ &02
CMS_CMD_CD         equ &03
CMS_CMD_LOAD_OPEN  equ &04
CMS_CMD_LOAD_READ  equ &05
CMS_CMD_SAVE_OPEN  equ &06
CMS_CMD_SAVE_WRITE equ &07
CMS_CMD_CLOSE      equ &08
CMS_CMD_GET_CWD    equ &09
CMS_CMD_REQ_BEGIN  equ &0A
CMS_CMD_TYPE       equ &0B
