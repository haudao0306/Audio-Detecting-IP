module conv_mac9 #(
    parameter DATA_WIDTH  = 16,
    parameter ACCUM_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,
    input wire en,

    input wire signed [DATA_WIDTH-1:0] p0,
    input wire signed [DATA_WIDTH-1:0] p1,
    input wire signed [DATA_WIDTH-1:0] p2,
    input wire signed [DATA_WIDTH-1:0] p3,
    input wire signed [DATA_WIDTH-1:0] p4,
    input wire signed [DATA_WIDTH-1:0] p5,
    input wire signed [DATA_WIDTH-1:0] p6,
    input wire signed [DATA_WIDTH-1:0] p7,
    input wire signed [DATA_WIDTH-1:0] p8,

    input wire signed [DATA_WIDTH-1:0] w0,
    input wire signed [DATA_WIDTH-1:0] w1,
    input wire signed [DATA_WIDTH-1:0] w2,
    input wire signed [DATA_WIDTH-1:0] w3,
    input wire signed [DATA_WIDTH-1:0] w4,
    input wire signed [DATA_WIDTH-1:0] w5,
    input wire signed [DATA_WIDTH-1:0] w6,
    input wire signed [DATA_WIDTH-1:0] w7,
    input wire signed [DATA_WIDTH-1:0] w8,

    output reg signed [ACCUM_WIDTH-1:0] partial_sum,
    output reg                          partial_valid
);

    reg signed [ACCUM_WIDTH-1:0] mult_reg [0:8];
    reg stage1_valid;

    wire signed [ACCUM_WIDTH-1:0] sum_all;

    assign sum_all =
        mult_reg[0] +
        mult_reg[1] +
        mult_reg[2] +
        mult_reg[3] +
        mult_reg[4] +
        mult_reg[5] +
        mult_reg[6] +
        mult_reg[7] +
        mult_reg[8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin

            mult_reg[0] <= 0;
            mult_reg[1] <= 0;
            mult_reg[2] <= 0;
            mult_reg[3] <= 0;
            mult_reg[4] <= 0;
            mult_reg[5] <= 0;
            mult_reg[6] <= 0;
            mult_reg[7] <= 0;
            mult_reg[8] <= 0;

            stage1_valid <= 1'b0;

        end
        else if (en) begin

            mult_reg[0] <= p0*w0;
            mult_reg[1] <= p1*w1;
            mult_reg[2] <= p2*w2;
            mult_reg[3] <= p3*w3;
            mult_reg[4] <= p4*w4;
            mult_reg[5] <= p5*w5;
            mult_reg[6] <= p6*w6;
            mult_reg[7] <= p7*w7;
            mult_reg[8] <= p8*w8;

            stage1_valid <= 1'b1;

        end
        else begin
            stage1_valid <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            partial_sum   <= 0;
            partial_valid <= 1'b0;

        end
        else begin

            partial_sum   <= sum_all;
            partial_valid <= stage1_valid;

        end
    end

endmodule