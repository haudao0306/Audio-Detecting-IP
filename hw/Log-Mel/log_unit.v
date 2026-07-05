// ============================================================

//  log_unit.v

//  Logarithm Unit cho Log-Mel pipeline - LUT based

//  [FIXED] ?ã s?a l?i tràn s? n_contrib_wide và logic Clipper

// ============================================================



module log_unit #(

    parameter IN_WIDTH  = 57,

    parameter Q_SHIFT   = 15,

    parameter E_WIDTH   = 42,

    parameter LUT_BITS  = 12,

    parameter LUT_SIZE  = 4096,

    parameter OUT_WIDTH = 16,   

    parameter FRAC_BITS = 12,

    parameter IDX_WIDTH = 6

)(

    input  wire                 clk,

    input  wire                 reset_n,

    input  wire                 enable,

    input  wire                 valid_in,

    input  wire [IN_WIDTH-1:0]  log_in,

    input  wire [IDX_WIDTH-1:0] idx_in,



    output reg  [OUT_WIDTH-1:0] log_out,

    output reg                  valid_out,

    output reg  [IDX_WIDTH-1:0] idx_out

);



    // --------------------------------------------------------

    // Ki?m tra tham s? t?i elaboration

    // --------------------------------------------------------

    initial begin

        if (E_WIDTH != IN_WIDTH - Q_SHIFT) $error("log_unit: E_WIDTH sai");

        if (LUT_SIZE != (1 << LUT_BITS)) $error("log_unit: LUT_SIZE sai");

        if (OUT_WIDTH < 18) $warning("OUT_WIDTH < 18 co the gay tran so voi E_WIDTH=42");

    end



    // ROM

    reg [15:0] lut_mem [0:LUT_SIZE-1]; // LUT ch? c?n 16 bit

    initial begin

        $readmemh("log_lut.mem", lut_mem);

    end



    // ============================================================

    // STAGE 0 (Combinational)

    // ============================================================

    wire [E_WIDTH-1:0] e_raw = log_in[IN_WIDTH-1 : Q_SHIFT];

    wire [E_WIDTH-1:0] e_val = (e_raw == {E_WIDTH{1'b0}}) ? {{(E_WIDTH-1){1'b0}}, 1'b1} : e_raw;



    reg  [5:0] msb_pos_comb;

    integer k;

    always @(*) begin

        msb_pos_comb = 6'd0;

        for (k = 0; k < E_WIDTH; k = k + 1) begin

            if (e_val[k]) msb_pos_comb = k[5:0];

        end

    end



    // Stage 1 registers

    reg [5:0]           msb_s1;

    reg [E_WIDTH-1:0]   eval_s1;

    reg                 v_s1;

    reg [IDX_WIDTH-1:0] idx_s1;



    always @(posedge clk or negedge reset_n) begin

        if (!reset_n) begin

            msb_s1  <= 6'd0; eval_s1 <= 0;

            v_s1    <= 1'b0; idx_s1  <= 0;

        end else if (enable) begin

            msb_s1  <= msb_pos_comb; eval_s1 <= e_val;

            v_s1    <= valid_in;     idx_s1  <= idx_in;

        end else begin

            v_s1    <= 1'b0;

        end

    end



    // ============================================================

    // STAGE 1 -> STAGE 2

    // ============================================================

    wire [5:0]          shift_amt = (E_WIDTH - 1) - msb_s1;

    wire [E_WIDTH-1:0]  norm_val  = eval_s1 << shift_amt;

    wire [LUT_BITS-1:0] lut_addr_comb = norm_val[E_WIDTH-2 -: LUT_BITS];



    reg [5:0]           n_s2;

    reg [LUT_BITS-1:0]  addr_s2;

    reg                 v_s2;

    reg [IDX_WIDTH-1:0] idx_s2;



    always @(posedge clk or negedge reset_n) begin

        if (!reset_n) begin

            n_s2    <= 6'd0; addr_s2 <= 0;

            v_s2    <= 1'b0; idx_s2  <= 0;

        end else if (enable) begin

            n_s2    <= msb_s1;       addr_s2 <= lut_addr_comb;

            v_s2    <= v_s1;         idx_s2  <= idx_s1;

        end else begin

            v_s2    <= 1'b0;

        end

    end



    // ============================================================

    // STAGE 2 -> STAGE 3 (Output)

    // ============================================================

    wire [15:0] lut_val = lut_mem[addr_s2];

    

    // Tính t?ng Log thô ? ??nh d?ng Q6.12 (FRAC_BITS = 12)

    wire [18:0] n_contrib_wide = {13'd0, n_s2} << FRAC_BITS; 

    wire [18:0] log_sum_q12 = n_contrib_wide + {3'd0, lut_val};



    // 1. ??a v? ??nh d?ng Q6.10 gi?ng hàm (np.log2 * 1024.0) c?a Python

    wire [18:0] log_sum_q10 = log_sum_q12 >> 2;



    // 2. Bù tr? sai s? h? th?ng do Vivado FFT IP (Hardware) scale bit.

    // Vi?c tr? ?i 1625 giúp k?t qu? Verilog kéo v? b?ng ?úng v?i Python nguyên b?n.

    wire signed [19:0] log_calibrated;

    assign log_calibrated = $signed({1'b0, log_sum_q10}) - 20'sd1625;



    always @(posedge clk or negedge reset_n) begin

        if (!reset_n) begin

            log_out   <= {OUT_WIDTH{1'b0}};

            valid_out <= 1'b0;

            idx_out   <= {IDX_WIDTH{1'b0}};

        end else if (enable) begin

            if (v_s2) begin

                

                // 3. B? L?C NHI?U (CLIPPER) ??NG B? V?I PYTHON

                // T??ng ???ng: np.where(log_hw < 2865, 0, log_hw)

                if (log_calibrated < 0) begin

                    log_out <= 16'd0;

                end else begin

                    log_out <= log_calibrated[15:0];

                end

                

                valid_out <= 1'b1;

                idx_out   <= idx_s2;

            end else begin

                valid_out <= 1'b0; 

            end

        end else begin

            valid_out <= 1'b0;

        end

    end



endmodule 



