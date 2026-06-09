`timescale 1ns / 1ps

module tb_poly_multiplier_top();

    reg  clk, rst_n, start;
    wire done;

    poly_multiplier_top u_top (
        .clk(clk), .rst_n(rst_n), .start(start), .done(done)
    );

    always #5 clk = ~clk;

    // --- 宣告所有中間階段的 Golden Array ---
    reg [22:0] gd_ntt_a1 [0:127]; reg [22:0] gd_ntt_a2 [0:127];
    reg [22:0] gd_ntt_b1 [0:127]; reg [22:0] gd_ntt_b2 [0:127];
    reg [22:0] gd_pwm_c1 [0:127]; reg [22:0] gd_pwm_c2 [0:127];
    reg [22:0] gd_fin_c1 [0:127]; reg [22:0] gd_fin_c2 [0:127];
    
    integer i, err_cnt;

    initial begin
        clk = 0; rst_n = 0; start = 0; err_cnt = 0;

        // 讀取 Input (使用相對路徑)
        $readmemh("poly_a1.mem", u_top.ram_a_1); 
        $readmemh("poly_a2.mem", u_top.ram_a_2); 
        $readmemh("poly_b1.mem", u_top.ram_b_1); 
        $readmemh("poly_b2.mem", u_top.ram_b_2);

        // 讀取 Intermediate Golden (使用相對路徑)
        $readmemh("ntt_a1_golden.mem", gd_ntt_a1); 
        $readmemh("ntt_a2_golden.mem", gd_ntt_a2);
        $readmemh("ntt_b1_golden.mem", gd_ntt_b1); 
        $readmemh("ntt_b2_golden.mem", gd_ntt_b2);
        $readmemh("pwm_c1_golden.mem", gd_pwm_c1); 
        $readmemh("pwm_c2_golden.mem", gd_pwm_c2);
        $readmemh("poly_c1_golden.mem", gd_fin_c1); 
        $readmemh("poly_c2_golden.mem", gd_fin_c2);

        #20 rst_n = 1; #20;
        start = 1; #10 start = 0; 

        // ==========================================
        // 🏁 檢查點 1：NTT_A 完成時
        // ==========================================
        wait(u_top.state == 3'd2); 
        @(posedge clk);
        $display("\n--- [Check Point 1: NTT_A] ---");
        err_cnt = 0;
        for (i=0; i<128; i=i+1) begin
            if (u_top.ram_a_1[i] !== gd_ntt_a1[i]) begin err_cnt=err_cnt+1; $display("Err_A1[%0d]: HW=%06x, GD=%06x", i, u_top.ram_a_1[i], gd_ntt_a1[i]); end
            if (u_top.ram_a_2[i] !== gd_ntt_a2[i]) begin err_cnt=err_cnt+1; $display("Err_A2[%0d]: HW=%06x, GD=%06x", i, u_top.ram_a_2[i], gd_ntt_a2[i]); end
        end
        if(err_cnt == 0) $display(">> NTT_A PASS"); else $display(">> NTT_A FAILED (%0d errors)", err_cnt);

        // ==========================================
        // 🏁 檢查點 2：NTT_B 完成時
        // ==========================================
        wait(u_top.state == 3'd3); 
        @(posedge clk);
        $display("\n--- [Check Point 2: NTT_B] ---");
        err_cnt = 0;
        for (i=0; i<128; i=i+1) begin
            if (u_top.ram_b_1[i] !== gd_ntt_b1[i]) begin err_cnt=err_cnt+1; $display("Err_B1[%0d]: HW=%06x, GD=%06x", i, u_top.ram_b_1[i], gd_ntt_b1[i]); end
            if (u_top.ram_b_2[i] !== gd_ntt_b2[i]) begin err_cnt=err_cnt+1; $display("Err_B2[%0d]: HW=%06x, GD=%06x", i, u_top.ram_b_2[i], gd_ntt_b2[i]); end
        end
        if(err_cnt == 0) $display(">> NTT_B PASS"); else $display(">> NTT_B FAILED (%0d errors)", err_cnt);

        // ==========================================
        // 🏁 檢查點 3：PWM 完成時
        // ==========================================
        wait(u_top.state == 3'd4); 
        @(posedge clk);
        $display("\n--- [Check Point 3: PWM] ---");
        err_cnt = 0;
        for (i=0; i<128; i=i+1) begin
            if (u_top.ram_c_1[i] !== gd_pwm_c1[i]) begin err_cnt=err_cnt+1; $display("Err_PWM_C1[%0d]: HW=%06x, GD=%06x", i, u_top.ram_c_1[i], gd_pwm_c1[i]); end
            if (u_top.ram_c_2[i] !== gd_pwm_c2[i]) begin err_cnt=err_cnt+1; $display("Err_PWM_C2[%0d]: HW=%06x, GD=%06x", i, u_top.ram_c_2[i], gd_pwm_c2[i]); end
        end
        if(err_cnt == 0) $display(">> PWM PASS"); else $display(">> PWM FAILED (%0d errors)", err_cnt);

        // ==========================================
        // 🏁 檢查點 4：INTT_C 完成時
        // ==========================================
        wait(done == 1); 
        @(posedge clk);
        $display("\n--- [Check Point 4: INTT_C Final] ---");
        err_cnt = 0;
        for (i=0; i<128; i=i+1) begin
            if (u_top.ram_c_1[i] !== gd_fin_c1[i]) begin err_cnt=err_cnt+1; $display("Err_FIN_C1[%0d]: HW=%06x, GD=%06x", i, u_top.ram_c_1[i], gd_fin_c1[i]); end
            if (u_top.ram_c_2[i] !== gd_fin_c2[i]) begin err_cnt=err_cnt+1; $display("Err_FIN_C2[%0d]: HW=%06x, GD=%06x", i, u_top.ram_c_2[i], gd_fin_c2[i]); end
        end
        if(err_cnt == 0) $display(">> INTT_C PASS! 全線通關！"); else $display(">> INTT_C FAILED (%0d errors)", err_cnt);

        $finish; 
    end
endmodule
