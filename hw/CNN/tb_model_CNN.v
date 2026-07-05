`timescale 1ns / 1ps

module tb_model_CNN;

    parameter DATA_WIDTH  = 16;
    parameter OUT_CLASSES = 3;

    localparam TOTAL_PIXELS   = 40 * 64;
    localparam CLK_PERIOD     = 10;
    localparam TIMEOUT_CYCLES = 1000000;

    reg clk;
    reg rst_n;

    reg                         in_valid;
    wire                        in_ready;
    reg signed [DATA_WIDTH-1:0] in_pixel;

    wire                        out_valid;
    wire signed [15:0]          out_class_0;
    wire signed [15:0]          out_class_1;
    wire signed [15:0]          out_class_2;

    reg [15:0] tb_input_mem [0:TOTAL_PIXELS-1];
    reg [15:0] tb_gold_mem  [0:OUT_CLASSES-1];

    integer pixel_idx;
    integer cycle_count;

    model_CNN #(
        .DATA_WIDTH          (DATA_WIDTH),
        .OUT_CLASSES         (OUT_CLASSES),
        .FC_FIFO_DEPTH       (64),
        .FC_FIFO_ADDR_WIDTH  (6)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),

        .in_valid    (in_valid),
        .in_ready    (in_ready),
        .in_pixel    (in_pixel),

        .out_valid   (out_valid),
        .out_class_0 (out_class_0),
        .out_class_1 (out_class_1),
        .out_class_2 (out_class_2)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    task send_one_pixel;
        input [15:0] pix;
        begin
            @(negedge clk);
            in_valid <= 1'b1;
            in_pixel <= pix;

            @(posedge clk);
            while (in_ready !== 1'b1) begin
                @(posedge clk);
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
        end
        else begin
            cycle_count <= cycle_count + 1;

            if (cycle_count >= TIMEOUT_CYCLES) begin
                $display("[FAIL] TIMEOUT: model_CNN khong tao out_valid.");
                $finish;
            end
        end
    end

    initial begin
        $readmemh("model_cnn_input.hex", tb_input_mem);
        $readmemh("model_cnn_output_gold.hex", tb_gold_mem);

        rst_n    = 1'b0;
        in_valid = 1'b0;
        in_pixel = {DATA_WIDTH{1'b0}};

        repeat (10) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        for (pixel_idx = 0; pixel_idx < TOTAL_PIXELS; pixel_idx = pixel_idx + 1) begin
            send_one_pixel(tb_input_mem[pixel_idx]);
        end

        @(negedge clk);
        in_valid <= 1'b0;
        in_pixel <= {DATA_WIDTH{1'b0}};

        @(posedge out_valid);

        $display("=============================================");
        $display("CHECK TIME: %0t ns", $time);
        $display("Expected: C0=%04x C1=%04x C2=%04x",
                 tb_gold_mem[0], tb_gold_mem[1], tb_gold_mem[2]);
        $display("Actual  : C0=%04x C1=%04x C2=%04x",
                 out_class_0[15:0], out_class_1[15:0], out_class_2[15:0]);

        if ((out_class_0[15:0] === tb_gold_mem[0]) &&
            (out_class_1[15:0] === tb_gold_mem[1]) &&
            (out_class_2[15:0] === tb_gold_mem[2])) begin
            $display("[PASS] model_CNN output matches golden.");
        end
        else begin
            $display("[FAIL] model_CNN output mismatch.");
        end

        $display("=============================================");

        repeat (20) @(posedge clk);
        $finish;
    end

endmodule

