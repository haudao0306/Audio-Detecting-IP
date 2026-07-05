module stream_fifo #(
    parameter DATA_WIDTH = 16,
    parameter DEPTH      = 1024,
    parameter ADDR_WIDTH = 10
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire [DATA_WIDTH-1:0] in_data,

    output reg                   out_valid,
    input  wire                  out_ready,
    output reg  [DATA_WIDTH-1:0] out_data
);

    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0]   count;

    reg                  rd_pending;
    reg [DATA_WIDTH-1:0] rd_data_q;

    wire input_fire  = in_valid && in_ready;
    wire output_fire = out_valid && out_ready;

    wire output_slot_free = !out_valid || out_ready;
    wire can_start_read   = (count != 0) && output_slot_free && !rd_pending;

    assign in_ready = (count < DEPTH);

    // Keep RAM in a clock-only process. Vivado cannot infer BRAM if this
    // process is sensitive to an asynchronous reset, even when mem is not reset.
    always @(posedge clk) begin
        if (input_fire)
            mem[wr_ptr] <= in_data;

        if (can_start_read)
            rd_data_q <= mem[rd_ptr];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= {ADDR_WIDTH{1'b0}};
            rd_ptr     <= {ADDR_WIDTH{1'b0}};
            count      <= {(ADDR_WIDTH+1){1'b0}};
            rd_pending <= 1'b0;
            out_valid  <= 1'b0;
            out_data   <= {DATA_WIDTH{1'b0}};
        end
        else begin
            if (input_fire)
                wr_ptr      <= wr_ptr + 1'b1;

            if (can_start_read) begin
                rd_ptr     <= rd_ptr + 1'b1;
                rd_pending <= 1'b1;
            end
            else begin
                rd_pending <= 1'b0;
            end

            if (output_fire)
                out_valid <= 1'b0;

            if (rd_pending) begin
                out_data  <= rd_data_q;
                out_valid <= 1'b1;
            end

            case ({input_fire, can_start_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule

