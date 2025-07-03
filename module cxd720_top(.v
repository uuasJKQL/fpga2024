module cxd720_top(
    input clk_100m_in,
    input rst,
    input [4:1] key,
    output [8:1] led,
    output [3:0] seg_s,
    output [7:0] seg_ap,
    output ad_clk,
    input [11:0] ad_din,
    output da1_wrt,
    output da1_clk,
    output reg [13:0] da1_out,
    output da2_wrt,
    output da2_clk,
    output reg [13:0] da2_out,
    output [38:3] ext
);

    // 时钟生成
   reg[31:0] left_1;
   reg[31:0] left_2;
   reg[31:0] center;
    reg[3:0] count_am;
     reg[3:0] count_fm;
      reg[3:0] count_cw;
      reg[3:0]count_test;
    reg [59:0] half_power;
    wire clk_64m;
    wire clk_64m_locked;
    wire clk_32m;
    clk_64m clk_64_inst(
        .clk_out_64m(clk_64m),    
        .locked(clk_64m_locked),
        .clk_in1(clk_100m_in)
    );

    // 测试信号生成
    wire signed [13:0] cos1m_data, cos8m_data;
    dds_compiler_0 dds_inst_1m(
        .aclk(clk_64m),
        .s_axis_config_tvalid(1'b1),
        .s_axis_config_tdata(23'H20000),
        .m_axis_data_tdata(cos1m_data)
    );

    dds_compiler_0 dds_inst_8m(
        .aclk(clk_64m),
        .s_axis_config_tvalid(1'b1),
        .s_axis_config_tdata(23'H100000),
        .m_axis_data_tdata(cos8m_data)
    );

    wire signed [14:0] cos_add;
    assign cos_add = cos1m_data + cos8m_data;

    // ADC输入预处理
    reg signed [11:0] adc12_in_r;
    always @(posedge clk_64m) begin
        adc12_in_r <= ad_din + 12'H800;
    end

    // FFT处理 - 4096点==========================================
    wire signed [28:0] fft_real, fft_imag;
    wire [11:0] fft_index; // 12位索引，范围0-4095
    wire [59:0] fft_abs;
    assign fft_abs = fft_real*fft_real + fft_imag*fft_imag;

    // 替换为4096点FFT模块
    fft_256_top fft_U0(
        .clkin_128m( clk_64m),
        .sig_i({adc12_in_r, 4'b0000}),
        .sig_q(16'H0),
        .fft_real(fft_real),
        .fft_imag(fft_imag),
        .out_index(fft_index)
    );
    // =========================================================

    // 调制识别核心 - 适应4096点FFT==============================
    reg [1:0] mod_type = 2'b00; // 00=未知, 01=CW, 10=AM, 11=FM
    reg [11:0] frame_counter = 0; // 扩展到12位
    reg [59:0] max_value = 0;
    reg [11:0] max_index = 0; // 扩展到12位
    reg [59:0] total_energy = 0;
    reg [59:0] left_sideband = 0;
    reg [59:0] right_sideband = 0;
    reg [11:0] left_bound = 0; // 扩展到12位
    reg [11:0] right_bound = 0; // 扩展到12位
    reg [11:0] bandwidth = 0;  // 扩展到12位
    
    // 频谱缓冲区 - 增加到4096点
    reg [31:0] fft_abs_buffer [0:2047];
    
    // FFT帧处理状态机
    reg [1:0] state = 0;
    parameter IDLE = 0, COLLECT = 1, ANALYZE = 2, DECIDE = 3;
    
    always @(posedge clk_64m) begin
        if (rst) begin
            state <= IDLE;
            frame_counter <= 0;
            max_value <= 0;
            max_index <= 0;
            total_energy <= 0;
            mod_type <= 2'b00;
              count_am<=0;
          count_cw<=0;
              count_fm<=0;
        count_test<=0;
        end else begin
            case (state)
                IDLE: begin
                    if (fft_index == 0) begin
                        state <= COLLECT;
                        max_value <= 0;
                        max_index <= 0;
                        total_energy <= 0;
                        count_am<=0;
                        count_cw<=0;
                        count_fm<=0;
                        count_test<=0;
                    end
                end
                
                COLLECT: begin
                    // 存储当前频谱点
                    fft_abs_buffer[fft_index] <= fft_abs[59:28];
                    
                    // 更新总能量
                  //  total_energy <= total_energy + fft_abs;
                    
                    // 寻找最大峰值
                    if (fft_abs > max_value) begin
                        max_value <= fft_abs;
                        max_index <= fft_index;
                    end
                    
                    // 使用4095作为结束点（4096点FFT）
                    if (fft_index == 2047) begin
                        state <= DECIDE;
                        frame_counter <= 0;
                    end
                end
                
                ANALYZE: begin
                    // 获取边带值（使用缓冲区）
                    left_sideband <= (max_index > 0) ? fft_abs_buffer[max_index - 1] : 0;
                    right_sideband <= (max_index < 2047) ? fft_abs_buffer[max_index + 1] : 0;
                    
                    // 计算带宽
                    if (frame_counter == 0) begin
                        // 调整边界范围以适应4096点
                        left_bound <= (max_index > 40) ? max_index - 40 : 0;
                        right_bound <= (max_index < 2007) ? max_index + 40 : 2047;
                        frame_counter <= 1;
                    end else if (frame_counter < 40) begin // 增加搜索范围
                        // 寻找-3dB点（半功率点）
                        half_power = max_value >> 1; // max_value/2
                        
                        // 向左扩展
                        if (left_bound > 0 && fft_abs_buffer[left_bound] > half_power)
                            left_bound <= left_bound - 1;
                            
                        // 向右扩展
                        if (right_bound < 4095 && fft_abs_buffer[right_bound] > half_power)
                            right_bound <= right_bound + 1;
                            
                        frame_counter <= frame_counter + 1;
                    end else begin
                        bandwidth <= right_bound - left_bound;
                        state <= DECIDE;
                    end
                end
                
                DECIDE: begin
                    // 调制类型判决 - 调整阈值以适应4096点
                    // CW: 窄带信号 (带宽 < 20 bins ≈ 312.5kHz)
                   left_1<=fft_abs_buffer[max_index-1];
                  left_2<=fft_abs_buffer[max_index-2];
                  center<=fft_abs_buffer[max_index];
                   if(count_test<10)
                   begin
                    if ((center>>11) >left_2 ) begin
                        count_cw<=count_cw+1;
                       // mod_type <= 2'b01; // CW
                    end 
                    // AM: 存在明显边带
                    else if ((center>>8)>left_2) begin
                          count_am<=count_am+1;
                        //mod_type <= 2'b10; // AM
                    end 
                    // FM: 宽带信号 (带宽 > 200 bins ≈ 3.125MHz)
                  
                    else begin
                          count_fm<=count_fm+1;
                       // mod_type <= 2'b11; // 
                    end
                 
                   end
else
begin
    count_test<=0;
mod_type<=(count_cw>count_am)?(count_cw>count_fm?2'b01:2'b11):(count_am>count_fm?2'b10:2'b11);
                    state <= IDLE;
end
                end
            endcase
        end
    end

    // 结果显示
  assign led[2:1] = mod_type; // LED显示调制类型
    
    // 七段数码管显示调制类型
    reg [3:0] seg_data;
    always @(*) begin
        case (mod_type)
            2'b01: seg_data = 4'hC; // 显示"C" (CW)
            2'b10: seg_data = 4'hA; // 显示"A" (AM)
            2'b11: seg_data = 4'hF; // 显示"F" (FM)
            default: seg_data = 4'h0; // 显示"0" (未知)
        endcase
    end
    
    // 七段数码管显示模块
    seg7_display seg7_inst(
        .clk(clk_64m),
        .data(seg_data),
        .seg_s(seg_s),
        .seg_ap(seg_ap)
    );

    // ILA调试 - 可能需要增加位宽
    ila_0 ila_inst (
        .clk(clk_64m),
        .probe0(left_1),
        .probe1(left_2), // 取低36位显示
        .probe2(center) ,
          .probe3(count_am) ,
            .probe4(count_fm) ,
              .probe5(count_cw) ,
               .probe6(count_test) 
    );

    // DA输出
    wire signed [13:0] fir_out;
    fir_lp_0 fir_lp_0_inst(
        .aclk(clk_64m),
        .s_axis_data_tvalid(1'b1),
        .s_axis_data_tdata(adc12_in_r),
        .m_axis_data_tdata(fir_out)
    );

    always @(posedge clk_64m) begin
        da1_out <= fir_out + 14'H2000;
        da2_out <= cos_add[14:1] + 14'H2000;
    end

    assign da1_clk = clk_64m;
    assign da1_wrt = clk_64m;
    assign da2_clk = clk_64m;
    assign da2_wrt = clk_64m;
    assign ad_clk = clk_64m;

endmodule

// 七段数码管显示模块
module seg7_display(
    input clk,
    input [3:0] data,
    output reg [3:0] seg_s,
    output reg [7:0] seg_ap
);

    reg [1:0] cnt = 0;
    always @(posedge clk) begin
        cnt <= cnt + 1;
    end

    always @(*) begin
        seg_s = 4'b1111; // 默认关闭所有数码管
        seg_s[cnt] = 1'b0; // 使能当前数码管
        
        case (data)
            4'h0: seg_ap = 8'b11000000; // 0
            4'h1: seg_ap = 8'b11111001; // 1
            4'h2: seg_ap = 8'b10100100; // 2
            4'h3: seg_ap = 8'b10110000; // 3
            4'h4: seg_ap = 8'b10011001; // 4
            4'h5: seg_ap = 8'b10010010; // 5
            4'h6: seg_ap = 8'b10000010; // 6
            4'h7: seg_ap = 8'b11111000; // 7
            4'h8: seg_ap = 8'b10000000; // 8
            4'h9: seg_ap = 8'b10010000; // 9
            4'hA: seg_ap = 8'b10001000; // A
            4'hB: seg_ap = 8'b10000011; // B
            4'hC: seg_ap = 8'b11000110; // C
            4'hD: seg_ap = 8'b10100001; // D
            4'hE: seg_ap = 8'b10000110; // E
            4'hF: seg_ap = 8'b10001110; // F
            default: seg_ap = 8'b11111111; // 全灭
        endcase
    end

endmodule
//module cxd720_top(
//    input clk_100m_in,
//    input rst,
//    input [4:1] key,
//    output [8:1] led,
//    output [3:0] seg_s,
//    output [7:0] seg_ap,
//    output ad_clk,
//    input [11:0] ad_din,
//    output da1_wrt,
//    output da1_clk,
//    output reg [13:0] da1_out,
//    output da2_wrt,
//    output da2_clk,
//    output reg [13:0] da2_out,
//    output [38:3] ext
//);
//  reg [51:0] half_power;
//    // 时钟生成
//    wire clk_64m;
//    wire clk_64m_locked;
//    clk_64m clk_64_inst(
//        .clk_out_64m(clk_64m),
//        .locked(clk_64m_locked),
//        .clk_in1(clk_100m_in)
//    );

//    // 测试信号生成
//    wire signed [13:0] cos1m_data, cos8m_data;
//    dds_compiler_0 dds_inst_1m(
//        .aclk(clk_64m),
//        .s_axis_config_tvalid(1'b1),
//        .s_axis_config_tdata(23'H20000),
//        .m_axis_data_tdata(cos1m_data)
//    );

//    dds_compiler_0 dds_inst_8m(
//        .aclk(clk_64m),
//        .s_axis_config_tvalid(1'b1),
//        .s_axis_config_tdata(23'H100000),
//        .m_axis_data_tdata(cos8m_data)
//    );

//    wire signed [14:0] cos_add;
//    assign cos_add = cos1m_data + cos8m_data;

//    // ADC输入预处理
//    reg signed [11:0] adc12_in_r;
//    always @(posedge clk_64m) begin
//        adc12_in_r <= ad_din + 12'H800;
//    end

//    // FFT处理
//    wire signed [24:0] fft_real, fft_imag;
//    wire [7:0] fft_index; // 8位索引，范围0-255
//    wire [51:0] fft_abs;
//    assign fft_abs = fft_real*fft_real + fft_imag*fft_imag;

//    fft_256_top fft_U0(
//        .clkin_128m(clk_64m),
//        .sig_i({adc12_in_r, 4'b0000}),
//        .sig_q(16'H0),
//        .fft_real(fft_real),
//        .fft_imag(fft_imag),
//        .out_index(fft_index)
//    );

//    // 调制识别核心
//    reg [1:0] mod_type = 2'b00; // 00=未知, 01=CW, 10=AM, 11=FM
//    reg [7:0] frame_counter = 0;
//    reg [51:0] max_value = 0;
//    reg [7:0] max_index = 0;
//    reg [51:0] total_energy = 0;
//    reg [51:0] left_sideband = 0;
//    reg [51:0] right_sideband = 0;
//    reg [7:0] left_bound = 0;
//    reg [7:0] right_bound = 0;
//    reg [7:0] bandwidth = 0;
    
//    // 频谱缓冲区
//    reg [51:0] fft_abs_buffer [0:255];
    
//    // FFT帧处理状态机
//    reg [1:0] state = 0;
//    parameter IDLE = 0, COLLECT = 1, ANALYZE = 2, DECIDE = 3;
    
//    always @(posedge clk_64m) begin
//        if (rst) begin
//            state <= IDLE;
//            frame_counter <= 0;
//            max_value <= 0;
//            max_index <= 0;
//            total_energy <= 0;
//            mod_type <= 2'b00;
//        end else begin
//            case (state)
//                IDLE: begin
//                    if (fft_index == 0) begin
//                        state <= COLLECT;
//                        max_value <= 0;
//                        max_index <= 0;
//                        total_energy <= 0;
//                    end
//                end
                
//                COLLECT: begin
//                    // 存储当前频谱点
//                    fft_abs_buffer[fft_index] <= fft_abs;
                    
//                    // 更新总能量
//                    total_energy <= total_energy + fft_abs;
                    
//                    // 寻找最大峰值
//                    if (fft_abs > max_value) begin
//                        max_value <= fft_abs;
//                        max_index <= fft_index;
//                    end
                    
//                    // 修复：使用255作为结束点（256点FFT）
//                    if (fft_index == 255) begin
//                        state <= ANALYZE;
//                        frame_counter <= 0;
//                    end
//                end
                
//                ANALYZE: begin
//                    // 获取边带值（使用缓冲区）
//                    left_sideband <= (max_index > 0) ? fft_abs_buffer[max_index - 1] : 0;
//                    right_sideband <= (max_index < 255) ? fft_abs_buffer[max_index + 1] : 0;
                    
//                    // 计算带宽
//                    if (frame_counter == 0) begin
//                        left_bound <= (max_index > 10) ? max_index - 10 : 0;
//                        right_bound <= (max_index < 245) ? max_index + 10 : 255;
//                        frame_counter <= 1;
//                    end else if (frame_counter < 20) begin
//                        // 寻找-3dB点（半功率点）
//                        half_power = max_value >> 1; // max_value/2
                        
//                        // 向左扩展
//                        if (left_bound > 0 && fft_abs_buffer[left_bound] > half_power)
//                            left_bound <= left_bound - 1;
                            
//                        // 向右扩展
//                        if (right_bound < 255 && fft_abs_buffer[right_bound] > half_power)
//                            right_bound <= right_bound + 1;
                            
//                        frame_counter <= frame_counter + 1;
//                    end else begin
//                        bandwidth <= right_bound - left_bound;
//                        state <= DECIDE;
//                    end
//                end
                
//                DECIDE: begin
//                    // 调制类型判决
//                    if (max_value > total_energy / 2) begin
//                        mod_type <= 2'b01; // CW (单频信号)
//                    end 
//                    else if (left_sideband > max_value / 10 && 
//                             right_sideband > max_value / 10 &&
//                             left_sideband + right_sideband > max_value / 5) begin
//                        mod_type <= 2'b10; // AM (存在边带)
//                    end 
//                    else if (bandwidth > 5) begin
//                        mod_type <= 2'b11; // FM (宽带信号)
//                    end 
//                    else begin
//                        mod_type <= 2'b00; // 未知
//                    end
//                    state <= IDLE;
//                end
//            endcase
//        end
//    end

//    // 结果显示
//   // assign led[1:0] = mod_type; // LED显示调制类型
    
//    // 七段数码管显示调制类型
//    reg [3:0] seg_data;
//    always @(*) begin
//        case (mod_type)
//            2'b01: seg_data = 4'hC; // 显示"C" (CW)
//            2'b10: seg_data = 4'hA; // 显示"A" (AM)
//            2'b11: seg_data = 4'hF; // 显示"F" (FM)
//            default: seg_data = 4'h0; // 显示"0" (未知)
//        endcase
//    end
    
//    // 七段数码管显示模块
//    seg7_display seg7_inst(
//        .clk(clk_64m),
//        .data(seg_data),
//        .seg_s(seg_s),
//        .seg_ap(seg_ap)
//    );

//    // ILA调试
//    ila_0 ila_inst (
//        .clk(clk_64m),
//        .probe0(fft_index),
//        .probe1(fft_abs[35:0]) // 取低36位显示
//    );

//    // DA输出
//    wire signed [13:0] fir_out;
//    fir_lp_0 fir_lp_0_inst(
//        .aclk(clk_64m),
//        .s_axis_data_tvalid(1'b1),
//        .s_axis_data_tdata(adc12_in_r),
//        .m_axis_data_tdata(fir_out)
//    );

//    always @(posedge clk_64m) begin
//        da1_out <= fir_out + 14'H2000;
//        da2_out <= cos_add[14:1] + 14'H2000;
//    end

//    assign da1_clk = clk_64m;
//    assign da1_wrt = clk_64m;
//    assign da2_clk = clk_64m;
//    assign da2_wrt = clk_64m;
//    assign ad_clk = clk_64m;

//endmodule

//// 七段数码管显示模块
//module seg7_display(
//    input clk,
//    input [3:0] data,
//    output reg [3:0] seg_s,
//    output reg [7:0] seg_ap
//);

//    reg [1:0] cnt = 0;
//    always @(posedge clk) begin
//        cnt <= cnt + 1;
//    end

//    always @(*) begin
//        seg_s = 4'b1111; // 默认关闭所有数码管
//        seg_s[cnt] = 1'b0; // 使能当前数码管
        
//        case (data)
//            4'h0: seg_ap = 8'b11000000; // 0
//            4'h1: seg_ap = 8'b11111001; // 1
//            4'h2: seg_ap = 8'b10100100; // 2
//            4'h3: seg_ap = 8'b10110000; // 3
//            4'h4: seg_ap = 8'b10011001; // 4
//            4'h5: seg_ap = 8'b10010010; // 5
//            4'h6: seg_ap = 8'b10000010; // 6
//            4'h7: seg_ap = 8'b11111000; // 7
//            4'h8: seg_ap = 8'b10000000; // 8
//            4'h9: seg_ap = 8'b10010000; // 9
//            4'hA: seg_ap = 8'b10001000; // A
//            4'hB: seg_ap = 8'b10000011; // B
//            4'hC: seg_ap = 8'b11000110; // C
//            4'hD: seg_ap = 8'b10100001; // D
//            4'hE: seg_ap = 8'b10000110; // E
//            4'hF: seg_ap = 8'b10001110; // F
//            default: seg_ap = 8'b11111111; // 全灭
//        endcase
//    end

//endmodule