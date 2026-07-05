`timescale 1ns/1ps

module tb_classifier_layer2;

    reg clk;
    reg rst_n;
    reg in_valid;
    reg [2047:0] in_layer1_data;
    
    wire out_valid;
    wire signed [15:0] out_class_0;
    wire signed [15:0] out_class_1;
    wire signed [15:0] out_class_2;

    // 1. Kh?i t?o UUT (Unit Under Test)
    classifier_layer2 uut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_layer1_data(in_layer1_data),
        .out_valid(out_valid),
        .out_class_0(out_class_0),
        .out_class_1(out_class_1),
        .out_class_2(out_class_2)
    );

    // 2. T?o xung Clock 100MHz (Chu k? 10ns)
    always #5 clk = ~clk;

    // 3. Khai báo b? nh? ?? n?p file Test Vector
    // - B? nh? Input: 1 ph?n t? r?ng 2048-bit
    reg [2047:0] tb_input_mem [0:0]; 
    // - B? nh? ?áp án (Gold Output): 3 ph?n t? r?ng 16-bit (Cho Class 0, 1, 2)
    reg signed [15:0] tb_gold_mem [0:2];

    initial begin
        // Kh?i t?o tr?ng thái ban ??u
        clk = 0;
        rst_n = 0;
        in_valid = 0;
        in_layer1_data = 0;
        
        // ??c d? li?u t? file sinh ra b?i Python
        $readmemh("classifier2_input.hex", tb_input_mem);
        $readmemh("classifier2_gold_output.hex", tb_gold_mem);

        // Reset h? th?ng
        #20;
        rst_n = 1;
        #20;

        // B?T ??U C?P KÍCH THÍCH (STIMULUS)
        @(posedge clk);
        in_valid = 1'b1;
        in_layer1_data = tb_input_mem[0]; // B?m tr?n gói 2048-bit vào trong 1 nh?p
        
        @(posedge clk);
        in_valid = 1'b0; // H? c? Valid xu?ng, ch? ??y 1 nh?p duy nh?t
        
        // Ch? thêm m?t th?i gian ?? m?ch Pipeline tính toán xong và xu?t k?t qu?
        #100;
        $display("--- HOÀN THÀNH KI?M TH? ---");
        $finish;
    end

    // 4. KH?I T? ??NG SO SÁNH K?T QU? T?I ??U RA (ASSERTION CHECKER)
    always @(posedge clk) begin
        if (out_valid) begin
            $display("\n=============================================");
            $display("TH?I ?I?M KI?M TRA: %0t ns", $time);
            
            // ??i chi?u v?i b? nh? tb_gold_mem (0 -> C0, 1 -> C1, 2 -> C2)
            if ((out_class_0 == tb_gold_mem[0]) && 
                (out_class_1 == tb_gold_mem[1]) && 
                (out_class_2 == tb_gold_mem[2])) begin
                
                $display("[SUCCESS] K?T QU? KH?P 100% V?I MÔ HÌNH PYTORCH!");
                $display(" -> Class 0: %h", out_class_0);
                $display(" -> Class 1: %h", out_class_1);
                $display(" -> Class 2: %h", out_class_2);
                
            end else begin
                
                $display("[ERROR] SAI L?CH K?T QU?!");
                $display("--- MONG ??I (T? PYTHON) ---");
                $display(" C0: %h | C1: %h | C2: %h", tb_gold_mem[0], tb_gold_mem[1], tb_gold_mem[2]);
                $display("--- TH?C T? (T? M?CH CH?Y) ---");
                $display(" C0: %h | C1: %h | C2: %h", out_class_0, out_class_1, out_class_2);
                
            end
            $display("=============================================\n");
        end
    end

endmodule