// SPDX-License-Identifier: GPL-2.0-or-later
// Experimental CPC MiSTer Mass Storage mailbox scaffold.
// Not a full M4 clone. This is a tiny CPC-facing test interface.

module m4s_mailbox #(
    parameter int DIR_INDEX_BITS = 11,
    parameter int REQUEST_BITS = 8
) (
    input  logic        clk,
    input  logic        reset,

    // CPC/Z80 I/O bus-facing strobes, to be driven by the Amstrad core's I/O decode.
    input  logic        io_cs,
    input  logic        io_rd,
    input  logic        io_wr,
    input  logic [1:0]  io_addr,   // 0 DATA, 1 STATUS, 2 COMMAND, 3 PARAM
    input  logic [7:0]  io_din,
    output logic [7:0]  io_dout,

    // Host-loaded text directory index. The stream is treated as zero-terminated.
    input  logic                        dir_index_begin,
    input  logic                        dir_index_wr,
    input  logic [DIR_INDEX_BITS-1:0]   dir_index_addr,
    input  logic [7:0]                  dir_index_din,
    input  logic                        dir_index_done,

    // Host request buffer for the HPS-side helper.
    output logic        host_req_valid,
    output logic [7:0]  host_req_cmd,
    output logic        host_req_pending,
    output logic [7:0]  host_req_len,
    input  logic [REQUEST_BITS-1:0] host_req_addr,
    output logic [7:0]  host_req_data,
    input  logic        host_req_ack
);

    localparam logic [1:0] REG_DATA   = 2'd0;
    localparam logic [1:0] REG_STATUS = 2'd1;
    localparam logic [1:0] REG_CMD    = 2'd2;
    localparam logic [1:0] REG_PARAM  = 2'd3;

    localparam logic [7:0] CMD_NOP       = 8'h00;
    localparam logic [7:0] CMD_PING      = 8'h01;
    localparam logic [7:0] CMD_DIR_BEGIN = 8'h02;
    localparam logic [7:0] CMD_REQ_BEGIN = 8'h0A;
    localparam logic [7:0] CMD_TYPE      = 8'h0B;

    localparam int DIR_INDEX_SIZE = 1 << DIR_INDEX_BITS;
    localparam int REQUEST_SIZE = 1 << REQUEST_BITS;
    localparam logic [DIR_INDEX_BITS-1:0] DIR_INDEX_LAST = {DIR_INDEX_BITS{1'b1}};
    localparam logic [15:0] DIR_INDEX_MAX_LEN = {{(16-DIR_INDEX_BITS){1'b0}}, DIR_INDEX_LAST} + 16'd1;
    localparam logic [REQUEST_BITS-1:0] REQUEST_LAST = {REQUEST_BITS{1'b1}};

    localparam logic [15:0] PING_LEN     = 16'd9;
    localparam logic [15:0] FALLBACK_LEN = 16'd15;

    logic [7:0] status;
    logic [7:0] param_reg;
    logic [7:0] command_reg;
    logic [15:0] stream_index;
    logic       stream_active;
    logic       old_io_rd;
    logic       old_io_wr;
    logic [1:0] old_io_addr;
    logic       dir_index_loaded;
    logic       response_waiting;
    logic [15:0] dir_index_len;
    logic [7:0] dir_index_ram [0:DIR_INDEX_SIZE-1];
    logic [REQUEST_BITS-1:0] request_len;
    logic [7:0] request_ram [0:REQUEST_SIZE-1];

    wire io_rd_fall = old_io_rd && !(io_cs && io_rd);
    wire io_wr_rise = io_cs && io_wr && !old_io_wr;
    wire waiting_for_response = response_waiting && !stream_active;

    assign host_req_pending = host_req_valid;
    assign host_req_len = request_len[7:0];
    assign host_req_data = request_ram[host_req_addr];

    // STATUS bit layout
    // bit 0: DATA_READY
    // bit 1: CAN_WRITE
    // bit 2: BUSY
    // bit 3: ERROR
    // bit 4: END_OF_STREAM
    always_comb begin
        status = 8'h02; // CAN_WRITE by default
        if (stream_active) status[0] = 1'b1;
        if (!stream_active && !waiting_for_response) status[4] = 1'b1;
        if (waiting_for_response) status[2] = 1'b1;
    end

    function automatic logic [7:0] ping_byte(input logic [7:0] idx);
        begin
            // "M4S OK\r\n\0"
            case (idx)
                8'd0: ping_byte = "M";
                8'd1: ping_byte = "4";
                8'd2: ping_byte = "S";
                8'd3: ping_byte = " ";
                8'd4: ping_byte = "O";
                8'd5: ping_byte = "K";
                8'd6: ping_byte = 8'h0D;
                8'd7: ping_byte = 8'h0A;
                default: ping_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic logic [7:0] fallback_byte(input logic [15:0] idx);
        begin
            // "NO M4S INDEX\r\n\0"
            case (idx)
                16'd0:  fallback_byte = "N";
                16'd1:  fallback_byte = "O";
                16'd2:  fallback_byte = " ";
                16'd3:  fallback_byte = "M";
                16'd4:  fallback_byte = "4";
                16'd5:  fallback_byte = "S";
                16'd6:  fallback_byte = " ";
                16'd7:  fallback_byte = "I";
                16'd8:  fallback_byte = "N";
                16'd9:  fallback_byte = "D";
                16'd10: fallback_byte = "E";
                16'd11: fallback_byte = "X";
                16'd12: fallback_byte = 8'h0D;
                16'd13: fallback_byte = 8'h0A;
                default: fallback_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic logic [15:0] stream_len(input logic [7:0] cmd);
        begin
            case (cmd)
                CMD_PING:      stream_len = PING_LEN;
                CMD_DIR_BEGIN: stream_len = dir_index_loaded ? dir_index_len : FALLBACK_LEN;
                CMD_TYPE:      stream_len = dir_index_loaded ? dir_index_len : FALLBACK_LEN;
                default:       stream_len = 16'd0;
            endcase
        end
    endfunction

    function automatic logic [7:0] stream_byte(input logic [7:0] cmd, input logic [15:0] idx);
        begin
            case (cmd)
                CMD_PING:      stream_byte = ping_byte(idx[7:0]);
                CMD_DIR_BEGIN: stream_byte = dir_index_loaded ? dir_index_ram[idx[DIR_INDEX_BITS-1:0]] : fallback_byte(idx);
                CMD_TYPE:      stream_byte = dir_index_loaded ? dir_index_ram[idx[DIR_INDEX_BITS-1:0]] : fallback_byte(idx);
                default:       stream_byte = 8'h00;
            endcase
        end
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            param_reg      <= 8'h00;
            command_reg    <= CMD_NOP;
            stream_index   <= 16'h0000;
            stream_active  <= 1'b0;
            dir_index_loaded <= 1'b0;
            response_waiting <= 1'b0;
            dir_index_len  <= FALLBACK_LEN;
            host_req_valid <= 1'b0;
            host_req_cmd   <= CMD_NOP;
            request_len    <= '0;
            old_io_rd      <= 1'b0;
            old_io_wr      <= 1'b0;
            old_io_addr    <= 2'b00;
        end else begin
            old_io_rd <= io_cs && io_rd;
            old_io_wr <= io_cs && io_wr;
            if (io_cs && io_rd) old_io_addr <= io_addr;
            if (host_req_ack) host_req_valid <= 1'b0;

            if (dir_index_begin) begin
                dir_index_loaded <= 1'b0;
                dir_index_len <= 16'd1;
                dir_index_ram[0] <= 8'h00;
            end

            if (dir_index_wr) begin
                dir_index_loaded <= 1'b1;
                dir_index_ram[dir_index_addr] <= dir_index_din;
                if (!dir_index_loaded || ({5'd0, dir_index_addr} >= dir_index_len)) begin
                    if (dir_index_addr != DIR_INDEX_LAST) begin
                        dir_index_len <= {5'd0, dir_index_addr} + 16'd2;
                        dir_index_ram[dir_index_addr + {{(DIR_INDEX_BITS-1){1'b0}}, 1'b1}] <= 8'h00;
                    end else begin
                        dir_index_len <= DIR_INDEX_MAX_LEN;
                    end
                end
            end

            if (dir_index_done) begin
                if (response_waiting) begin
                    response_waiting <= 1'b0;
                    stream_index <= 16'h0000;
                    stream_active <= 1'b1;
                end
            end

            if (io_wr_rise) begin
                unique case (io_addr)
                    REG_PARAM: begin
                        param_reg <= io_din;
                    end
                    REG_CMD: begin
                        command_reg <= io_din;

                        if (io_din == CMD_PING) begin
                            stream_index <= 16'h0000;
                            stream_active <= 1'b1;
                        end else if (io_din == CMD_DIR_BEGIN) begin
                            host_req_cmd <= io_din;
                            host_req_valid <= 1'b1;
                            request_len <= '0;
                            request_ram[0] <= 8'h00;
                            response_waiting <= 1'b1;
                            stream_active <= 1'b0;
                        end else if (io_din == CMD_REQ_BEGIN) begin
                            request_len <= '0;
                            request_ram[0] <= 8'h00;
                            response_waiting <= 1'b0;
                            stream_active <= 1'b0;
                        end else if (io_din == CMD_TYPE) begin
                            host_req_cmd <= io_din;
                            host_req_valid <= 1'b1;
                            response_waiting <= 1'b1;
                            stream_active <= 1'b0;
                        end
                    end
                    REG_DATA: begin
                        request_ram[request_len] <= io_din;
                        if (io_din != 8'h00 && request_len != REQUEST_LAST) begin
                            request_len <= request_len + {{(REQUEST_BITS-1){1'b0}}, 1'b1};
                            request_ram[request_len + {{(REQUEST_BITS-1){1'b0}}, 1'b1}] <= 8'h00;
                        end
                    end
                    default: begin end
                endcase
            end

            if (io_rd_fall && old_io_addr == REG_DATA && stream_active) begin
                if (stream_index >= stream_len(command_reg) - 16'd1) begin
                    stream_active <= 1'b0;
                end else begin
                    stream_index <= stream_index + 16'd1;
                end
            end
        end
    end

    always_comb begin
        io_dout = 8'hFF;
        if (io_cs && io_rd) begin
            unique case (io_addr)
                REG_DATA:   io_dout = stream_byte(command_reg, stream_index);
                REG_STATUS: io_dout = status;
                REG_CMD:    io_dout = command_reg;
                REG_PARAM:  io_dout = param_reg;
                default:    io_dout = 8'hFF;
            endcase
        end
    end

endmodule
