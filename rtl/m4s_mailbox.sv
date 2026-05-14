// SPDX-License-Identifier: GPL-2.0-or-later
// Experimental CPC MiSTer Mass Storage mailbox scaffold.
// Not a full M4 clone. This is a tiny CPC-facing test interface.

module m4s_mailbox (
    input  logic        clk,
    input  logic        reset,

    // CPC/Z80 I/O bus-facing strobes, to be driven by the Amstrad core's I/O decode.
    input  logic        io_cs,
    input  logic        io_rd,
    input  logic        io_wr,
    input  logic [1:0]  io_addr,   // 0 DATA, 1 STATUS, 2 COMMAND, 3 PARAM
    input  logic [7:0]  io_din,
    output logic [7:0]  io_dout,

    // TODO: Later connect this to a real host/HPS bridge or internal FIFO.
    output logic        host_req_valid,
    output logic [7:0]  host_req_cmd,
    input  logic        host_req_ready
);

    localparam logic [1:0] REG_DATA   = 2'd0;
    localparam logic [1:0] REG_STATUS = 2'd1;
    localparam logic [1:0] REG_CMD    = 2'd2;
    localparam logic [1:0] REG_PARAM  = 2'd3;

    localparam logic [7:0] CMD_NOP       = 8'h00;
    localparam logic [7:0] CMD_PING      = 8'h01;
    localparam logic [7:0] CMD_DIR_BEGIN = 8'h02;

    localparam int MOCK_LEN = 37;

    logic [7:0] status;
    logic [7:0] param_reg;
    logic [7:0] command_reg;
    logic [7:0] stream_index;
    logic       stream_active;

    // STATUS bit layout
    // bit 0: DATA_READY
    // bit 1: CAN_WRITE
    // bit 2: BUSY
    // bit 3: ERROR
    // bit 4: END_OF_STREAM
    always_comb begin
        status = 8'h02; // CAN_WRITE by default
        if (stream_active) status[0] = 1'b1;
        if (!stream_active) status[4] = 1'b1;
    end

    function automatic logic [7:0] mock_byte(input logic [7:0] idx);
        begin
            // "M4S MOCK DIR\r\nREADME.TXT\r\nHELLO.BAS\r\n\0"
            case (idx)
                8'd0:  mock_byte = "M";
                8'd1:  mock_byte = "4";
                8'd2:  mock_byte = "S";
                8'd3:  mock_byte = " ";
                8'd4:  mock_byte = "M";
                8'd5:  mock_byte = "O";
                8'd6:  mock_byte = "C";
                8'd7:  mock_byte = "K";
                8'd8:  mock_byte = " ";
                8'd9:  mock_byte = "D";
                8'd10: mock_byte = "I";
                8'd11: mock_byte = "R";
                8'd12: mock_byte = 8'h0D;
                8'd13: mock_byte = 8'h0A;
                8'd14: mock_byte = "R";
                8'd15: mock_byte = "E";
                8'd16: mock_byte = "A";
                8'd17: mock_byte = "D";
                8'd18: mock_byte = "M";
                8'd19: mock_byte = "E";
                8'd20: mock_byte = ".";
                8'd21: mock_byte = "T";
                8'd22: mock_byte = "X";
                8'd23: mock_byte = "T";
                8'd24: mock_byte = 8'h0D;
                8'd25: mock_byte = 8'h0A;
                8'd26: mock_byte = "H";
                8'd27: mock_byte = "E";
                8'd28: mock_byte = "L";
                8'd29: mock_byte = "L";
                8'd30: mock_byte = "O";
                8'd31: mock_byte = ".";
                8'd32: mock_byte = "B";
                8'd33: mock_byte = "A";
                8'd34: mock_byte = "S";
                8'd35: mock_byte = 8'h0D;
                8'd36: mock_byte = 8'h0A;
                default: mock_byte = 8'h00;
            endcase
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            param_reg      <= 8'h00;
            command_reg    <= CMD_NOP;
            stream_index   <= 8'h00;
            stream_active  <= 1'b0;
            host_req_valid <= 1'b0;
            host_req_cmd   <= CMD_NOP;
        end else begin
            host_req_valid <= 1'b0;

            if (io_cs && io_wr) begin
                unique case (io_addr)
                    REG_PARAM: begin
                        param_reg <= io_din;
                    end
                    REG_CMD: begin
                        command_reg <= io_din;
                        host_req_cmd <= io_din;
                        host_req_valid <= 1'b1;

                        if (io_din == CMD_PING || io_din == CMD_DIR_BEGIN) begin
                            stream_index <= 8'h00;
                            stream_active <= 1'b1;
                        end
                    end
                    REG_DATA: begin
                        // TODO: accept path/data bytes for CD, SAVE, etc.
                    end
                    default: begin end
                endcase
            end

            if (io_cs && io_rd && io_addr == REG_DATA && stream_active) begin
                if (stream_index >= MOCK_LEN-1) begin
                    stream_active <= 1'b0;
                end else begin
                    stream_index <= stream_index + 8'd1;
                end
            end
        end
    end

    always_comb begin
        io_dout = 8'hFF;
        if (io_cs && io_rd) begin
            unique case (io_addr)
                REG_DATA:   io_dout = mock_byte(stream_index);
                REG_STATUS: io_dout = status;
                REG_CMD:    io_dout = command_reg;
                REG_PARAM:  io_dout = param_reg;
                default:    io_dout = 8'hFF;
            endcase
        end
    end

endmodule
