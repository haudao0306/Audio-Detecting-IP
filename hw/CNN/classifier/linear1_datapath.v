module linear1_datapath #(
    parameter DATA_WIDTH       = 16,
    parameter CHANNELS         = 64,
    parameter NUM_CYCLES       = 40,
    parameter ACCUM_WIDTH      = 48,
    parameter PIXEL_FRAC       = 8,
    parameter WEIGHT_FRAC      = 8,
    parameter OUT_FRAC         = 8,
    parameter BUS_WIDTH        = CHANNELS * DATA_WIDTH,
    parameter CYCLE_IDX_WIDTH  = (NUM_CYCLES <= 2) ? 1 : $clog2(NUM_CYCLES)
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         in_valid,
    input  wire [CYCLE_IDX_WIDTH-1:0]   in_cycle_idx,

    input  wire [BUS_WIDTH-1:0]         in_data_flat,
    input  wire [BUS_WIDTH-1:0]         in_weight_flat,
    input  wire signed [DATA_WIDTH-1:0] in_bias,

    output reg                          out_valid,
    output reg  signed [DATA_WIDTH-1:0] out_node_data
);

    localparam TOTAL_FRAC  = PIXEL_FRAC + WEIGHT_FRAC;
    localparam SHIFT_RIGHT = TOTAL_FRAC - OUT_FRAC;
    localparam ROUND_CONST = 1 << (SHIFT_RIGHT - 1);
    localparam PROD_WIDTH  = 2 * DATA_WIDTH;

    integer c;

    reg signed [PROD_WIDTH-1:0]        mult_reg [0:CHANNELS-1];
    reg signed [DATA_WIDTH-1:0]        bias_s1;
    reg                                valid_s1;
    reg [CYCLE_IDX_WIDTH-1:0]          cycle_idx_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1     <= 1'b0;
            cycle_idx_s1 <= {CYCLE_IDX_WIDTH{1'b0}};
            bias_s1      <= {DATA_WIDTH{1'b0}};

            for (c = 0; c < CHANNELS; c = c + 1)
                mult_reg[c] <= {PROD_WIDTH{1'b0}};
        end
        else if (in_valid) begin
            for (c = 0; c < CHANNELS; c = c + 1) begin
                mult_reg[c] <=
                    $signed(in_data_flat[c*DATA_WIDTH +: DATA_WIDTH]) *
                    $signed(in_weight_flat[c*DATA_WIDTH +: DATA_WIDTH]);
            end

            valid_s1     <= 1'b1;
            cycle_idx_s1 <= in_cycle_idx;
            bias_s1      <= in_bias;
        end
        else begin
            valid_s1 <= 1'b0;
        end
    end

    reg signed [ACCUM_WIDTH-1:0] sum_l1 [0:31];
    reg signed [ACCUM_WIDTH-1:0] sum_l2 [0:15];
    reg signed [ACCUM_WIDTH-1:0] sum_l3 [0:7];
    reg signed [ACCUM_WIDTH-1:0] sum_l4 [0:3];
    reg signed [ACCUM_WIDTH-1:0] sum_l5 [0:1];
    reg signed [ACCUM_WIDTH-1:0] sum_l6;

    reg signed [DATA_WIDTH-1:0] bias_l1, bias_l2, bias_l3, bias_l4, bias_l5, bias_l6;
    reg                         valid_l1, valid_l2, valid_l3, valid_l4, valid_l5, valid_l6;
    reg [CYCLE_IDX_WIDTH-1:0]   cycle_idx_l1, cycle_idx_l2, cycle_idx_l3;
    reg [CYCLE_IDX_WIDTH-1:0]   cycle_idx_l4, cycle_idx_l5, cycle_idx_l6;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_l1     <= 1'b0;
            cycle_idx_l1 <= {CYCLE_IDX_WIDTH{1'b0}};
            bias_l1      <= {DATA_WIDTH{1'b0}};
            for (c = 0; c < 32; c = c + 1)
                sum_l1[c] <= {ACCUM_WIDTH{1'b0}};
        end
        else if (valid_s1) begin
            for (c = 0; c < 32; c = c + 1) begin
                sum_l1[c] <=
                    {{(ACCUM_WIDTH-PROD_WIDTH){mult_reg[2*c][PROD_WIDTH-1]}}, mult_reg[2*c]} +
                    {{(ACCUM_WIDTH-PROD_WIDTH){mult_reg[2*c+1][PROD_WIDTH-1]}}, mult_reg[2*c+1]};
            end
            valid_l1     <= 1'b1;
            cycle_idx_l1 <= cycle_idx_s1;
            bias_l1      <= bias_s1;
        end
        else begin
            valid_l1 <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_l2     <= 1'b0;
            cycle_idx_l2 <= {CYCLE_IDX_WIDTH{1'b0}};
            bias_l2      <= {DATA_WIDTH{1'b0}};
            for (c = 0; c < 16; c = c + 1)
                sum_l2[c] <= {ACCUM_WIDTH{1'b0}};
        end
        else if (valid_l1) begin
            for (c = 0; c < 16; c = c + 1)
                sum_l2[c] <= sum_l1[2*c] + sum_l1[2*c+1];
            valid_l2     <= 1'b1;
            cycle_idx_l2 <= cycle_idx_l1;
            bias_l2      <= bias_l1;
        end
        else begin
            valid_l2 <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_l3     <= 1'b0;
            cycle_idx_l3 <= {CYCLE_IDX_WIDTH{1'b0}};
            bias_l3      <= {DATA_WIDTH{1'b0}};
            for (c = 0; c < 8; c = c + 1)
                sum_l3[c] <= {ACCUM_WIDTH{1'b0}};
        end
        else if (valid_l2) begin
            for (c = 0; c < 8; c = c + 1)
                sum_l3[c] <= sum_l2[2*c] + sum_l2[2*c+1];
            valid_l3     <= 1'b1;
            cycle_idx_l3 <= cycle_idx_l2;
            bias_l3      <= bias_l2;
        end
        else begin
            valid_l3 <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_l4     <= 1'b0;
            cycle_idx_l4 <= {CYCLE_IDX_WIDTH{1'b0}};
            bias_l4      <= {DATA_WIDTH{1'b0}};
            for (c = 0; c < 4; c = c + 1)
                sum_l4[c] <= {ACCUM_WIDTH{1'b0}};
        end
        else if (valid_l3) begin
            for (c = 0; c < 4; c = c + 1)
                sum_l4[c] <= sum_l3[2*c] + sum_l3[2*c+1];
            valid_l4     <= 1'b1;
            cycle_idx_l4 <= cycle_idx_l3;
            bias_l4      <= bias_l3;
        end
        else begin
            valid_l4 <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_l5     <= 1'b0;
            cycle_idx_l5 <= {CYCLE_IDX_WIDTH{1'b0}};
            bias_l5      <= {DATA_WIDTH{1'b0}};
            for (c = 0; c < 2; c = c + 1)
                sum_l5[c] <= {ACCUM_WIDTH{1'b0}};
        end
        else if (valid_l4) begin
            sum_l5[0]    <= sum_l4[0] + sum_l4[1];
            sum_l5[1]    <= sum_l4[2] + sum_l4[3];
            valid_l5     <= 1'b1;
            cycle_idx_l5 <= cycle_idx_l4;
            bias_l5      <= bias_l4;
        end
        else begin
            valid_l5 <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_l6     <= 1'b0;
            cycle_idx_l6 <= {CYCLE_IDX_WIDTH{1'b0}};
            bias_l6      <= {DATA_WIDTH{1'b0}};
            sum_l6       <= {ACCUM_WIDTH{1'b0}};
        end
        else if (valid_l5) begin
            sum_l6       <= sum_l5[0] + sum_l5[1];
            valid_l6     <= 1'b1;
            cycle_idx_l6 <= cycle_idx_l5;
            bias_l6      <= bias_l5;
        end
        else begin
            valid_l6 <= 1'b0;
        end
    end

    reg signed [ACCUM_WIDTH-1:0] accum_reg;
    reg signed [ACCUM_WIDTH-1:0] accum_s2;
    reg signed [DATA_WIDTH-1:0]  bias_s2;
    reg                          valid_s2;
    reg [CYCLE_IDX_WIDTH-1:0]    cycle_idx_s2;

    wire signed [ACCUM_WIDTH-1:0] accum_next =
        (cycle_idx_l6 == {CYCLE_IDX_WIDTH{1'b0}}) ? sum_l6 : (accum_reg + sum_l6);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum_reg    <= {ACCUM_WIDTH{1'b0}};
            accum_s2     <= {ACCUM_WIDTH{1'b0}};
            bias_s2      <= {DATA_WIDTH{1'b0}};
            valid_s2     <= 1'b0;
            cycle_idx_s2 <= {CYCLE_IDX_WIDTH{1'b0}};
        end
        else if (valid_l6) begin
            accum_reg    <= accum_next;
            accum_s2     <= accum_next;
            bias_s2      <= bias_l6;
            valid_s2     <= 1'b1;
            cycle_idx_s2 <= cycle_idx_l6;
        end
        else begin
            valid_s2 <= 1'b0;
        end
    end

    wire signed [ACCUM_WIDTH-1:0] bias_ext =
        {{(ACCUM_WIDTH-DATA_WIDTH){bias_s2[DATA_WIDTH-1]}}, bias_s2};

    wire signed [ACCUM_WIDTH-1:0] aligned_bias =
        bias_ext <<< SHIFT_RIGHT;

    wire signed [ACCUM_WIDTH-1:0] final_sum =
        accum_s2 + aligned_bias;

    wire signed [ACCUM_WIDTH-1:0] relu_out =
        (final_sum > 0) ? final_sum : {ACCUM_WIDTH{1'b0}};

    wire [ACCUM_WIDTH-1:0] rounded =
        relu_out + ROUND_CONST;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid     <= 1'b0;
            out_node_data <= {DATA_WIDTH{1'b0}};
        end
        else if (valid_s2 && (cycle_idx_s2 == NUM_CYCLES - 1)) begin
            if (|rounded[ACCUM_WIDTH-2 : DATA_WIDTH + SHIFT_RIGHT - 1])
                out_node_data <= {1'b0, {(DATA_WIDTH-1){1'b1}}};
            else
                out_node_data <= rounded[DATA_WIDTH + SHIFT_RIGHT - 1 : SHIFT_RIGHT];

            out_valid <= 1'b1;
        end
        else begin
            out_valid <= 1'b0;
        end
    end

endmodule