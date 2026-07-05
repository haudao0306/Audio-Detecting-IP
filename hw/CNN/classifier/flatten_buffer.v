module flatten_buffer #(
    parameter DATA_WIDTH       = 16,
    parameter IN_CHANNELS      = 64,
    parameter NUM_CYCLES       = 40,
    parameter BUS_WIDTH        = IN_CHANNELS * DATA_WIDTH,
    parameter CYCLE_IDX_WIDTH  = (NUM_CYCLES <= 2) ? 1 : $clog2(NUM_CYCLES),
    parameter COUNT_WIDTH      = CYCLE_IDX_WIDTH + 1
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire [BUS_WIDTH-1:0]         in_data_flat,

    input  wire                         restart_replay,
    input  wire                         next_cycle_en,
    input  wire                         clear_frame,

    output reg                          out_valid,
    output reg  [BUS_WIDTH-1:0]         out_data_flat,
    output reg  [CYCLE_IDX_WIDTH-1:0]   out_cycle_idx,
    output wire                         frame_ready,
    output wire                         last_cycle
);

    reg [BUS_WIDTH-1:0] mem [0:NUM_CYCLES-1];

    reg [CYCLE_IDX_WIDTH-1:0] wr_idx;
    reg [COUNT_WIDTH-1:0]     wr_count;
    reg [CYCLE_IDX_WIDTH-1:0] rd_idx;
    reg                       frame_full;

    wire write_en = in_valid && in_ready;

    assign in_ready    = !frame_full && (wr_count < NUM_CYCLES);
    assign frame_ready = frame_full;
    assign last_cycle  = out_valid && (rd_idx == NUM_CYCLES - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_idx        <= {CYCLE_IDX_WIDTH{1'b0}};
            wr_count      <= {COUNT_WIDTH{1'b0}};
            rd_idx        <= {CYCLE_IDX_WIDTH{1'b0}};
            frame_full    <= 1'b0;
            out_valid     <= 1'b0;
            out_data_flat <= {BUS_WIDTH{1'b0}};
            out_cycle_idx <= {CYCLE_IDX_WIDTH{1'b0}};
        end
        else begin
            if (clear_frame) begin
                wr_idx        <= {CYCLE_IDX_WIDTH{1'b0}};
                wr_count      <= {COUNT_WIDTH{1'b0}};
                rd_idx        <= {CYCLE_IDX_WIDTH{1'b0}};
                frame_full    <= 1'b0;
                out_valid     <= 1'b0;
                out_data_flat <= {BUS_WIDTH{1'b0}};
                out_cycle_idx <= {CYCLE_IDX_WIDTH{1'b0}};
            end
            else begin
                if (write_en) begin
                    mem[wr_idx] <= in_data_flat;

                    if (wr_count == NUM_CYCLES - 1) begin
                        frame_full <= 1'b1;
                        wr_count   <= wr_count + 1'b1;
                    end
                    else begin
                        wr_count <= wr_count + 1'b1;
                        wr_idx   <= wr_idx + 1'b1;
                    end
                end

                if (frame_full && restart_replay) begin
                    rd_idx        <= {CYCLE_IDX_WIDTH{1'b0}};
                    out_data_flat <= mem[0];
                    out_cycle_idx <= {CYCLE_IDX_WIDTH{1'b0}};
                    out_valid     <= 1'b1;
                end
                else if (out_valid && next_cycle_en) begin
                    if (rd_idx == NUM_CYCLES - 1) begin
                        out_valid <= 1'b0;
                    end
                    else begin
                        rd_idx        <= rd_idx + 1'b1;
                        out_data_flat <= mem[rd_idx + 1'b1];
                        out_cycle_idx <= rd_idx + 1'b1;
                        out_valid     <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
