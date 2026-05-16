// SPDX-License-Identifier: GPL-2.0-or-later
// Small HPS extension bridge for the experimental CMS directory index.

/* verilator lint_off UNOPTFLAT */
module cms_hps_ext #(
    parameter int DIR_INDEX_BITS = 11
) (
    input  logic                      clk,
    input  logic                      reset,
    inout  wire [35:0]                EXT_BUS,

    output logic                      dir_index_begin,
    output logic                      dir_index_wr,
    output logic [DIR_INDEX_BITS-1:0] dir_index_addr,
    output logic [7:0]                dir_index_din,
    output logic                      dir_index_done,

    input  logic                      host_req_pending,
    input  logic [7:0]                host_req_len,
    output logic [7:0]                host_req_addr,
    input  logic [7:0]                host_req_data,
    output logic                      host_req_ack
);

    localparam logic [7:0] CMD_DIR_BEGIN = 8'h70;
    localparam logic [7:0] CMD_DIR_WRITE = 8'h71;
    localparam logic [7:0] CMD_REQ_STATUS = 8'h72;
    localparam logic [7:0] CMD_REQ_READ   = 8'h73;
    localparam logic [7:0] CMD_REQ_ACK    = 8'h74;
    localparam logic [7:0] CMD_RESP_DONE  = 8'h77;

    wire        io_strobe = EXT_BUS[33];
    wire        io_enable = EXT_BUS[34];
    wire [15:0] io_din    = EXT_BUS[31:16];

    logic old_io_strobe;
    logic write_active;
    logic read_status_active;
    logic read_request_active;
    logic seen_command;
    logic [DIR_INDEX_BITS-1:0] write_addr;

    wire io_strobe_rise = io_enable && io_strobe && !old_io_strobe;
    wire ext_drive = io_enable && (read_status_active || read_request_active);
    wire [15:0] ext_dout = read_status_active ?
                           {host_req_len, 7'b0000000, host_req_pending} :
                           {8'h00, host_req_data};

    /* verilator lint_off UNOPTFLAT */
    assign EXT_BUS[32] = ext_drive;
    assign EXT_BUS[15:0] = ext_drive ? ext_dout : 16'hzzzz;
    /* verilator lint_on UNOPTFLAT */
    assign host_req_addr = io_din[7:0];

    always_ff @(posedge clk) begin
        if (reset) begin
            old_io_strobe  <= 1'b0;
            write_active   <= 1'b0;
            read_status_active <= 1'b0;
            read_request_active <= 1'b0;
            seen_command   <= 1'b0;
            write_addr     <= '0;
            dir_index_begin <= 1'b0;
            dir_index_wr   <= 1'b0;
            dir_index_addr <= '0;
            dir_index_din  <= 8'h00;
            dir_index_done <= 1'b0;
            host_req_ack   <= 1'b0;
        end else begin
            old_io_strobe <= io_enable && io_strobe;
            dir_index_begin <= 1'b0;
            dir_index_wr <= 1'b0;
            dir_index_done <= 1'b0;
            host_req_ack <= 1'b0;

            if (!io_enable) begin
                write_active <= 1'b0;
                read_status_active <= 1'b0;
                read_request_active <= 1'b0;
                seen_command <= 1'b0;
            end else if (io_strobe_rise) begin
                if (!seen_command) begin
                    seen_command <= 1'b1;
                    write_active <= (io_din[7:0] == CMD_DIR_WRITE);
                    read_status_active <= (io_din[7:0] == CMD_REQ_STATUS);
                    read_request_active <= (io_din[7:0] == CMD_REQ_READ);

                    if (io_din[7:0] == CMD_DIR_BEGIN) begin
                        write_addr <= '0;
                        dir_index_begin <= 1'b1;
                    end else if (io_din[7:0] == CMD_REQ_ACK) begin
                        host_req_ack <= 1'b1;
                    end else if (io_din[7:0] == CMD_RESP_DONE) begin
                        dir_index_done <= 1'b1;
                    end
                end else if (write_active) begin
                    dir_index_wr <= 1'b1;
                    dir_index_addr <= write_addr;
                    dir_index_din <= io_din[7:0];
                    write_addr <= write_addr + {{(DIR_INDEX_BITS-1){1'b0}}, 1'b1};
                end
            end
        end
    end

endmodule
/* verilator lint_on UNOPTFLAT */
