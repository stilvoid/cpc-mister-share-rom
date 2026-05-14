// SPDX-License-Identifier: GPL-2.0-or-later
// Small write-only HPS extension bridge for the experimental M4S directory index.

module m4s_hps_ext #(
    parameter int DIR_INDEX_BITS = 11
) (
    input  logic                      clk,
    input  logic                      reset,
    inout  wire [35:0]                EXT_BUS,

    output logic                      dir_index_begin,
    output logic                      dir_index_wr,
    output logic [DIR_INDEX_BITS-1:0] dir_index_addr,
    output logic [7:0]                dir_index_din
);

    localparam logic [7:0] CMD_DIR_BEGIN = 8'h70;
    localparam logic [7:0] CMD_DIR_WRITE = 8'h71;

    wire        io_strobe = EXT_BUS[33];
    wire        io_enable = EXT_BUS[34];
    wire [15:0] io_din    = EXT_BUS[31:16];

    logic old_io_strobe;
    logic write_active;
    logic seen_command;
    logic [DIR_INDEX_BITS-1:0] write_addr;

    wire io_strobe_rise = io_enable && io_strobe && !old_io_strobe;

    assign EXT_BUS[32] = 1'b0;

    always_ff @(posedge clk) begin
        if (reset) begin
            old_io_strobe  <= 1'b0;
            write_active   <= 1'b0;
            seen_command   <= 1'b0;
            write_addr     <= '0;
            dir_index_begin <= 1'b0;
            dir_index_wr   <= 1'b0;
            dir_index_addr <= '0;
            dir_index_din  <= 8'h00;
        end else begin
            old_io_strobe <= io_enable && io_strobe;
            dir_index_begin <= 1'b0;
            dir_index_wr <= 1'b0;

            if (!io_enable) begin
                write_active <= 1'b0;
                seen_command <= 1'b0;
            end else if (io_strobe_rise) begin
                if (!seen_command) begin
                    seen_command <= 1'b1;
                    write_active <= (io_din[7:0] == CMD_DIR_WRITE);

                    if (io_din[7:0] == CMD_DIR_BEGIN) begin
                        write_addr <= '0;
                        dir_index_begin <= 1'b1;
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
