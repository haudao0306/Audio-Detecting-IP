// ============================================================
// mac_unit.v
// FIXED VERSION
// - No stale acc_mem read
// - FIFO stores final accumulated value
// - DONE captures acc_next instead of old acc_mem
// ============================================================

module mac_unit #(
    parameter NUM_FILTERS = 40,
    parameter NUM_BINS    = 512,
    parameter PK_WIDTH    = 33,
    parameter WMK_WIDTH   = 16,
    parameter PROD_WIDTH  = 49,
    parameter ACC_WIDTH   = 58
)(
    input  wire                                 clk,
    input  wire                                 reset_n,
    input  wire                                 enable,

    input  wire                                 valid_in,
    input  wire [PK_WIDTH-1:0]                  mel_in,
    input  wire [$clog2(NUM_BINS)-1:0]          bin_idx,

    output reg                                  valid_out,
    output reg  [ACC_WIDTH-1:0]                 mel_out,
    output reg  [$clog2(NUM_FILTERS)-1:0]       mel_idx
);

    localparam FILT_W       = $clog2(NUM_FILTERS);
    localparam FIFO_DEPTH   = NUM_FILTERS;
    localparam FIFO_W       = $clog2(FIFO_DEPTH);
    localparam FIFO_CNT_W   = $clog2(FIFO_DEPTH + 1);
    localparam FIFO_ENTRY_W = ACC_WIDTH + FILT_W;

    // ========================================================
    // ROM
    // ========================================================
    reg [47:0] mel_rom [0:NUM_BINS-1];

    initial begin
        $readmemh("mel_rom_48bit_with_flags.mem", mel_rom);
    end

    // ========================================================
    // STAGE 0
    // ========================================================
    reg [47:0]         rom_data;
    reg [PK_WIDTH-1:0] s0_mel_in;
    reg                s0_valid;
    reg                s0_sof;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rom_data  <= 48'd0;
            s0_mel_in <= 0;
            s0_valid  <= 1'b0;
            s0_sof    <= 1'b0;
        end
        else if (enable) begin
            rom_data  <= mel_rom[bin_idx];
            s0_mel_in <= mel_in;
            s0_valid  <= valid_in;
            s0_sof    <= (bin_idx == 0) && valid_in;
        end
    end

    wire [15:0] rom_w0      = rom_data[15:0];
    wire [15:0] rom_w1      = rom_data[31:16];
    wire [5:0]  rom_f0      = rom_data[37:32];
    wire [5:0]  rom_f1      = rom_data[43:38];
    wire        rom_done_f0 = rom_data[44];
    wire        rom_done_f1 = rom_data[45];

    // ========================================================
    // STAGE 1 : MULTIPLY
    // ========================================================
    reg                  s1_valid;
    reg [FILT_W-1:0]     s1_f0, s1_f1;
    reg                  s1_done_f0, s1_done_f1;
    reg [PROD_WIDTH-1:0] s1_prod0, s1_prod1;
    reg                  s1_sof;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            s1_valid   <= 1'b0;
            s1_f0      <= 0;
            s1_f1      <= 0;
            s1_done_f0 <= 1'b0;
            s1_done_f1 <= 1'b0;
            s1_prod0   <= 0;
            s1_prod1   <= 0;
            s1_sof     <= 1'b0;
        end
        else if (enable) begin

            s1_valid <= s0_valid;

            if (s0_valid) begin
                s1_f0      <= rom_f0[FILT_W-1:0];
                s1_f1      <= rom_f1[FILT_W-1:0];

                s1_done_f0 <= rom_done_f0;
                s1_done_f1 <= rom_done_f1;

                s1_prod0   <= s0_mel_in * rom_w0;
                s1_prod1   <= s0_mel_in * rom_w1;

                s1_sof     <= s0_sof;
            end
        end
    end

    // ========================================================
    // STAGE 2 : ACCUMULATE
    // ========================================================
    reg                  s2_valid;
    reg [FILT_W-1:0]     s2_f0, s2_f1;
    reg                  s2_done_f0, s2_done_f1;
    reg [PROD_WIDTH-1:0] s2_prod0, s2_prod1;
    reg                  s2_sof;

    reg [ACC_WIDTH-1:0] acc_mem   [0:NUM_FILTERS-1];
    reg                 acc_phase [0:NUM_FILTERS-1];

    reg                 s2_phase;

    integer i;

    // --------------------------------------------------------
    // FORWARDING REGISTERS - gi?i quy?t RAW hazard
    // Khi cycle N ghi acc_mem[idx], cycle N+1 ??c cùng idx
    // s? nh?n forwarded value thay vì ??c acc_mem ch?a update
    // --------------------------------------------------------
    reg [ACC_WIDTH-1:0] fwd_data0;   // forwarded value c?a f0
    reg [ACC_WIDTH-1:0] fwd_data1;   // forwarded value c?a f1
    reg [FILT_W-1:0]    fwd_idx0;    // filter index ???c ghi cycle tr??c (f0)
    reg [FILT_W-1:0]    fwd_idx1;    // filter index ???c ghi cycle tr??c (f1)
    reg                 fwd_valid0;  // cycle tr??c có ghi f0?
    reg                 fwd_valid1;  // cycle tr??c có ghi f1?

    // --------------------------------------------------------
    // FORWARDING MUX
    // ?u tiên: fwd_f0 > fwd_f1 > acc_mem (f0 ghi sau f1 n?u cùng idx)
    // --------------------------------------------------------
    wire [ACC_WIDTH-1:0] acc_mem_f0_safe =
        (fwd_valid0 && fwd_idx0 == s2_f0) ? fwd_data0 :
        (fwd_valid1 && fwd_idx1 == s2_f0) ? fwd_data1 :
        acc_mem[s2_f0];

    wire [ACC_WIDTH-1:0] acc_mem_f1_safe =
        (fwd_valid0 && fwd_idx0 == s2_f1) ? fwd_data0 :
        (fwd_valid1 && fwd_idx1 == s2_f1) ? fwd_data1 :
        acc_mem[s2_f1];

    // --------------------------------------------------------
    // PROD EXTENSIONS
    // --------------------------------------------------------
    wire [ACC_WIDTH-1:0] s2_prod0_ext =
        {{(ACC_WIDTH-PROD_WIDTH){1'b0}}, s2_prod0};

    wire [ACC_WIDTH-1:0] s2_prod1_ext =
        {{(ACC_WIDTH-PROD_WIDTH){1'b0}}, s2_prod1};

    wire active_phase =
        (s2_valid && s2_sof) ? ~s2_phase : s2_phase;

    // --------------------------------------------------------
    // FINAL ADD VALUES
    // --------------------------------------------------------
    wire [ACC_WIDTH-1:0] f0_add =
        s2_prod0_ext +
        ((s2_prod1 != 0 && s2_f1 == s2_f0) ? s2_prod1_ext : 0);

    wire [ACC_WIDTH-1:0] f1_add =
        s2_prod1_ext;

    // --------------------------------------------------------
    // ACC NEXT - dùng safe version có forwarding
    // --------------------------------------------------------
    wire [ACC_WIDTH-1:0] acc_f0_next =
        (acc_phase[s2_f0] != active_phase)
            ? f0_add
            : (acc_mem_f0_safe + f0_add);   // ? forwarded

    wire [ACC_WIDTH-1:0] acc_f1_next =
        (acc_phase[s2_f1] != active_phase)
            ? f1_add
            : (acc_mem_f1_safe + f1_add);   // ? forwarded

    // ========================================================
    // DONE DELAY
    // ========================================================
    reg                 done_valid0_d;
    reg                 done_valid1_d;

    reg [FILT_W-1:0]    done_idx0_d;
    reg [FILT_W-1:0]    done_idx1_d;

    reg [ACC_WIDTH-1:0] done_data0_d;
    reg [ACC_WIDTH-1:0] done_data1_d;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin

            s2_valid   <= 1'b0;
            s2_f0      <= 0;
            s2_f1      <= 0;

            s2_done_f0 <= 1'b0;
            s2_done_f1 <= 1'b0;

            s2_prod0   <= 0;
            s2_prod1   <= 0;

            s2_sof     <= 1'b0;
            s2_phase   <= 1'b0;

            done_valid0_d <= 1'b0;
            done_valid1_d <= 1'b0;

            done_idx0_d  <= 0;
            done_idx1_d  <= 0;

            done_data0_d <= 0;
            done_data1_d <= 0;

            // forwarding reset
            fwd_valid0 <= 1'b0;
            fwd_valid1 <= 1'b0;
            fwd_idx0   <= 0;
            fwd_idx1   <= 0;
            fwd_data0  <= 0;
            fwd_data1  <= 0;

            for (i = 0; i < NUM_FILTERS; i = i + 1) begin
                acc_mem[i]   <= 0;
                acc_phase[i] <= 1'b0;
            end
        end
        else if (enable) begin

            // ------------------------------------------------
            // PIPELINE SHIFT
            // ------------------------------------------------
            s2_valid   <= s1_valid;

            s2_f0      <= s1_f0;
            s2_f1      <= s1_f1;

            s2_done_f0 <= s1_done_f0;
            s2_done_f1 <= s1_done_f1;

            s2_prod0   <= s1_prod0;
            s2_prod1   <= s1_prod1;

            s2_sof     <= s1_sof;

            if (s2_valid && s2_sof)
                s2_phase <= ~s2_phase;

            // ------------------------------------------------
            // FORWARDING UPDATE
            // Ghi l?i nh?ng gì v?a ???c write vào acc_mem
            // cycle này ?? cycle sau có th? forward n?u c?n
            // ------------------------------------------------
            fwd_valid0 <= 1'b0;
            fwd_valid1 <= 1'b0;

            if (s2_valid) begin

                // f0 luôn ???c ghi
                fwd_valid0 <= 1'b1;
                fwd_idx0   <= s2_f0;
                fwd_data0  <= acc_f0_next;

                // f1 ch? ???c ghi khi prod1!=0 và f1!=f0
                if ((s2_prod1 != 0) && (s2_f1 != s2_f0)) begin
                    fwd_valid1 <= 1'b1;
                    fwd_idx1   <= s2_f1;
                    fwd_data1  <= acc_f1_next;
                end
            end

            // ------------------------------------------------
            // ACC UPDATE - không thay ??i so v?i b?n g?c
            // ------------------------------------------------
            if (s2_valid) begin

                acc_mem[s2_f0]   <= acc_f0_next;
                acc_phase[s2_f0] <= active_phase;

                if ((s2_prod1 != 0) && (s2_f1 != s2_f0)) begin
                    acc_mem[s2_f1]   <= acc_f1_next;
                    acc_phase[s2_f1] <= active_phase;
                end
            end

            // ------------------------------------------------
            // DONE CAPTURE
            // acc_f0_next và acc_f1_next ?ã dùng forwarded value
            // nên done_data capture t? ??ng ?úng
            // ------------------------------------------------
            done_valid0_d <= s2_valid && s2_done_f0;
            done_valid1_d <= s2_valid && s2_done_f1;

            done_idx0_d <= s2_f0;
            done_idx1_d <= s2_f1;

            if (s2_valid && s2_done_f0)
                done_data0_d <= acc_f0_next;

            if (s2_valid && s2_done_f1)
                done_data1_d <= acc_f1_next;

        end
    end

    // ========================================================
    // FIFO
    // ========================================================
    reg [FIFO_ENTRY_W-1:0] fifo_mem [0:FIFO_DEPTH-1];

    reg [FIFO_W-1:0]     wr_ptr, rd_ptr;
    reg [FIFO_CNT_W-1:0] fifo_count;

    reg [1:0]              push_cnt;
    reg [FIFO_ENTRY_W-1:0] push_entry0, push_entry1;

    always @(*) begin

        push_cnt    = 0;
        push_entry0 = 0;
        push_entry1 = 0;

        if (done_valid0_d && done_valid1_d) begin

            if (done_idx0_d == done_idx1_d) begin
                push_cnt    = 1;
                push_entry0 = {done_idx0_d, done_data0_d};
            end
            else begin
                push_cnt    = 2;
                push_entry0 = {done_idx0_d, done_data0_d};
                push_entry1 = {done_idx1_d, done_data1_d};
            end
        end
        else if (done_valid0_d) begin
            push_cnt    = 1;
            push_entry0 = {done_idx0_d, done_data0_d};
        end
        else if (done_valid1_d) begin
            push_cnt    = 1;
            push_entry0 = {done_idx1_d, done_data1_d};
        end
    end

    wire fifo_empty = (fifo_count == 0);
    wire pop_en     = !fifo_empty;

    wire [FIFO_W-1:0] wp_next1 =
        (wr_ptr == FIFO_DEPTH-1) ? 0 : (wr_ptr + 1'b1);

    wire [FIFO_W-1:0] wp_next2 =
        (wp_next1 == FIFO_DEPTH-1) ? 0 : (wp_next1 + 1'b1);

    wire [FIFO_W-1:0] rp_next =
        (rd_ptr == FIFO_DEPTH-1) ? 0 : (rd_ptr + 1'b1);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr     <= 0;
            rd_ptr     <= 0;
            fifo_count <= 0;
        end
        else if (enable) begin

            case (push_cnt)

                2'd1: begin
                    fifo_mem[wr_ptr] <= push_entry0;
                    wr_ptr <= wp_next1;
                end

                2'd2: begin
                    fifo_mem[wr_ptr]   <= push_entry0;
                    fifo_mem[wp_next1] <= push_entry1;
                    wr_ptr <= wp_next2;
                end
            endcase

            if (pop_en)
                rd_ptr <= rp_next;

            fifo_count <= fifo_count + push_cnt - (pop_en ? 1 : 0);
        end
    end

    // ========================================================
    // OUTPUT STREAM
    // ========================================================
    reg [FIFO_ENTRY_W-1:0] pop_entry_d;
    reg                    pop_valid_d;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin

            pop_entry_d <= 0;
            pop_valid_d <= 1'b0;

            mel_out   <= 0;
            mel_idx   <= 0;
            valid_out <= 1'b0;
        end
        else if (enable) begin

            pop_valid_d <= pop_en;

            if (pop_en)
                pop_entry_d <= fifo_mem[rd_ptr];

            valid_out <= pop_valid_d;

            if (pop_valid_d) begin
                mel_idx <= pop_entry_d[FIFO_ENTRY_W-1 : ACC_WIDTH];
                mel_out <= pop_entry_d[ACC_WIDTH-1:0];
            end
        end
    end

endmodule