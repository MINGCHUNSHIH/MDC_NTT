module poly_multiplier_top (

    input  wire clk,

    input  wire rst_n,

    input  wire start,       // External start signal

    output reg  done         // Hardware done signal

);



    // ==========================================

    // 1. FSM States

    // ==========================================

    localparam S_IDLE   = 3'd0;

    localparam S_NTT_A  = 3'd1; // Forward NTT for Poly A

    localparam S_NTT_B  = 3'd2; // Forward NTT for Poly B

    localparam S_PWM    = 3'd3; // Point-wise Multiplication

    localparam S_INTT_C = 3'd4; // Inverse NTT for Result C

    localparam S_DONE   = 3'd5;



    reg [2:0] state, next_state;



    // ==========================================

    // 2. Pipeline Counters

    // ==========================================

    reg [6:0] read_cnt;  // 0 to 127

    reg [6:0] write_cnt; // 0 to 127

    

    // Bit-Reversal wiring for write address

    wire [6:0] write_cnt_br = {write_cnt[0], write_cnt[1], write_cnt[2], write_cnt[3], write_cnt[4], write_cnt[5], write_cnt[6]};



    // ==========================================

    // 3. Physical RAM Declarations

    // ==========================================

    reg [22:0] ram_a_1 [0:127];

    reg [22:0] ram_a_2 [0:127];

    

    reg [22:0] ram_b_1 [0:127];

    reg [22:0] ram_b_2 [0:127];

    

    reg [22:0] ram_c_1 [0:127];

    reg [22:0] ram_c_2 [0:127];

    

    // RAM Read Wires

    wire [22:0] ram_a_rdata1 = ram_a_1[read_cnt];

    wire [22:0] ram_a_rdata2 = ram_a_2[read_cnt];

    wire [22:0] ram_b_rdata1 = ram_b_1[read_cnt];

    wire [22:0] ram_b_rdata2 = ram_b_2[read_cnt];

    

    wire [22:0] ram_c_rdata1 = ram_c_1[read_cnt];

    wire [22:0] ram_c_rdata2 = ram_c_2[read_cnt];



    // ==========================================

    // 4. Core Instantiations

    // ==========================================

    reg         core_en_in;

    reg  [22:0] core_x1_in, core_x2_in;



    // NTT Core

    wire ntt_en_out;

    wire [22:0] ntt_y1_out, ntt_y2_out;

    ntt_core #(.IS_INTT(0)) u_ntt (

        .clk(clk), .rst_n(rst_n),

        .en_in(core_en_in && (state == S_NTT_A || state == S_NTT_B)), 

        .x1_in(core_x1_in), .x2_in(core_x2_in),

        .en_out(ntt_en_out), .y1_out(ntt_y1_out), .y2_out(ntt_y2_out)

    );



    // PWM Core

    wire pwm_en_out;

    wire [22:0] pwm_y1_out, pwm_y2_out;

    pwm_core u_pwm (

        .clk(clk), .rst_n(rst_n),

        .en_in(core_en_in && state == S_PWM),

        .polyA_y1(ram_a_rdata1), .polyA_y2(ram_a_rdata2),

        .polyB_y1(ram_b_rdata1), .polyB_y2(ram_b_rdata2),

        .en_out(pwm_en_out), .y1_out(pwm_y1_out), .y2_out(pwm_y2_out)

    );



    // INTT Core

    wire intt_en_out;

    wire [22:0] intt_y1_out, intt_y2_out;

    intt_core u_intt (

        .clk(clk), .rst_n(rst_n),

        .en_in(core_en_in && state == S_INTT_C),

        .x1_in(core_x1_in), .x2_in(core_x2_in),

        .en_out(intt_en_out), .y1_out(intt_y1_out), .y2_out(intt_y2_out)

    );



    // ==========================================

    // 5. Memory Routing & Write Logic

    // ==========================================

    wire [6:0] target_write_addr = (state == S_PWM) ? write_cnt : write_cnt_br;



    // MUX for Core Inputs

    always @* begin

        core_x1_in = 23'd0;

        core_x2_in = 23'd0;

        

        case (state)

            S_NTT_A: begin

                core_x1_in = ram_a_rdata1;

                core_x2_in = ram_a_rdata2;

            end

            S_NTT_B: begin

                core_x1_in = ram_b_rdata1;

                core_x2_in = ram_b_rdata2;

            end

            S_INTT_C: begin

                core_x1_in = ram_c_rdata1;

                core_x2_in = ram_c_rdata2;

            end

            default: begin

                core_x1_in = 23'd0;

                core_x2_in = 23'd0;

            end

        endcase

    end



    // RAM Write Logic (Synchronous)

    always @(posedge clk) begin

        if (ntt_en_out || pwm_en_out || intt_en_out) begin

            case (state)

                S_NTT_A: begin

                    ram_a_1[target_write_addr] <= ntt_y1_out;

                    ram_a_2[target_write_addr] <= ntt_y2_out;

                end

                S_NTT_B: begin

                    ram_b_1[target_write_addr] <= ntt_y1_out;

                    ram_b_2[target_write_addr] <= ntt_y2_out;

                end

                S_PWM: begin

                    ram_c_1[target_write_addr] <= pwm_y1_out;

                    ram_c_2[target_write_addr] <= pwm_y2_out;

                end

                S_INTT_C: begin

                    ram_c_1[target_write_addr] <= intt_y1_out;

                    ram_c_2[target_write_addr] <= intt_y2_out;

                end

            endcase

        end

    end



    // ==========================================

    // 6. FSM Sequential Logic

    // ==========================================

    always @* begin

        next_state = state;

        case (state)

            S_IDLE:   if (start) next_state = S_NTT_A;

            S_NTT_A:  if (write_cnt == 127 && ntt_en_out) next_state = S_NTT_B;

            S_NTT_B:  if (write_cnt == 127 && ntt_en_out) next_state = S_PWM;

            S_PWM:    if (write_cnt == 127 && pwm_en_out) next_state = S_INTT_C;

            S_INTT_C: if (write_cnt == 127 && intt_en_out) next_state = S_DONE;

            S_DONE:   next_state = S_IDLE;

        endcase

    end



    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= S_IDLE;

            read_cnt <= 0;

            write_cnt <= 0;

            core_en_in <= 0;

            done <= 0;

        end else begin

            state <= next_state;

            

            if (state != next_state) begin

                read_cnt <= 0;

                write_cnt <= 0;

                core_en_in <= 1; 

                if (next_state == S_DONE) done <= 1;

                else done <= 0;

            end else begin

                if (core_en_in) begin

                    if (read_cnt == 127) core_en_in <= 0;

                    else read_cnt <= read_cnt + 1;

                end

                

                if (ntt_en_out || pwm_en_out || intt_en_out) begin

                    write_cnt <= write_cnt + 1;

                end

            end

        end

    end



endmodule