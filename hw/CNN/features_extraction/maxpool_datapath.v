module maxpool_datapath #(
    parameter DATA_WIDTH = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  valid_in,
    
    input  wire  [DATA_WIDTH-1:0] p0,
    input  wire  [DATA_WIDTH-1:0] p1,
    input  wire  [DATA_WIDTH-1:0] p2,
    input  wire  [DATA_WIDTH-1:0] p3,
    
    output reg   [DATA_WIDTH-1:0] max_out,
    output reg                   valid_out
);

    // ==========================================
    // T?NG 1: M?CH T? H?P (COMBINATIONAL LOGIC)
    // ==========================================
    // So sánh song song 2 c?p ??c l?p ?? gi?m Critical Path
    wire  [DATA_WIDTH-1:0] max_01;
    wire  [DATA_WIDTH-1:0] max_23;
    
    assign max_01 = (p0 > p1) ? p0 : p1;
    assign max_23 = (p2 > p3) ? p2 : p3;

    // ==========================================
    // T?NG 2: THANH GHI CH?T K?T QU? (PIPELINE)
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            max_out   <= 0;
            valid_out <= 1'b0;
        end 
        else begin
            // Tín hi?u valid_out s? tr? 1 nh?p so v?i valid_in
            valid_out <= valid_in; 
            
            if (valid_in) begin
                // So sánh chung k?t và l?u th?ng vào Flip-Flop ??u ra
                max_out <= (max_01 > max_23) ? max_01 : max_23;
            end
        end
    end

endmodule