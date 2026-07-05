`timescale 1ns/1ps

module tb_maxpool_datapath();

    // 1. Khai báo tham s? và tín hi?u
    parameter DATA_WIDTH = 16;

    reg clk;
    reg rst_n;
    reg valid_in;
    reg [DATA_WIDTH-1:0] p0, p1, p2, p3;
    
    wire [DATA_WIDTH-1:0] max_out;
    wire valid_out;

    // 2. Kh?i t?o Module DUT (Design Under Test)
    // Chú ý: ?ây là b?n ?ã b? 'signed' vì b?n dùng ReLU
    maxpool_datapath #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .p0(p0),
        .p1(p1),
        .p2(p2),
        .p3(p3),
        .max_out(max_out),
        .valid_out(valid_out)
    );

    // 3. T?o xung nh?p Clock (10ns)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 4. K?ch b?n b?m d? li?u (Stimulus)
    initial begin
        // Reset h? th?ng ban ??u
        rst_n = 0;
        valid_in = 0;
        p0 = 0; p1 = 0; p2 = 0; p3 = 0;

        #20;
        rst_n = 1; // Nh? reset
        #10;

        $display("=======================================================");
        $display("BAT DAU TESTBENCH KHOI MAXPOOL DATAPATH (SAU RELU)");
        $display("=======================================================\n");

        // Test Case 1: Max n?m ? p0 (Top-Left)
        @(posedge clk);
        valid_in <= 1;
        p0 <= 150; p1 <= 45; p2 <= 12; p3 <= 99;

        // Test Case 2: Max n?m ? p1 (Top-Right)
        @(posedge clk);
        p0 <= 15; p1 <= 250; p2 <= 200; p3 <= 5;

        // Test Case 3: Max n?m ? p2 (Bot-Left)
        @(posedge clk);
        p0 <= 88; p1 <= 77; p2 <= 300; p3 <= 299;

        // Test Case 4: Max n?m ? p3 (Bot-Right)
        @(posedge clk);
        p0 <= 0; p1 <= 120; p2 <= 55; p3 <= 500;

        // Test Case 5: Có nhi?u s? b?ng nhau và là Max
        @(posedge clk);
        p0 <= 64; p1 <= 128; p2 <= 128; p3 <= 32;

        // Test Case 6: C? 4 s? b?ng nhau (Tr??ng h?p vùng ?nh t?nh/?en)
        @(posedge clk);
        p0 <= 42; p1 <= 42; p2 <= 42; p3 <= 42;

        // D?ng ??y d? li?u (H? c? valid)
        @(posedge clk);
        valid_in <= 0;
        p0 <= 0; p1 <= 0; p2 <= 0; p3 <= 0;

        #30;
        $display("\n=======================================================");
        $display("HOAN THANH MO PHONG");
        $display("=======================================================");
        $finish;
    end

    // 5. Kh?i Monitor: ??ng b? hi?n th? Input và Output
    // Vì Output tr? 1 nh?p so v?i Input, ta dùng thanh ghi d?i 1 nh?p ?? log hi?n th? kh?p nhau
    reg [DATA_WIDTH-1:0] p0_d, p1_d, p2_d, p3_d;
    
    always @(posedge clk) begin
        if (valid_in) begin
            p0_d <= p0;
            p1_d <= p1;
            p2_d <= p2;
            p3_d <= p3;
        end
    end

    always @(posedge clk) begin
        if (valid_out) begin
            $display("Input [p0:%3d, p1:%3d, p2:%3d, p3:%3d]  ==>  OUTPUT MAX = %3d", 
                     p0_d, p1_d, p2_d, p3_d, max_out);
        end
    end

endmodule