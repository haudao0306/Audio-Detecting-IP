`timescale 1ns / 1ps

module tb_linear1_datapath;

    // =========================================================
    // 1. KHAI BÁO PARAMETER MATCH V?I DUT
    // =========================================================
    parameter DATA_WIDTH  = 16;
    parameter CHANNELS    = 64;
    parameter ACCUM_WIDTH = 32;
    parameter Q_FRAC      = 8;
    localparam BUS_WIDTH  = CHANNELS * DATA_WIDTH; // 1024-bit

    // =========================================================
    // 2. KHAI BÁO CÁC TÍN HI?U K?T N?I
    // =========================================================
    reg                      clk;
    reg                      rst_n;
    reg                      in_valid;
    reg  [5:0]               in_cycle_idx;
    reg  [BUS_WIDTH-1:0]     in_data_flat;
    reg  [BUS_WIDTH-1:0]     in_weight_flat;
    reg  signed [DATA_WIDTH-1:0] in_bias;

    wire                     out_valid;
    wire signed [DATA_WIDTH-1:0] out_node_data;

    // Bi?n ph?c v? vòng l?p
    integer cycle;

    // =========================================================
    // 3. KH?I T?O MODULE C?N TEST (DUT)
    // =========================================================
    linear1_datapath #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHANNELS(CHANNELS),
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .Q_FRAC(Q_FRAC)
    ) DUT (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_cycle_idx(in_cycle_idx),
        .in_data_flat(in_data_flat),
        .in_weight_flat(in_weight_flat),
        .in_bias(in_bias),
        .out_valid(out_valid),
        .out_node_data(out_node_data)
    );

    // =========================================================
    // 4. T?O XUNG CLOCK (100MHz -> Chu k? 10ns)
    // =========================================================
    always #5 clk = ~clk;

    // =========================================================
    // 5. K?CH B?N MÔ PH?NG (STIMULUS)
    // =========================================================
    initial begin
        // Kh?i t?o các giá tr? ban ??u
        clk = 0;
        rst_n = 0;
        in_valid = 0;
        in_cycle_idx = 0;
        in_data_flat = 0;
        in_weight_flat = 0;
        in_bias = 0;

        $display("==========================================================");
        $display("[TB] BAT DAU KIERM TRA CLASSIFIER LINEAR1 DATAPATH");
        $display("==========================================================");

        // Reset h? th?ng
        #20;
        rst_n = 1;
        #20;

        // --------------------------------------------------------
        // TEST CASE 1: TÍNH TOÁN K?T QU? D??NG (KI?M TRA ACCUM + BIAS + ROUNDING)
        // --------------------------------------------------------
        // C?u hình toán h?c (D?ng fixed-point Q8.8):
        // - M?i kênh data = 16'h0010 (t?c là 16/256 = 0.0625)
        // - M?i kênh weight = 16'h0020 (t?c là 32/256 = 0.125)
        // - Tích 1 c?p = 0.0625 * 0.125 = 0.0078125
        // - T?ng 64 kênh trong 1 nh?p = 0.0078125 * 64 = 0.5
        // - Tích l?y qua 40 nh?p = 0.5 * 40 = 20.0
        // - N?p thêm Bias = 16'h0100 (t?c là 1.0)
        // => K?t qu? lý thuy?t mong ??i = 20.0 + 1.0 = 21.0 (Hex trong Q8.8 là 16'h1500)
        
        in_bias = 16'h0100; // Bias = +1.0
        $display("[TB] => Bat dau TEST CASE 1: Ket qua duong (Ky vong: 21.0 / Hex: 1500)");

        for (cycle = 0; cycle < 40; cycle = cycle + 1) begin
            @(posedge clk);
            in_valid     <= 1'b1;
            in_cycle_idx <= cycle[5:0];
            // Sao chép giá tr? c? ??nh ra toàn b? 64 kênh (1024-bit)
            in_data_flat   <= { CHANNELS { 16'h0010 } }; 
            in_weight_flat <= { CHANNELS { 16'h0020 } };
        end

        // K?t thúc 40 nh?p, t?t valid ??u vào và ch? k?t qu? t? Pipeline trôi ra
        @(posedge clk);
        in_valid     <= 1'b0;
        in_cycle_idx <= 6'd0;
        in_data_flat <= 1024'd0;
        in_weight_flat <= 1024'd0;

        // Ch? xem k?t qu? ??u ra xu?t hi?n (Do thi?t k? tr? pipeline 3 t?ng)
        @(posedge clk);
        while (!out_valid) @(posedge clk); 
        
        // Ki?m tra k?t qu? Test Case 1
        $display("[RESULT] Thoi gian: %0t ns | Out_Valid = %b | Out_Data = 16'h%h", $time, out_valid, out_node_data);
        if (out_node_data === 16'h1500) begin
            $display("[SUCCESS] TEST CASE 1: PASSED!");
        end else begin
            $display("[ERROR] TEST CASE 1: FAILED! Sai lech ket qua.");
        end

        #50; // Ngh? ng?i gi?a 2 test case

        // --------------------------------------------------------
        // TEST CASE 2: TÍNH TOÁN K?T QU? ÂM (KI?M TRA RELU CHÉM V? 0)
        // --------------------------------------------------------
        // - Gi? nguyên data và weight nh? c? (T?ng tích l?y v?n là 20.0)
        // - Thay Bias c?c âm = -50.0 (Hex Q8.8: 16'hCE00)
        // => K?t qu? tr??c ReLU = 20.0 + (-50.0) = -30.0
        // => K?t qu? sau ReLU mong ??i = 0.0 (Hex: 16'h0000)
        
        in_bias = 16'hCE00; // Bias = -50.0
        $display("[TB] => Bat dau TEST CASE 2: Ket qua am de test ReLU (Ky vong: 0.0 / Hex: 0000)");

        for (cycle = 0; cycle < 40; cycle = cycle + 1) begin
            @(posedge clk);
            in_valid     <= 1'b1;
            in_cycle_idx <= cycle[5:0];
            in_data_flat   <= { CHANNELS { 16'h0010 } }; 
            in_weight_flat <= { CHANNELS { 16'h0020 } };
        end

        // T?t valid ??u vào
        @(posedge clk);
        in_valid     <= 1'b0;
        in_cycle_idx <= 6'd0;
        in_data_flat <= 1024'd0;
        in_weight_flat <= 1024'd0;

        // Ch? k?t qu? ??u ra
        @(posedge clk);
        while (!out_valid) @(posedge clk);

        // Ki?m tra k?t qu? Test Case 2
        $display("[RESULT] Thoi gian: %0t ns | Out_Valid = %b | Out_Data = 16'h%h", $time, out_valid, out_node_data);
        if (out_node_data === 16'h0000) begin
            $display("[SUCCESS] TEST CASE 2: PASSED!");
        end else begin
            $display("[ERROR] TEST CASE 2: FAILED! ReLU khong hoat dong.");
        end

        $display("==========================================================");
        $display("[TB] HOAN THANH MO PHONG SIMULATION");
        $display("==========================================================");
        $finish;
    end

endmodule
