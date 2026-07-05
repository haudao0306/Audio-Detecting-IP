`timescale 1ns / 1ps

module tb_features;

    // =====================================================
    // 1. PARAMETERS & ???NG D?N FILE
    // =====================================================
    parameter DATA_WIDTH   = 16;
    parameter ACCUM_WIDTH  = 32;

    // Kích th??c ?nh g?c ban ??u n?p vào m?ng CNN
    parameter IMG_H        = 40;
    parameter IMG_W        = 64;
    parameter OUT_CHANNELS = 64; // S? kênh ??u ra c?a Layer 3

    // T?ng s? l??ng m?u d? li?u ??u vào và ??u ra mong ??i
    localparam TOTAL_INPUTS  = IMG_H * IMG_W;                           // 40 * 64 = 2560 pixels ??n (16-bit)
    localparam TOTAL_OUTPUTS = (IMG_H / 8) * (IMG_W / 8);               // ?i qua 3 t?ng MaxPool (2x2x2 = 8) -> 5 * 8 = 40

    // C?ng bus ??u ra g?p (Flattened Bus)
    localparam OUT_BUS_WIDTH = OUT_CHANNELS * DATA_WIDTH;               // 64 * 16 = 1024-bit

    // Khai báo các tham s? hàng ??i FIFO n?i b?
    parameter FIFO12_DEPTH      = 1024;
    parameter FIFO12_ADDR_WIDTH = 10;
    parameter FIFO23_DEPTH      = 256;
    parameter FIFO23_ADDR_WIDTH = 8;

    // =====================================================
    // 2. TÍN HI?U K?T N?I DUT
    // =====================================================
    reg clk;
    reg rst_n;

    // ??u vào t? kh?i Log-Mel (M?i chu k? c?p 1 pixel ??n 16-bit)
    reg                        in_valid;
    wire                       in_ready;
    reg  signed [DATA_WIDTH-1:0] in_pixel;

    // ??u ra sau khi ?ã x? lý ??ng th?i qua 3 Layers
    wire [OUT_BUS_WIDTH-1:0]   out_pixels_flat;
    wire                       out_valid;

    // M?ng b? nh? gi? l?p n?p d? li?u t? Python
    reg [DATA_WIDTH-1:0]    input_memory    [0:TOTAL_INPUTS-1];
    reg [OUT_BUS_WIDTH-1:0] expected_memory [0:TOTAL_OUTPUTS-1];

    // Các bi?n vòng l?p và ??m l?i t?ng quan
    integer i;
    integer sent_count;
    integer out_count;
    integer error_count;

    // Các b? ??m giám sát tín hi?u n?i b? (Debug Counters) gi?a các Layer
    integer layer1_out_count;
    integer layer2_out_count;
    integer layer3_valid_count;

    // =====================================================
    // 3. DUT INSTANTIATION
    // =====================================================
    features #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .FIFO12_DEPTH(FIFO12_DEPTH),
        .FIFO12_ADDR_WIDTH(FIFO12_ADDR_WIDTH),
        .FIFO23_DEPTH(FIFO23_DEPTH),
        .FIFO23_ADDR_WIDTH(FIFO23_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_pixel(in_pixel),

        .out_pixels_flat(out_pixels_flat),
        .out_valid(out_valid)
    );

    // =====================================================
    // 4. CLOCK (Chu k? 10ns -> 100MHz)
    // =====================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =====================================================
    // 5. INIT / LOAD FILES
    // =====================================================
    initial begin
        $display("");
        $display("====================================================");
        $display(" LOADING TEST VECTORS FOR TOAN BO KHOI FEATURES (3 LAYERS)");
        $display("====================================================");

        $readmemh("input_features.mem", input_memory);
        $readmemh("output_features.mem", expected_memory);

        $display(" INPUT  VECTOR : input_features.mem");
        $display(" GOLDEN VECTOR : output_features.mem");
        $display(" TOTAL INPUTS  : %0d pixels ??n", TOTAL_INPUTS);
        $display(" TOTAL OUTPUTS : %0d kh?i ?a kênh (1024-bit)", TOTAL_OUTPUTS);
        $display("====================================================");
        $display("");
    end

    // =====================================================
    // 6. RESET
    // =====================================================
    initial begin
        rst_n    = 1'b0;
        in_valid = 1'b0;
        in_pixel = {DATA_WIDTH{1'b0}};

        sent_count  = 0;
        out_count   = 0;
        error_count = 0;

        layer1_out_count   = 0;
        layer2_out_count   = 0;
        layer3_valid_count = 0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
    end

    // =====================================================
    // 7. INPUT DRIVER WITH HANDSHAKE
    // =====================================================
    initial begin
        @(posedge rst_n);
        @(negedge clk);

        $display("");
        $display("====================================================");
        $display(" START SENDING INPUT STREAM TO FEATURES TOP");
        $display("====================================================");
        $display("");

        i = 0;

        while (i < TOTAL_INPUTS) begin
            @(negedge clk);

            in_valid = 1'b1;
            in_pixel = input_memory[i];

            @(posedge clk);

            if (in_ready) begin
                i = i + 1;
                sent_count = sent_count + 1;
            end
        end

        @(negedge clk);
        in_valid = 1'b0;
        in_pixel = {DATA_WIDTH{1'b0}};

        $display("");
        $display("====================================================");
        $display(" INPUT STREAM FINISHED");
        $display(" SENT INPUTS : %0d / %0d", sent_count, TOTAL_INPUTS);
        $display(" WAITING FOR OUTPUTS FROM LAYER 3");
        $display("====================================================");
        $display("");
    end

    // =====================================================
    // 8. DEBUG COUNTERS (Giám sát ti?n ?? truy?n d?n ???ng ?ng)
    // =====================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // ??m s? l??ng m?u ?ã thoát kh?i Layer 1 thành công
            if (dut.layer1_out_valid)
                layer1_out_count = layer1_out_count + 1;

            // ??m s? l??ng m?u ?ã thoát kh?i Layer 2 thành công
            if (dut.layer2_out_valid)
                layer2_out_count = layer2_out_count + 1;

            // ??m s? l??ng m?u ??u ra th?c t? t?i Top-level
            if (out_valid)
                layer3_valid_count = layer3_valid_count + 1;
        end
    end

    // =====================================================
    // 9. OUTPUT CHECKER
    // =====================================================
    always @(posedge clk) begin
        if (rst_n && out_valid) begin

            if (out_count >= TOTAL_OUTPUTS) begin
                $display("----------------------------------------------------");
                $display(" EXTRA OUTPUT FROM VERILOG");
                $display(" OUTPUT INDEX : %0d", out_count);
                $display(" VERILOG      : %h", out_pixels_flat);
                $display(" EXPECTED MAX : %0d outputs", TOTAL_OUTPUTS);
                $display("----------------------------------------------------");
                error_count = error_count + 1;
                finish_report();
            end

            $display("----------------------------------------------------");
            $display(" OUTPUT INDEX : %0d", out_count);
            $display(" VERILOG      : %h", out_pixels_flat);
            $display(" PYTHON       : %h", expected_memory[out_count]);

            if (out_pixels_flat !== expected_memory[out_count]) begin
                $display(" RESULT       : MISMATCH");
                error_count = error_count + 1;
            end
            else begin
                $display(" RESULT       : MATCH");
            end

            $display("----------------------------------------------------");
            $display("");

            out_count = out_count + 1;

            if (out_count == TOTAL_OUTPUTS) begin
                repeat (5) @(posedge clk);
                finish_report();
            end
        end
    end

    // =====================================================
    // 10. FINISH REPORT
    // =====================================================
    task finish_report;
    begin
        $display("");
        $display("====================================================");
        $display(" SIMULATION FINISHED");
        $display("====================================================");
        $display(" TOTAL INPUT SENT          : %0d / %0d", sent_count, TOTAL_INPUTS);
        $display(" LAYER 1 OUT VALID COUNT   : %0d", layer1_out_count);
        $display(" LAYER 2 OUT VALID COUNT   : %0d", layer2_out_count);
        $display(" LAYER 3 OUTPUT COUNT (TOP): %0d / %0d", out_count, TOTAL_OUTPUTS);
        $display(" LAYER 3 VALID RAW COUNT   : %0d", layer3_valid_count);
        $display(" TOTAL ERRORS              : %0d", error_count);

        if ((error_count == 0) && (out_count == TOTAL_OUTPUTS)) begin
            $display("");
            $display(" PASS: TOAN BO KHOI FEATURES CHAY CHINH XAC!");
        end
        else begin
            $display("");
            $display(" FAIL: CO LOI HOAC THIEU DU LIEU DAU RA!");
        end

        $display("====================================================");
        $display("");

        $finish;
    end
    endtask

    // =====================================================
    // 11. TIMEOUT WATCHDOG
    // =====================================================
    initial begin
        // Vì lu?ng d? li?u truy?n dài qua 3 t?ng Convolutions và 2 t?ng FIFO l?n, 
        // t?ng m?c b?o v? lên 5ms ?? ??m b?o x? s?ch hàng ??i.
        #5000000;

        $display("");
        $display("====================================================");
        $display(" TIMEOUT ERROR");
        $display("====================================================");
        $display(" TOTAL INPUT SENT          : %0d / %0d", sent_count, TOTAL_INPUTS);
        $display(" LAYER 1 OUT VALID COUNT   : %0d", layer1_out_count);
        $display(" LAYER 2 OUT VALID COUNT   : %0d", layer2_out_count);
        $display(" LAYER 3 OUTPUT COUNT (TOP): %0d / %0d", out_count, TOTAL_OUTPUTS);
        $display(" LAYER 3 VALID RAW COUNT   : %0d", layer3_valid_count);
        $display(" TOTAL ERRORS              : %0d", error_count);
        $display("====================================================");
        $display("");

        $finish;
    end

endmodule