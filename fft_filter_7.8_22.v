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
    input [32:9] ext,
    output clk_2,
    input  D11
);

wire [11:0] ad;
//assign ad[8:1]=ext[10:3];
//assign ad[11:9]=ext[31:29];
//assign ad[0]=ext[32];
assign ad[0]=D11;

assign ad[1]=ext[10];
assign ad[2]=ext[9];
assign ad[3]=ext[12];
assign ad[4]=ext[11];
  assign ad[5]=ext[14];
  assign ad[6]=ext[13];
  assign ad[7]=ext[16];
  assign ad[8]=ext[15];  
    assign ad[9]=ext[18];
    assign ad[10]=ext[17];
    assign ad[11]=ext[20];
    
    
    
    // 时钟生成
    
 reg[13:0]max_out;
   reg[31:0] center;
    reg[6:0] count_am;
     reg[6:0] count_fm;
      reg[6:0] count_cw;
      reg[6:0]count_test;
    reg [31:0] half_power;
    wire clk_64m;
    wire clk_64m_locked;
    wire clk_32m;
    clk_64m clk_64_inst(
        .clk_out_64m(clk_64m),    
           .clk_out5(clk_out2),   
        .locked(clk_64m_locked),
        .clk_in1(clk_100m_in)
    );
    assign clk_2=clk_64m;
wire signed [13:0] cos_data;
wire  signed[13:0]cos73k_data;
    // 测试信号生成
    wire signed [13:0] cos1m_data, cos8m_data;
    dds_compiler_0 dds_inst_1m(
        .aclk(clk_64m),
        .s_axis_config_tvalid(1'b1),
        .s_axis_config_tdata(23'HA3D),
        .m_axis_data_tdata(cos20k_data)
    );
wire [23:0]freq_control;
    dds_compiler_0 dds_inst_8m(
        .aclk(clk_64m),
        .s_axis_config_tvalid(1'b1),
        .s_axis_config_tdata(freq_control),
        .m_axis_data_tdata(cos_data)
    );

    wire signed [14:0] cos_add;


    // ADC输入预处理
    reg signed [11:0] adc12_in_r;
    always @(posedge clk_64m) begin
        adc12_in_r <= ad_din + 12'H800;
    end
       reg signed [11:0] adc12_in2_r;
    always @(posedge clk_64m) begin
        adc12_in2_r <= ad + 12'H800;
    end
      always @(posedge clk_64m) begin
       da2_out <=  cos_data+ 14'H2000;
    end
     always @(posedge clk_64m) begin
       da1_out <=  {  adc12_in_r,2'b00} + 14'H2000;
    end
   wire valid;
    wire valid_1;
    // FFT处理 - 4096点==========================================
    wire signed [28:0] fft_real, fft_imag;
    wire [11:0] fft_index; // 12位索引，范围0-4095
    reg [59:0] fft_abs;
    always @(posedge clk_64m) begin
         if(valid)begin
            
          fft_abs = fft_real*fft_real + fft_imag*fft_imag;
         end
    end
  
    
    wire signed [28:0] fft_real_b, fft_imag_b;
    wire [11:0] fft_index_b; // 12位索引，范围0-4095
    reg[59:0] fft_abs_b;
 
    reg valid_reg;
    reg valid_reg_1;
      always @(posedge clk_64m) begin
         if(valid_1)begin
            
          fft_abs_b =( fft_real_b*fft_real_b + fft_imag_b*fft_imag_b)<<2;
         end
    end

    // 替换为4096点FFT模块
    fft_256_top fft_U0(
        .clkin_128m( clk_64m),
        .sig_i({adc12_in_r, 4'b0000}),
        .sig_q(16'H0),
        .fft_real(fft_real),
        .fft_imag(fft_imag),
        .out_index(fft_index),
        .valid(valid)
    );
        fft_256_top fft_U1(
        .clkin_128m( clk_64m),
        .sig_i({adc12_in2_r,4'b0000}),
        .sig_q(16'H0),
        .fft_real(fft_real_b),
        .fft_imag(fft_imag_b),
        .out_index(fft_index_b),
        .valid(valid_1)
    );
    // =========================================================
// 在模块顶部定义FFT点数参数

    // 调制识别核心 - 适应4096点FFT==============================
    reg [1:0] mod_type = 2'b00; // 00=未知, 01=CW, 10=AM, 11=FM
    reg [11:0] frame_counter = 0; // 扩展到12位
    reg [59:0] max_value = 0;
    reg [11:0] max_index = 0; // 扩展到12位
reg [11:0] max_index_r = 0; // 扩展到12位
reg [11:0] max_index_b_r = 0; // 扩展到12位
     reg [59:0] max_value_b = 0;
    reg [11:0] max_index_b = 0; // 扩展到12位
reg [59:0]max_value_r=0;
reg [59:0]max_value_b_r=0;

reg [11:0]index;
 reg [11:0]max_filter_index;
  reg [59:0]max_filter;
   reg [11:0]max_filter_index_r;
  reg [59:0]max_filter_r;
    // 频谱缓冲区 - 增加到4096点
    reg [59:0] fft_abs_buffer [0:2047];
     reg [59:0] fft_abs_buffer_b [0:2047];
      reg fft_finish;
      reg fft_finish_b;
assign freq_control=(max_filter_index_r>>3)*8'H41;
    // FFT帧处理状态机
    reg [2:0] state = 0;
    parameter IDLE = 0, COLLECT = 1, ANALYZE = 2,FIND_MAX=3,FINISH=4;
       reg [2:0] state_b = 0;
       reg [2:0] state_a=0;
     always @(posedge clk_64m) begin
        if (rst) begin
            state_b <= IDLE;
        
            max_value_b <= 0;
            max_index_b <= 0;
   
        end else begin
            case (state_b)
   
                IDLE: begin
                    if (fft_index_b == 0) begin
                        state_b <= COLLECT;
                        max_value_b <= 0;
                        max_index_b <= 0;
                    fft_finish_b<=0;
                        
                    end
                end
                
                COLLECT: begin
                    // 存储当前频谱点
              
                    fft_abs_buffer_b[fft_index_b] <= fft_abs_b;
                    
                    // 更新总能量
                  //  total_energy <= total_energy + fft_abs;
                    
                    // 寻找最大峰值
                    if (fft_abs_b > max_value_b&&fft_index_b<2044&&fft_index_b>3) begin
                        max_value_b <= fft_abs_b;
                        max_index_b <= fft_index_b;
                    end
                    
                    // 使用4095作为结束点（4096点FFT）
                    if (fft_index_b == 2047) begin
                        max_index_b_r<=max_index_b;
                        max_value_b_r<=max_value_b;
                        fft_finish_b<=1;
                        state_b<=ANALYZE;
                      
                    end
                
               
                end
                  ANALYZE:
                begin
                    if(state_a==FINISH)
                    state_b<=IDLE;
                end
             endcase
        end
    end
    always @(posedge clk_64m) begin
        if (rst) begin
            state <= IDLE;
       
            max_value <= 0;
            max_index <= 0;
     
       
        end else begin
            case (state)
   
                IDLE: begin
                    if (fft_index == 0) begin
                        state <= COLLECT;
                        max_value <= 0;
                        max_index <= 0;
                      fft_finish<=0;
    
                        
                    end
                end
                
                COLLECT: begin
                    // 存储当前频谱点
              
                    fft_abs_buffer[fft_index] <= fft_abs;
                    
                    // 更新总能量
                  //  total_energy <= total_energy + fft_abs;
                    
                    // 寻找最大峰值
                    if (fft_abs > max_value&&fft_index<2044&&fft_index>3) begin
                        max_value <= fft_abs;
                        max_index <= fft_index;
                    end
                    
                    // 使用4095作为结束点（4096点FFT）
                    if (fft_index == 2047) begin
                        max_index_r<=max_index;
                        max_value_r<=max_value;
                        fft_finish<=1;
                        state<=ANALYZE;
                     
                    end
                
               
                end

                ANALYZE:
                begin
                    if(state_a==FINISH)
                    state<=IDLE;
                   
                end
             endcase
        end
    end
    always @(posedge clk_64m) begin

case (state_a)
   IDLE :begin
    if (fft_finish&&fft_finish_b) begin
    
state_a<=FIND_MAX;

    end
   end 
   
   FIND_MAX:
   begin
        
            if(index<2047)
begin
   if(fft_abs_buffer[index]>fft_abs_buffer_b[index]&&index>10&&index<2037)
   begin
    
    if(fft_abs_buffer[index]-fft_abs_buffer_b[index]>max_filter)
   begin
    max_filter<=fft_abs_buffer[index]-fft_abs_buffer_b[index];
   max_filter_index<=index;
   end
   
   end
    index<=index+1;
end
else
begin
    index<=0;
    state_a<=FINISH;
max_filter_index_r<=max_filter_index;
max_filter_r<=max_filter;
   end
   
   end 
   
    default:; 


FINISH:
begin
    max_filter<=0;
    max_filter_index<=0;
   if(fft_finish==0&&fft_finish_b==0)
   state_a<=IDLE; 
end
endcase
    end
//                 SUB:
//                 begin
//                    if(index<2047)
// begin
//     fft_abs_result[index]<= (fft_abs_buffer[index]>fft_abs_buffer_b[index]?fft_abs_buffer[index]-fft_abs_buffer_b[index]:0);
//     index<=index+1;
// end
// else
// begin
//     index<=0;
//     state<=FIND_WIDTH;
// end


//                 end
                
                // FIND_WIDTH: begin
                //     if(index<2048)
                //     begin
                //     index<=index+1;
                    
                //      if (fft_abs_result[index] > max_value_1&&index>10&&index<2037) begin
                    
                //         max_value_1 <= fft_abs_result[index];
                //         max_index_1 <= index;
                      
                        
                //     end
                //     end
                //     else
                //     begin
                //         index<=0;
                //         state<=ANALYZE;
                //     end
                    
                




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
reg [11:0]seg_data_f;
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
        .probe0(cos_data),
        .probe1(max_value_b_r), // 取低36位显示
         .probe2(max_value_r),
          .probe3(freq_control),
           .probe4(max_index_b_r),
          .probe5(max_filter_index_r),
             .probe6(max_index_r)
    );

    // DA输出
    wire signed [13:0] fir_out;
    fir_lp_0 fir_lp_0_inst(
        .aclk(clk_64m),
        .s_axis_data_tvalid(1'b1),
        .s_axis_data_tdata(adc12_in_r),
        .m_axis_data_tdata(fir_out)
    );

    // always @(posedge clk_64m) begin
    //     da1_out <= fir_out + 14'H2000;
    //     da2_out <= cos_add[14:1] + 14'H2000;
    // end

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
//module fft_4096_top(  // 修改模块名反映实际点数
//  input  clkin_128m,
//  input  signed [15:0] sig_i,
//  input  signed [15:0] sig_q,
//  output signed [28:0] fft_real,  // 修正位宽为32位
//  output signed [28:0] fft_imag,
//  output [15:0] out_index
//);

//   wire [7:0] fft_s_config_tdata;//[0:0]FWD_INV_0

//   wire [7:0] fft_m_status_tdata;
  

//   wire fft_m_data_tlast;

//   wire [31:0] fft_s_data_tdata;

//   wire fft_m_data_tvalid;
//// ==============================================
//// 1. 时钟分频生成250kHz采样率 (128MHz/512=250kHz)
//// ==============================================
//reg [8:0] clk_div = 0;  // 512分频计数器 (2^9=512)
//reg sample_en;

//always @(posedge clkin_128m) begin
//    if(clk_div == 9'd499) begin
//        clk_div <= 0;
//        sample_en <= 1'b1;
//    end else begin
//        clk_div <= clk_div + 1;
//        sample_en <= 1'b0;
//    end
//end

//// ==============================================
//// 2. 数据流水线寄存器
//// ==============================================
//reg [31:0] fft_input_reg;
//always @(posedge clkin_128m) begin
//    if(sample_en) 
//        fft_input_reg <= {sig_q, sig_i};  // I/Q拼接
//end
//assign fft_s_data_tdata =fft_input_reg;
//// ==============================================
//// 3. FFT控制信号声明
//// ==============================================
//wire fft_s_config_tready;
//wire [63:0] fft_m_data_tdata;
//wire [15:0] fft_m_data_tuser;

//// ==============================================
//// 4. FFT配置状态机 (4096点专用)
//// ==============================================
//reg [1:0] state = 0;
//reg fft_s_config_tvalid = 0;
//reg fft_s_data_tvalid = 0;
//reg fft_s_data_tlast = 0;
//reg [11:0] sample_count = 0;  // 12位计数器 (2^12=4096)

//always @(posedge clkin_128m) begin
//    case(state)
//        0: begin // 发送配置
//            fft_s_config_tvalid <= 1'b1;
//            if(fft_s_config_tready) begin
//                state <= 1;
//            end
//        end
//        1: begin // 配置完成
//            fft_s_config_tvalid <= 1'b0;
//            state <= 2;
//        end
//        2: begin // 数据输入
//            fft_s_data_tvalid <= sample_en; // 250kHz有效
            
//            if(sample_en) begin
//                // 帧结束检测 (4095时置位tlast)
//                if(sample_count == 12'd4095) begin
//                    fft_s_data_tlast <= 1'b1;
//                    sample_count <= 0;
//                end else begin
//                    fft_s_data_tlast <= 1'b0;
//                    sample_count <= sample_count + 1;
//                end
//            end
//        end
//    endcase
//end

//// ==============================================
//// 5. 输出处理逻辑
//// ==============================================
//reg signed [28:0] fft_real_reg;
//reg signed [28:0] fft_imag_reg;
//reg [15:0] index_reg;

//// 添加输出有效标志
//reg output_valid;
//always @(posedge clkin_128m) begin
//    if(fft_m_data_tvalid) begin
//        fft_real_reg <= fft_m_data_tdata[31:0];   // 实部在低32位
//        fft_imag_reg <= fft_m_data_tdata[63:32];  // 虚部在高32位
//        index_reg <= fft_m_data_tuser;
//        output_valid <= 1'b1;
//    end else begin
//        output_valid <= 1'b0;
//    end
//end

//assign fft_real = fft_real_reg;
//assign fft_imag = fft_imag_reg;
//assign out_index = index_reg;

//// ==============================================
//// 6. FFT配置参数
//// ==============================================
//assign fft_s_config_tdata = 8'b00000001; // FFT模式

//// ==============================================
//// 7. 实例化4096点FFT IP核
//// ==============================================
//FFT_4096 FFT_4096_U0 (  // 修改实例化名称
//    .aclk(clkin_128m),                      
//    .aresetn(1'b1),                        // 复位信号保持高电平
//    .s_axis_config_tdata(fft_s_config_tdata),  
//    .s_axis_config_tvalid(fft_s_config_tvalid),
//    .s_axis_config_tready(fft_s_config_tready),
//    .s_axis_data_tdata(fft_s_data_tdata),    
//    .s_axis_data_tvalid(fft_s_data_tvalid),  
//    .s_axis_data_tready(fft_s_data_tready),  // 监控背压信号
//    .s_axis_data_tlast(fft_s_data_tlast),    
//    .m_axis_data_tdata(fft_m_data_tdata),    
//    .m_axis_data_tuser(fft_m_data_tuser),    
//    .m_axis_data_tvalid(fft_m_data_tvalid),  
//    .m_axis_data_tready(1'b1),              
//    .m_axis_data_tlast(fft_m_data_tlast),    
//    // 事件信号
//    .event_frame_started(event_frame_started),
//    .event_tlast_unexpected(event_tlast_unexpected),
//    .event_tlast_missing(event_tlast_missing),
//    .event_status_channel_halt(event_status_channel_halt),
//    .event_data_in_channel_halt(event_data_in_channel_halt),
//    .event_data_out_channel_halt(event_data_out_channel_halt)
//);

//// ==============================================
//// 8. 性能监控逻辑 (调试用)
//// ==============================================
//// 采样率验证
//reg [31:0] sample_counter, time_counter;
//always @(posedge clkin_128m) begin
//    time_counter <= time_counter + 1;
//    if(sample_en) sample_counter <= sample_counter + 1;
//end

//// 背压检测
//wire backpressure = fft_s_data_tvalid && !fft_s_data_tready;

//endmodule
`timescale 1ns / 1ps

module fft_256_top(
  input  clkin_128m,
  input  signed [15:0] sig_i,
  input  signed [15:0] sig_q,
  output signed [28:0] fft_real,
  output signed [28:0] fft_imag,
  output [15:0] out_index,
  output valid
);

  // ==============================================
  // 0. 窗函数参数和存储
  // ==============================================
  parameter FFT_SIZE = 4096;        // FFT点数
  parameter COEFF_WIDTH = 16;       // 窗系数位宽
  
  // 窗系数ROM - 使用预先生成的汉宁窗系数
  (* rom_style = "block" *) reg [COEFF_WIDTH-1:0] hanning_rom [0:FFT_SIZE-1];
  
  // 从文件加载窗系数 (使用MATLAB生成的hanning_rom.hex)
  initial begin
    $readmemh("/home/wyh/FPGA/cxd720_fft_256/hanning_rom.hex", hanning_rom);
    $display("Hanning window ROM initialized from file");
  end
  
  // ==============================================
  // 1. 时钟分频生成250kHz采样率 (128MHz/512=250kHz)
  // ==============================================
  reg [8:0] clk_div = 0;  // 512分频计数器 (2^9=512)
  reg sample_en;
  reg [11:0] sample_index = 0;  // 当前采样索引 (0-4095)

  always @(posedge clkin_128m) begin
    if(clk_div == 9'd249) begin  // 0-511计数，共512个周期
        clk_div <= 0;
        sample_en <= 1'b1;
        sample_index <= (sample_index == FFT_SIZE-1) ? 0 : sample_index + 1;
    end else begin
        clk_div <= clk_div + 1;
        sample_en <= 1'b0;
    end
  end

  // ==============================================
  // 2. 加窗处理逻辑
  // ==============================================
  reg signed [31:0] windowed_i = 0;
  reg signed [31:0] windowed_q = 0;
  reg signed [15:0] windowed_i_reg = 0;
  reg signed [15:0] windowed_q_reg = 0;
  
  // 加窗乘法器
  always @(posedge clkin_128m) begin
    if(sample_en) begin
      // 应用汉宁窗系数
      windowed_i <= $signed(sig_i) * $signed(hanning_rom[sample_index]);
      windowed_q <= $signed(sig_q) * $signed(hanning_rom[sample_index]);
    end
    
    // 延时一个周期取高16位 (相当于右移15位)
    windowed_i_reg <= windowed_i[30:15];
    windowed_q_reg <= windowed_q[30:15];
  end

  // ==============================================
  // 3. 数据流水线寄存器
  // ==============================================
  reg [31:0] fft_input_reg;
  always @(posedge clkin_128m) begin
    // 在乘法结果就绪后(延时一个周期)采样
    if(clk_div == 9'd0 && sample_index != 0) begin 
        fft_input_reg <= {windowed_q_reg, windowed_i_reg};  // I/Q拼接
    end
  end
  
  // ==============================================
  // 4. FFT控制信号声明
  // ==============================================
  wire [7:0] fft_s_config_tdata;
  wire fft_s_config_tready;
  wire [63:0] fft_m_data_tdata;
  wire [15:0] fft_m_data_tuser;
  wire fft_m_data_tlast;
  wire [31:0] fft_s_data_tdata;
  wire fft_m_data_tvalid;

  // ==============================================
  // 5. FFT配置状态机 (4096点专用)
  // ==============================================
  reg [1:0] state = 0;
  reg fft_s_config_tvalid = 0;
  reg fft_s_data_tvalid = 0;
  reg fft_s_data_tlast = 0;
  reg [11:0] sample_count = 0;  // 12位计数器 (2^12=4096)

  assign fft_s_data_tdata = fft_input_reg;  // 连接到加窗后的数据

  always @(posedge clkin_128m) begin
    case(state)
      0: begin // 发送配置
        fft_s_config_tvalid <= 1'b1;
        if(fft_s_config_tready) begin
          state <= 1;
        end
      end
      1: begin // 配置完成
        fft_s_config_tvalid <= 1'b0;
        state <= 2;
      end
      2: begin // 数据输入
        // 数据有效信号与采样使能对齐，但延迟一个周期
        fft_s_data_tvalid <= (clk_div == 9'd0) && (sample_index != 0);
        
        if((clk_div == 9'd0) && (sample_index != 0)) begin
          // 帧结束检测 (4095时置位tlast)
          if(sample_count == FFT_SIZE-1) begin
            fft_s_data_tlast <= 1'b1;
            sample_count <= 0;
          end else begin
            fft_s_data_tlast <= 1'b0;
            sample_count <= sample_count + 1;
          end
        end
      end
    endcase
  end

  // ==============================================
  // 6. 输出处理逻辑
  // ==============================================
  reg signed [28:0] fft_real_reg;
  reg signed [28:0] fft_imag_reg;
  reg [15:0] index_reg;

  // 添加输出有效标志
  reg output_valid;
  always @(posedge clkin_128m) begin
    if(fft_m_data_tvalid) begin
      // 根据Xilinx FFT IP核文档，输出格式为：
      // [63:48] - 虚部(Q)
      // [31:16] - 实部(I)
      fft_real_reg <= fft_m_data_tdata[28:0];
      fft_imag_reg <= fft_m_data_tdata[60:32];
      index_reg <= fft_m_data_tuser;
      output_valid <= 1'b1;
    end else begin
      output_valid <= 1'b0;
    end
  end

  assign fft_real = fft_real_reg;
  assign fft_imag = fft_imag_reg;
  assign out_index = index_reg;
assign valid=output_valid;
  // ==============================================
  // 7. FFT配置参数
  // ==============================================
  assign fft_s_config_tdata = 8'b00000001; // FFT模式

  // ==============================================
  // 8. 实例化4096点FFT IP核
  // ==============================================
  FFT_256 FFT_4096_U0 (
    .aclk(clkin_128m),                      
    .aresetn(1'b1),                        // 复位信号保持高电平
    .s_axis_config_tdata(fft_s_config_tdata),  
    .s_axis_config_tvalid(fft_s_config_tvalid),
    .s_axis_config_tready(fft_s_config_tready),
    .s_axis_data_tdata(fft_s_data_tdata),    
    .s_axis_data_tvalid(fft_s_data_tvalid),  
    .s_axis_data_tready(fft_s_data_tready),  // 监控背压信号
    .s_axis_data_tlast(fft_s_data_tlast),    
    .m_axis_data_tdata(fft_m_data_tdata),    
    .m_axis_data_tuser(fft_m_data_tuser),    
    .m_axis_data_tvalid(fft_m_data_tvalid),  
    .m_axis_data_tready(1'b1),              
    .m_axis_data_tlast(fft_m_data_tlast),    
    // 事件信号
    .event_frame_started(),
    .event_tlast_unexpected(),
    .event_tlast_missing(),
    .event_status_channel_halt(),
    .event_data_in_channel_halt(),
    .event_data_out_channel_halt()
  );

  // ==============================================
  // 9. 调试信号
  // ==============================================
  reg [15:0] dbg_window_coeff = 0;
  reg signed [15:0] dbg_input_i = 0;
  reg signed [15:0] dbg_input_q = 0;
  
  always @(posedge clkin_128m) begin
    if(sample_en) begin
      dbg_window_coeff <= hanning_rom[sample_index];
      dbg_input_i <= sig_i;
      dbg_input_q <= sig_q;
    end
  end

endmodule