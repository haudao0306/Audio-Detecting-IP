`timescale 1ns/1ps

module tb_maxpool_top();

    parameter DATA_WIDTH = 16;
    parameter CHANNELS   = 16;
    parameter IMG_H      = 40;
    parameter IMG_W      = 64;
    
    localparam IN_LEN  = IMG_W * IMG_H;             
    localparam OUT_LEN = (IMG_W/2) * (IMG_H/2);     

    reg clk;
    reg rst_n;
    reg in_valid;
    reg [(CHANNELS * DATA_WIDTH)-1:0] in_pixels_256b;
    
    wire [(CHANNELS * DATA_WIDTH)-1:0] out_pixels_256b;
    wire out_valid;

    reg [255:0] in_mem  [0:IN_LEN-1];
    reg [255:0] ref_mem [0:OUT_LEN-1];

    initial begin
        $readmemh("input_256b.hex", in_mem);
        $readmemh("output_256b_ref.hex", ref_mem);
    end

    maxpool_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHANNELS(CHANNELS),
        .IMG_H(IMG_H)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_pixels_flat(in_pixels_256b),
        .out_pixels_flat(out_pixels_256b),
        .out_valid(out_valid)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    integer i;
    initial begin
        rst_n = 0;
        in_valid = 0;
        in_pixels_256b = 0;
        
        #25;
        rst_n = 1;
        #10;
        
        $display("\n======================================================================================");
        $display("   SO SANH CHI TIET OUTPUT MAXPOOL (COLUMN-MAJOR)");
        $display("   Format: [STT] | Status | Hardware Output | Golden (Python)");
        $display("======================================================================================\n");

        for (i = 0; i < IN_LEN; i = i + 1) begin
            @(posedge clk);
            in_valid <= 1'b1;
            in_pixels_256b <= in_mem[i];
        end
        
        @(posedge clk);
        in_valid <= 1'b0;
        in_pixels_256b <= 0;

        // ??i ??n khi nh?n ?? 640 k?t qu? ho?c h?t th?i gian timeout
        wait (out_cnt == OUT_LEN);
        #100;
        $finish;
    end

    // ==========================================
    // LOGIC HI?N TH? VÀ SO SÁNH CHI TI?T
    // ==========================================
    integer out_cnt = 0;
    integer error_cnt = 0;
    reg match;

    always @(posedge clk) begin
        if (out_valid) begin
            match = (out_pixels_256b === ref_mem[out_cnt]);
            
            if (match) begin
                // In ra ?? quan sát n?u b?n mu?n xem t?t c?, 
                // ho?c có th? comment l?i n?u ch? mu?n xem l?i
                $display("[%3d] | [ OK ]  | %h | %h", out_cnt, out_pixels_256b, ref_mem[out_cnt]);
            end else begin
                $display("[%3d] | [ ERR ] | %h | %h <--- SAI LECH!", out_cnt, out_pixels_256b, ref_mem[out_cnt]);
                error_cnt = error_cnt + 1;
            end
            
            out_cnt = out_cnt + 1;

            if (out_cnt == OUT_LEN) begin
                $display("\n======================================================================================");
                $display(">> TONG KET: Da kiem tra %0d mau.", OUT_LEN);
                if (error_cnt == 0) 
                    $display(">> KET QUA: CHINH XAC 100%%");
                else 
                    $display(">> KET QUA: PHAT HIEN %0d LOI!", error_cnt);
                $display("======================================================================================\n");
            end
        end
    end

endmodule