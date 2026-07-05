`timescale 1ns/1ps

module tb_maxpool_buffer();

    // 1. Khai báo Parameters và Signals
    parameter DATA_WIDTH = 16;
    parameter IMG_H = 6; // ??t b?ng 6 ?? log in ra ng?n g?n, d? ki?m tra

    reg clk;
    reg rst_n;
    reg buffer_in_valid;
    reg [DATA_WIDTH-1:0] in_pixel;
    
    wire [DATA_WIDTH-1:0] p0, p1, p2, p3;
    wire buffer_out_valid;

    // 2. Kh?i t?o Module c?n test (DUT - Design Under Test)
    maxpool_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_H(IMG_H)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .buffer_in_valid(buffer_in_valid),
        .in_pixel(in_pixel),
        .p0(p0),
        .p1(p1),
        .p2(p2),
        .p3(p3),
        .buffer_out_valid(buffer_out_valid)
    );

    // 3. T?o xung nh?p Clock (Chu k? 10ns)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 4. K?ch b?n Test (Stimulus)
    integer c, r;
    initial begin
        // Reset h? th?ng
        rst_n = 0;
        buffer_in_valid = 0;
        in_pixel = 0;
        
        #20;
        rst_n = 1; // Nh? reset
        #10;

        $display("==================================================");
        $display("BAT DAU TESTBENCH KHOI MAXPOOL BUFFER");
        $display("Quy uoc gia tri: in_pixel = (Cot * 100) + Hang");
        $display("Vi du: 102 nghia la Cot 1, Hang 2");
        $display("==================================================\n");

        // ??y d? li?u vào: Ch?y 4 c?t (0 ??n 3), m?i c?t có IMG_H hàng
        for (c = 0; c < 4; c = c + 1) begin
            for (r = 0; r < IMG_H; r = r + 1) begin
                @(posedge clk);
                buffer_in_valid <= 1;
                in_pixel <= c * 100 + r; // Gán giá tr? theo t?a ??
                
                // B?n có th? m? comment dòng d??i n?u mu?n xem log lúc ??y data vào
                // $display(" -> Nap vao: Cot %0d, Hang %0d | Data: %03d", c, r, c * 100 + r);
            end
        end

        // Ng?ng ??y d? li?u
        @(posedge clk);
        buffer_in_valid <= 0;

        #50;
        $display("==================================================");
        $display("HOAN THANH MO PHONG");
        $display("==================================================");
        $finish;
    end

    // 5. Kh?i Monitor: Theo dõi và in ra Log trên TCL khi có k?t qu?
    always @(posedge clk) begin
        if (buffer_out_valid) begin
            $display(">>> XUAT CUA SO 2x2 TAI THOI DIEM NAY:");
            $display("    p0 (Top-Left) : %03d  |  p1 (Top-Right) : %03d", p0, p1);
            $display("    p2 (Bot-Left) : %03d  |  p3 (Bot-Right) : %03d\n", p2, p3);
        end
    end

endmodule
