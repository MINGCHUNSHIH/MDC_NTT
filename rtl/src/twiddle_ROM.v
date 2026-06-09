// =============================================================================
// 模組名稱: twiddle_rom
// 檔案名稱: twiddle_ROM.v
// 功能描述:
//   旋轉因子查表 ROM (Twiddle Factors Lookup ROM)。
//   在 NTT/INTT 流水線的每一級 Stage 中，根據當前蝶形運算時的串流位址 (addr_cnt)，
//   提供正確的模數旋轉因子 (Psi/Psi_inv 的冪次，模數 Q = 8380417)。
//   STAGE 參數指定對應流水線 Stage 1-8，支援正向與逆向的旋轉因子切換。
// =============================================================================
module twiddle_rom #(parameter STAGE = 1)(
    input clk, input rst_n, input en, input is_intt, output reg [22:0] twiddle
);
    reg [6:0] addr_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) addr_cnt <= 0;
        else if (en) addr_cnt <= addr_cnt + 1;
    end
    always @* begin
        twiddle = 23'd0;
        case (STAGE)
            1: begin
                case (addr_cnt >> 7)
                    7'd0: twiddle = is_intt ? 23'd3572223 : 23'd4808194;
                    default: twiddle = 23'd0;
                endcase
            end
            2: begin
                case (addr_cnt >> 6)
                    7'd0: twiddle = is_intt ? 23'd4618904 : 23'd3765607;
                    7'd1: twiddle = is_intt ? 23'd4614810 : 23'd3761513;
                    default: twiddle = 23'd0;
                endcase
            end
            3: begin
                case (addr_cnt >> 5)
                    7'd0: twiddle = is_intt ? 23'd3201430 : 23'd5178923;
                    7'd1: twiddle = is_intt ? 23'd3145678 : 23'd5496691;
                    7'd2: twiddle = is_intt ? 23'd2883726 : 23'd5234739;
                    7'd3: twiddle = is_intt ? 23'd3201494 : 23'd5178987;
                    default: twiddle = 23'd0;
                endcase
            end
            4: begin
                case (addr_cnt >> 4)
                    7'd0: twiddle = is_intt ? 23'd1221177 : 23'd7778734;
                    7'd1: twiddle = is_intt ? 23'd7822959 : 23'd3542485;
                    7'd2: twiddle = is_intt ? 23'd1005239 : 23'd2682288;
                    7'd3: twiddle = is_intt ? 23'd4615550 : 23'd2129892;
                    7'd4: twiddle = is_intt ? 23'd6250525 : 23'd3764867;
                    7'd5: twiddle = is_intt ? 23'd5698129 : 23'd7375178;
                    7'd6: twiddle = is_intt ? 23'd4837932 : 23'd557458;
                    7'd7: twiddle = is_intt ? 23'd601683 : 23'd7159240;
                    default: twiddle = 23'd0;
                endcase
            end
            5: begin
                case (addr_cnt >> 3)
                    7'd0: twiddle = is_intt ? 23'd6096684 : 23'd5010068;
                    7'd1: twiddle = is_intt ? 23'd5564778 : 23'd4317364;
                    7'd2: twiddle = is_intt ? 23'd3585098 : 23'd2663378;
                    7'd3: twiddle = is_intt ? 23'd642628 : 23'd6705802;
                    7'd4: twiddle = is_intt ? 23'd6919699 : 23'd4855975;
                    7'd5: twiddle = is_intt ? 23'd5926434 : 23'd7946292;
                    7'd6: twiddle = is_intt ? 23'd6666122 : 23'd676590;
                    7'd7: twiddle = is_intt ? 23'd3227876 : 23'd7044481;
                    7'd8: twiddle = is_intt ? 23'd1335936 : 23'd5152541;
                    7'd9: twiddle = is_intt ? 23'd7703827 : 23'd1714295;
                    7'd10: twiddle = is_intt ? 23'd434125 : 23'd2453983;
                    7'd11: twiddle = is_intt ? 23'd3524442 : 23'd1460718;
                    7'd12: twiddle = is_intt ? 23'd1674615 : 23'd7737789;
                    7'd13: twiddle = is_intt ? 23'd5717039 : 23'd4795319;
                    7'd14: twiddle = is_intt ? 23'd4063053 : 23'd2815639;
                    7'd15: twiddle = is_intt ? 23'd3370349 : 23'd2283733;
                    default: twiddle = 23'd0;
                endcase
            end
            6: begin
                case (addr_cnt >> 2)
                    7'd0: twiddle = is_intt ? 23'd6522001 : 23'd3602218;
                    7'd1: twiddle = is_intt ? 23'd5034454 : 23'd3182878;
                    7'd2: twiddle = is_intt ? 23'd6526611 : 23'd2740543;
                    7'd3: twiddle = is_intt ? 23'd5463079 : 23'd4793971;
                    7'd4: twiddle = is_intt ? 23'd4510100 : 23'd5269599;
                    7'd5: twiddle = is_intt ? 23'd7823561 : 23'd2101410;
                    7'd6: twiddle = is_intt ? 23'd5188063 : 23'd3704823;
                    7'd7: twiddle = is_intt ? 23'd2897314 : 23'd1159875;
                    7'd8: twiddle = is_intt ? 23'd3950053 : 23'd394148;
                    7'd9: twiddle = is_intt ? 23'd1716988 : 23'd928749;
                    7'd10: twiddle = is_intt ? 23'd1935799 : 23'd1095468;
                    7'd11: twiddle = is_intt ? 23'd4623627 : 23'd4874037;
                    7'd12: twiddle = is_intt ? 23'd3574466 : 23'd2071829;
                    7'd13: twiddle = is_intt ? 23'd817536 : 23'd4361428;
                    7'd14: twiddle = is_intt ? 23'd6621070 : 23'd3241972;
                    7'd15: twiddle = is_intt ? 23'd4965348 : 23'd2156050;
                    7'd16: twiddle = is_intt ? 23'd6224367 : 23'd3415069;
                    7'd17: twiddle = is_intt ? 23'd5138445 : 23'd1759347;
                    7'd18: twiddle = is_intt ? 23'd4018989 : 23'd7562881;
                    7'd19: twiddle = is_intt ? 23'd6308588 : 23'd4805951;
                    7'd20: twiddle = is_intt ? 23'd3506380 : 23'd3756790;
                    7'd21: twiddle = is_intt ? 23'd7284949 : 23'd6444618;
                    7'd22: twiddle = is_intt ? 23'd7451668 : 23'd6663429;
                    7'd23: twiddle = is_intt ? 23'd7986269 : 23'd4430364;
                    7'd24: twiddle = is_intt ? 23'd7220542 : 23'd5483103;
                    7'd25: twiddle = is_intt ? 23'd4675594 : 23'd3192354;
                    7'd26: twiddle = is_intt ? 23'd6279007 : 23'd556856;
                    7'd27: twiddle = is_intt ? 23'd3110818 : 23'd3870317;
                    7'd28: twiddle = is_intt ? 23'd3586446 : 23'd2917338;
                    7'd29: twiddle = is_intt ? 23'd5639874 : 23'd1853806;
                    7'd30: twiddle = is_intt ? 23'd5197539 : 23'd3345963;
                    7'd31: twiddle = is_intt ? 23'd4778199 : 23'd1858416;
                    default: twiddle = 23'd0;
                endcase
            end
            7: begin
                case (addr_cnt >> 1)
                    7'd0: twiddle = is_intt ? 23'd6635910 : 23'd3073009;
                    7'd1: twiddle = is_intt ? 23'd2236726 : 23'd1277625;
                    7'd2: twiddle = is_intt ? 23'd1922253 : 23'd5744944;
                    7'd3: twiddle = is_intt ? 23'd3818627 : 23'd3852015;
                    7'd4: twiddle = is_intt ? 23'd2354215 : 23'd4183372;
                    7'd5: twiddle = is_intt ? 23'd7369194 : 23'd5157610;
                    7'd6: twiddle = is_intt ? 23'd327848 : 23'd5258977;
                    7'd7: twiddle = is_intt ? 23'd8031605 : 23'd8106357;
                    7'd8: twiddle = is_intt ? 23'd459163 : 23'd2508980;
                    7'd9: twiddle = is_intt ? 23'd653275 : 23'd2028118;
                    7'd10: twiddle = is_intt ? 23'd6067579 : 23'd1937570;
                    7'd11: twiddle = is_intt ? 23'd3467665 : 23'd4564692;
                    7'd12: twiddle = is_intt ? 23'd2778788 : 23'd2811291;
                    7'd13: twiddle = is_intt ? 23'd5697147 : 23'd5396636;
                    7'd14: twiddle = is_intt ? 23'd2775755 : 23'd7270901;
                    7'd15: twiddle = is_intt ? 23'd7023969 : 23'd4158088;
                    7'd16: twiddle = is_intt ? 23'd5006167 : 23'd1528066;
                    7'd17: twiddle = is_intt ? 23'd5454601 : 23'd482649;
                    7'd18: twiddle = is_intt ? 23'd1226661 : 23'd1148858;
                    7'd19: twiddle = is_intt ? 23'd4478945 : 23'd5418153;
                    7'd20: twiddle = is_intt ? 23'd7759253 : 23'd7814814;
                    7'd21: twiddle = is_intt ? 23'd5344437 : 23'd169688;
                    7'd22: twiddle = is_intt ? 23'd5919030 : 23'd2462444;
                    7'd23: twiddle = is_intt ? 23'd1317678 : 23'd5046034;
                    7'd24: twiddle = is_intt ? 23'd2362063 : 23'd4213992;
                    7'd25: twiddle = is_intt ? 23'd1300016 : 23'd4892034;
                    7'd26: twiddle = is_intt ? 23'd4182915 : 23'd1987814;
                    7'd27: twiddle = is_intt ? 23'd4898211 : 23'd5183169;
                    7'd28: twiddle = is_intt ? 23'd2254727 : 23'd1736313;
                    7'd29: twiddle = is_intt ? 23'd2391089 : 23'd235407;
                    7'd30: twiddle = is_intt ? 23'd6592474 : 23'd5130263;
                    7'd31: twiddle = is_intt ? 23'd2579253 : 23'd3258457;
                    7'd32: twiddle = is_intt ? 23'd5121960 : 23'd5801164;
                    7'd33: twiddle = is_intt ? 23'd3250154 : 23'd1787943;
                    7'd34: twiddle = is_intt ? 23'd8145010 : 23'd5989328;
                    7'd35: twiddle = is_intt ? 23'd6644104 : 23'd6125690;
                    7'd36: twiddle = is_intt ? 23'd3197248 : 23'd3482206;
                    7'd37: twiddle = is_intt ? 23'd6392603 : 23'd4197502;
                    7'd38: twiddle = is_intt ? 23'd3488383 : 23'd7080401;
                    7'd39: twiddle = is_intt ? 23'd4166425 : 23'd6018354;
                    7'd40: twiddle = is_intt ? 23'd3334383 : 23'd7062739;
                    7'd41: twiddle = is_intt ? 23'd5917973 : 23'd2461387;
                    7'd42: twiddle = is_intt ? 23'd8210729 : 23'd3035980;
                    7'd43: twiddle = is_intt ? 23'd565603 : 23'd621164;
                    7'd44: twiddle = is_intt ? 23'd2962264 : 23'd3901472;
                    7'd45: twiddle = is_intt ? 23'd7231559 : 23'd7153756;
                    7'd46: twiddle = is_intt ? 23'd7897768 : 23'd2925816;
                    7'd47: twiddle = is_intt ? 23'd6852351 : 23'd3374250;
                    7'd48: twiddle = is_intt ? 23'd4222329 : 23'd1356448;
                    7'd49: twiddle = is_intt ? 23'd1109516 : 23'd5604662;
                    7'd50: twiddle = is_intt ? 23'd2983781 : 23'd2683270;
                    7'd51: twiddle = is_intt ? 23'd5569126 : 23'd5601629;
                    7'd52: twiddle = is_intt ? 23'd3815725 : 23'd4912752;
                    7'd53: twiddle = is_intt ? 23'd6442847 : 23'd2312838;
                    7'd54: twiddle = is_intt ? 23'd6352299 : 23'd7727142;
                    7'd55: twiddle = is_intt ? 23'd5871437 : 23'd7921254;
                    7'd56: twiddle = is_intt ? 23'd274060 : 23'd348812;
                    7'd57: twiddle = is_intt ? 23'd3121440 : 23'd8052569;
                    7'd58: twiddle = is_intt ? 23'd3222807 : 23'd1011223;
                    7'd59: twiddle = is_intt ? 23'd4197045 : 23'd6026202;
                    7'd60: twiddle = is_intt ? 23'd4528402 : 23'd4561790;
                    7'd61: twiddle = is_intt ? 23'd2635473 : 23'd6458164;
                    7'd62: twiddle = is_intt ? 23'd7102792 : 23'd6143691;
                    7'd63: twiddle = is_intt ? 23'd5307408 : 23'd1744507;
                    default: twiddle = 23'd0;
                endcase
            end
            8: begin
                case (addr_cnt >> 0)
                    7'd0: twiddle = is_intt ? 23'd731434 : 23'd1753;
                    7'd1: twiddle = is_intt ? 23'd7325939 : 23'd6444997;
                    7'd2: twiddle = is_intt ? 23'd781875 : 23'd5720892;
                    7'd3: twiddle = is_intt ? 23'd6480365 : 23'd6924527;
                    7'd4: twiddle = is_intt ? 23'd3773731 : 23'd2660408;
                    7'd5: twiddle = is_intt ? 23'd3974485 : 23'd6600190;
                    7'd6: twiddle = is_intt ? 23'd4849188 : 23'd8321269;
                    7'd7: twiddle = is_intt ? 23'd303005 : 23'd2772600;
                    7'd8: twiddle = is_intt ? 23'd392707 : 23'd1182243;
                    7'd9: twiddle = is_intt ? 23'd5454363 : 23'd87208;
                    7'd10: twiddle = is_intt ? 23'd1716814 : 23'd636927;
                    7'd11: twiddle = is_intt ? 23'd3014420 : 23'd4415111;
                    7'd12: twiddle = is_intt ? 23'd2193087 : 23'd4423672;
                    7'd13: twiddle = is_intt ? 23'd6022044 : 23'd6084020;
                    7'd14: twiddle = is_intt ? 23'd5256655 : 23'd5095502;
                    7'd15: twiddle = is_intt ? 23'd2185084 : 23'd4663471;
                    7'd16: twiddle = is_intt ? 23'd1514152 : 23'd8352605;
                    7'd17: twiddle = is_intt ? 23'd8240173 : 23'd822541;
                    7'd18: twiddle = is_intt ? 23'd4949981 : 23'd1009365;
                    7'd19: twiddle = is_intt ? 23'd7520273 : 23'd5926272;
                    7'd20: twiddle = is_intt ? 23'd553718 : 23'd6400920;
                    7'd21: twiddle = is_intt ? 23'd7872272 : 23'd1596822;
                    7'd22: twiddle = is_intt ? 23'd1103344 : 23'd4423473;
                    7'd23: twiddle = is_intt ? 23'd5274859 : 23'd4620952;
                    7'd24: twiddle = is_intt ? 23'd770441 : 23'd6695264;
                    7'd25: twiddle = is_intt ? 23'd7835041 : 23'd4969849;
                    7'd26: twiddle = is_intt ? 23'd8165537 : 23'd2678278;
                    7'd27: twiddle = is_intt ? 23'd5016875 : 23'd4611469;
                    7'd28: twiddle = is_intt ? 23'd5360024 : 23'd4829411;
                    7'd29: twiddle = is_intt ? 23'd1370517 : 23'd635956;
                    7'd30: twiddle = is_intt ? 23'd11879 : 23'd8129971;
                    7'd31: twiddle = is_intt ? 23'd4385746 : 23'd5925040;
                    7'd32: twiddle = is_intt ? 23'd3369273 : 23'd4234153;
                    7'd33: twiddle = is_intt ? 23'd7216819 : 23'd6607829;
                    7'd34: twiddle = is_intt ? 23'd6352379 : 23'd2192938;
                    7'd35: twiddle = is_intt ? 23'd6715099 : 23'd6653329;
                    7'd36: twiddle = is_intt ? 23'd6657188 : 23'd2387513;
                    7'd37: twiddle = is_intt ? 23'd1615530 : 23'd4768667;
                    7'd38: twiddle = is_intt ? 23'd5811406 : 23'd8111961;
                    7'd39: twiddle = is_intt ? 23'd4399818 : 23'd5199961;
                    7'd40: twiddle = is_intt ? 23'd4022750 : 23'd3747250;
                    7'd41: twiddle = is_intt ? 23'd7630840 : 23'd2296099;
                    7'd42: twiddle = is_intt ? 23'd4231948 : 23'd1239911;
                    7'd43: twiddle = is_intt ? 23'd2612853 : 23'd4541938;
                    7'd44: twiddle = is_intt ? 23'd5370669 : 23'd3195676;
                    7'd45: twiddle = is_intt ? 23'd5732423 : 23'd2642980;
                    7'd46: twiddle = is_intt ? 23'd338420 : 23'd1254190;
                    7'd47: twiddle = is_intt ? 23'd3033742 : 23'd8368000;
                    7'd48: twiddle = is_intt ? 23'd1834526 : 23'd2998219;
                    7'd49: twiddle = is_intt ? 23'd724804 : 23'd141835;
                    7'd50: twiddle = is_intt ? 23'd1187885 : 23'd8291116;
                    7'd51: twiddle = is_intt ? 23'd7872490 : 23'd2513018;
                    7'd52: twiddle = is_intt ? 23'd1393159 : 23'd7025525;
                    7'd53: twiddle = is_intt ? 23'd5889092 : 23'd613238;
                    7'd54: twiddle = is_intt ? 23'd6386371 : 23'd7070156;
                    7'd55: twiddle = is_intt ? 23'd1476985 : 23'd6161950;
                    7'd56: twiddle = is_intt ? 23'd2743411 : 23'd7921677;
                    7'd57: twiddle = is_intt ? 23'd7852436 : 23'd6458423;
                    7'd58: twiddle = is_intt ? 23'd1179613 : 23'd4040196;
                    7'd59: twiddle = is_intt ? 23'd7794176 : 23'd4908348;
                    7'd60: twiddle = is_intt ? 23'd2033807 : 23'd2039144;
                    7'd61: twiddle = is_intt ? 23'd2374402 : 23'd6500539;
                    7'd62: twiddle = is_intt ? 23'd6275131 : 23'd7561656;
                    7'd63: twiddle = is_intt ? 23'd1623354 : 23'd6201452;
                    7'd64: twiddle = is_intt ? 23'd2178965 : 23'd6757063;
                    7'd65: twiddle = is_intt ? 23'd818761 : 23'd2105286;
                    7'd66: twiddle = is_intt ? 23'd1879878 : 23'd6006015;
                    7'd67: twiddle = is_intt ? 23'd6341273 : 23'd6346610;
                    7'd68: twiddle = is_intt ? 23'd3472069 : 23'd586241;
                    7'd69: twiddle = is_intt ? 23'd4340221 : 23'd7200804;
                    7'd70: twiddle = is_intt ? 23'd1921994 : 23'd527981;
                    7'd71: twiddle = is_intt ? 23'd458740 : 23'd5637006;
                    7'd72: twiddle = is_intt ? 23'd2218467 : 23'd6903432;
                    7'd73: twiddle = is_intt ? 23'd1310261 : 23'd1994046;
                    7'd74: twiddle = is_intt ? 23'd7767179 : 23'd2491325;
                    7'd75: twiddle = is_intt ? 23'd1354892 : 23'd6987258;
                    7'd76: twiddle = is_intt ? 23'd5867399 : 23'd507927;
                    7'd77: twiddle = is_intt ? 23'd89301 : 23'd7192532;
                    7'd78: twiddle = is_intt ? 23'd8238582 : 23'd7655613;
                    7'd79: twiddle = is_intt ? 23'd5382198 : 23'd6545891;
                    7'd80: twiddle = is_intt ? 23'd12417 : 23'd5346675;
                    7'd81: twiddle = is_intt ? 23'd7126227 : 23'd8041997;
                    7'd82: twiddle = is_intt ? 23'd5737437 : 23'd2647994;
                    7'd83: twiddle = is_intt ? 23'd5184741 : 23'd3009748;
                    7'd84: twiddle = is_intt ? 23'd3838479 : 23'd5767564;
                    7'd85: twiddle = is_intt ? 23'd7140506 : 23'd4148469;
                    7'd86: twiddle = is_intt ? 23'd6084318 : 23'd749577;
                    7'd87: twiddle = is_intt ? 23'd4633167 : 23'd4357667;
                    7'd88: twiddle = is_intt ? 23'd3180456 : 23'd3980599;
                    7'd89: twiddle = is_intt ? 23'd268456 : 23'd2569011;
                    7'd90: twiddle = is_intt ? 23'd3611750 : 23'd6764887;
                    7'd91: twiddle = is_intt ? 23'd5992904 : 23'd1723229;
                    7'd92: twiddle = is_intt ? 23'd1727088 : 23'd1665318;
                    7'd93: twiddle = is_intt ? 23'd6187479 : 23'd2028038;
                    7'd94: twiddle = is_intt ? 23'd1772588 : 23'd1163598;
                    7'd95: twiddle = is_intt ? 23'd4146264 : 23'd5011144;
                    7'd96: twiddle = is_intt ? 23'd2455377 : 23'd3994671;
                    7'd97: twiddle = is_intt ? 23'd250446 : 23'd8368538;
                    7'd98: twiddle = is_intt ? 23'd7744461 : 23'd7009900;
                    7'd99: twiddle = is_intt ? 23'd3551006 : 23'd3020393;
                    7'd100: twiddle = is_intt ? 23'd3768948 : 23'd3363542;
                    7'd101: twiddle = is_intt ? 23'd5702139 : 23'd214880;
                    7'd102: twiddle = is_intt ? 23'd3410568 : 23'd545376;
                    7'd103: twiddle = is_intt ? 23'd1685153 : 23'd7609976;
                    7'd104: twiddle = is_intt ? 23'd3759465 : 23'd3105558;
                    7'd105: twiddle = is_intt ? 23'd3956944 : 23'd7277073;
                    7'd106: twiddle = is_intt ? 23'd6783595 : 23'd508145;
                    7'd107: twiddle = is_intt ? 23'd1979497 : 23'd7826699;
                    7'd108: twiddle = is_intt ? 23'd2454145 : 23'd860144;
                    7'd109: twiddle = is_intt ? 23'd7371052 : 23'd3430436;
                    7'd110: twiddle = is_intt ? 23'd7557876 : 23'd140244;
                    7'd111: twiddle = is_intt ? 23'd27812 : 23'd6866265;
                    7'd112: twiddle = is_intt ? 23'd3716946 : 23'd6195333;
                    7'd113: twiddle = is_intt ? 23'd3284915 : 23'd3123762;
                    7'd114: twiddle = is_intt ? 23'd2296397 : 23'd2358373;
                    7'd115: twiddle = is_intt ? 23'd3956745 : 23'd6187330;
                    7'd116: twiddle = is_intt ? 23'd3965306 : 23'd5365997;
                    7'd117: twiddle = is_intt ? 23'd7743490 : 23'd6663603;
                    7'd118: twiddle = is_intt ? 23'd8293209 : 23'd2926054;
                    7'd119: twiddle = is_intt ? 23'd7198174 : 23'd7987710;
                    7'd120: twiddle = is_intt ? 23'd5607817 : 23'd8077412;
                    7'd121: twiddle = is_intt ? 23'd59148 : 23'd3531229;
                    7'd122: twiddle = is_intt ? 23'd1780227 : 23'd4405932;
                    7'd123: twiddle = is_intt ? 23'd5720009 : 23'd4606686;
                    7'd124: twiddle = is_intt ? 23'd1455890 : 23'd1900052;
                    7'd125: twiddle = is_intt ? 23'd2659525 : 23'd7598542;
                    7'd126: twiddle = is_intt ? 23'd1935420 : 23'd1054478;
                    7'd127: twiddle = is_intt ? 23'd8378664 : 23'd7648983;
                    default: twiddle = 23'd0;
                endcase
            end
            default: twiddle = 23'd0;
        endcase
    end
endmodule
