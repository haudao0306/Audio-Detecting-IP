`timescale 1ns/1ps

module tb_classifier;

    reg clk;
    reg rst_n;
    
    reg in_valid;
    reg [1023:0] in_data_flat; // 64 kênh * 16-bit = 1024 bit
    
    // Tín hi?u Ready t? m?ch (B?T BU?C ?? handshake)
    wire in_ready; 
    
    wire out_valid;
    wire signed [15:0] out_class_0;
    wire signed [15:0] out_class_1;
    wire signed [15:0] out_class_2;

    // 1. Kh?i t?o Top Module
    classifier uut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_data_flat(in_data_flat),
        .out_valid(out_valid),
        .out_class_0(out_class_0),
        .out_class_1(out_class_1),
        .out_class_2(out_class_2)
    );

    // 2. T?o Clock (100MHz)
    always #5 clk = ~clk;

    // 3. Khai báo b? nh? ??c file Hex
    reg [1023:0] tb_input_mem [0:39];     // 40 dòng d? li?u vào
    reg signed [15:0] tb_gold_mem [0:2];  // 3 dòng d? li?u ra (?áp án)

    integer i;

    initial begin
        // Kh?i t?o tr?ng thái
        clk = 0;
        rst_n = 0;
        in_valid = 0;
        in_data_flat = 0;
        
        // Load file ki?m th?
        $readmemh("classifier_input.hex", tb_input_mem);
        $readmemh("classifier_gold_output.hex", tb_gold_mem);

        // 1. S?A RESET: Nh? reset ? s??n âm ?? m?ch không b? l? nh?p clock ??u tiên
        #25;
        @(negedge clk);
        rst_n = 1;
        #10;

        // B?T ??U C?P D? LI?U B?NG HANDSHAKE
        $display("[%0t] B?t ??u n?p 40 chu k? d? li?u vào Classifier...", $time);
        
        for (i = 0; i < 40; i = i + 1) begin
            // 2. S?A B?M DATA: Chu?n b? tín hi?u ? s??n ÂM
            @(negedge clk);
            in_valid = 1'b1;
            in_data_flat = tb_input_mem[i];
            
            // Ch? s??n D??NG ?? RTL ch?t d? li?u
            @(posedge clk);
            
            // N?u m?ch ?ang b?n (FIFO ??y ho?c Layer 1 b?n), gi? nguyên data và ch?
            while (in_ready === 1'b0) begin
                @(posedge clk);
            end
        end
        
        // K?t thúc 40 nh?p, h? c? ? s??n âm ti?p theo
        @(negedge clk);
        in_valid = 1'b0;
        
        // ??i tín hi?u out_valid xu?t hi?n
        wait(out_valid == 1'b1);
        
        // Ch? thêm 50ns r?i k?t thúc
        #50;
        $finish;
    end

    // -------------------------------------------------------------------------
    // [M?I THÊM] KH?I THEO DÕI VÀ IN K?T QU? C?A LAYER 1
    // -------------------------------------------------------------------------
    integer j; // Bi?n ch?y cho vòng l?p in node
    
    always @(posedge clk) begin
        // ?ã s?a l?i tên bi?n cho kh?p v?i module Top `classifier`
        // Thêm ?i?u ki?n in_ready ?? tránh in l?p n?u b? stall b?i FIFO
        if (uut.layer1_out_valid == 1'b1 && uut.layer1_out_ready == 1'b1) begin
            $display("\n=== ACTUAL OUTPUT OF LAYER 1 (128 NODES T? RTL) ===");
            $display("TH?I ?I?M: %0t ns", $time);
            
            for (j = 0; j < 128; j = j + 1) begin
                $display("Node %03d: %04h", j, uut.layer1_out_data[j*16 +: 16]);
            end
            
            $display("===================================================\n");
        end
    end
    // -------------------------------------------------------------------------


    // 4. KH?I KI?M TRA ?ÁP ÁN (ASSERTION) CHO TOP MODULE
    always @(posedge clk) begin
        if (out_valid) begin
            $display("\n=============================================");
            $display("TH?I ?I?M KI?M TRA: %0t ns", $time);
            
            if ((out_class_0 == tb_gold_mem[0]) && 
                (out_class_1 == tb_gold_mem[1]) && 
                (out_class_2 == tb_gold_mem[2])) begin
                
                $display("[SUCCESS] M?CH TOP CH?Y HOÀN H?O! ?ÁP ÁN KH?P 100%");
                $display(" -> Class 0: %h", out_class_0);
                $display(" -> Class 1: %h", out_class_1);
                $display(" -> Class 2: %h", out_class_2);
                
            end else begin
                
                $display("[ERROR] CÓ S? SAI L?CH D? LI?U ? MODULE TOP!");
                $display("--- MONG ??I (T? PYTHON) ---");
                $display(" C0: %h | C1: %h | C2: %h", tb_gold_mem[0], tb_gold_mem[1], tb_gold_mem[2]);
                $display("--- TH?C T? (T? M?CH CH?Y) ---");
                $display(" C0: %h | C1: %h | C2: %h", out_class_0, out_class_1, out_class_2);
                
            end
            $display("=============================================\n");
        end
    end

endmodule