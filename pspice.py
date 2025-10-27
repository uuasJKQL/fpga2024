import os
import matplotlib.pyplot as plt
import numpy as np
import PySpice.Logging.Logging as Logging
from PySpice.Spice.Netlist import Circuit
from PySpice.Unit import *
import logging

# 设置日志级别为ERROR以减少输出
logger = Logging.setup_logging(logging_level=logging.ERROR)

def plot_nmos_iv_characteristics():
    """绘制NMOS的I-V特性曲线"""
    
    # 定义要测试的两种NMOS尺寸
    nmos_devices = [
        {'name': 'NMOS_W1.2_L0.25', 'w': 1.2, 'l': 0.25},
        {'name': 'NMOS_W4.8_L0.5', 'w': 4.8, 'l': 0.5}
    ]
    
    # 创建图形
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 6))
    
    colors = ['b', 'g', 'r', 'c', 'm', 'y']
    
    for device_idx, device in enumerate(nmos_devices):
        print(f"仿真 {device['name']}...")
        
        # 创建电路
        circuit = Circuit(f"{device['name']} I-V")
        
        # 添加电源和元件
        circuit.V('vdd', 'vdd', circuit.gnd, 5@u_V)  # 电源电压
        circuit.V('gate', 'gate', circuit.gnd, 0@u_V)   # 栅极电压
        
        # 添加NMOS晶体管 - 使用简化的模型参数（不带单位）
        circuit.model('nmos_model', 'nmos', 
                      level=1,
                      kp=120e-6,     # 120 μA/V²，直接使用数值
                      vto=0.4,       # 阈值电压
                      lambda_=0.05,  # 沟道长度调制系数
                      gamma=0.5,     # 体效应系数
                      phi=0.7)       # 表面势
        
        # 添加NMOS - 使用指定的W和L
        circuit.MOSFET(1, 'drain', 'gate', circuit.gnd, circuit.gnd, 
                      model='nmos_model', 
                      w=device['w']@u_um, 
                      l=device['l']@u_um)
        
        # 添加一个小的采样电阻来测量电流
        circuit.R('sense', 'drain', 'out', 1@u_Ω)  # 1Ω采样电阻
        
        # 在输出节点添加电压源来扫描Vds
        circuit.V('drain', 'out', circuit.gnd, 0@u_V)
        
        # 不同的Vgs值
        vgs_values = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
        
        for vgs_idx, vgs in enumerate(vgs_values):
            print(f"  仿真 Vgs = {vgs}V")
            
            try:
                # 创建仿真器
                simulator = circuit.simulator()
                
                # 设置Vgs值
                circuit['Vgate'].dc_value = vgs@u_V
                
                # 扫描Vds从0到5V
                analysis = simulator.dc(Vdrain=slice(0, 5, 0.05))
                
                # 获取漏极电流Id - 通过测量采样电阻的电压来计算电流
                # I = V/R，其中R=1Ω，所以I = V
                v_drain = np.array(analysis['out'])  # 采样电阻后的电压
                v_sense = np.array(analysis['drain']) - v_drain  # 采样电阻两端的电压
                id_current = -v_sense / 1.0  # 电流 = 电压/电阻，电阻=1Ω
                
                # 获取Vds值
                vds = np.array(analysis['out'])
                
                # 绘制I-V曲线
                if device_idx == 0:
                    ax1.plot(vds, id_current * 1e6, 
                            color=colors[vgs_idx], 
                            linewidth=2,
                            label=f'Vgs = {vgs}V')
                    ax1.set_title(f"NMOS W={device['w']}µm, L={device['l']}µm")
                else:
                    ax2.plot(vds, id_current * 1e6, 
                            color=colors[vgs_idx], 
                            linewidth=2,
                            label=f'Vgs = {vgs}V')
                    ax2.set_title(f"NMOS W={device['w']}µm, L={device['l']}µm")
                    
            except Exception as e:
                print(f"  Vgs={vgs}V 时出错: {e}")
                continue
    
    # 设置图形属性
    for ax in [ax1, ax2]:
        ax.set_xlabel('Vds (V)')
        ax.set_ylabel('Id (µA)')
        ax.grid(True, alpha=0.3)
        ax.legend()
        ax.set_xlim(0, 5)
    
    plt.tight_layout()
    plt.savefig('nmos_iv_characteristics.png', dpi=150, bbox_inches='tight')
    plt.show()

def plot_pmos_iv_characteristics():
    """绘制PMOS的I-V特性曲线"""
    
    # 定义要测试的两种PMOS尺寸
    pmos_devices = [
        {'name': 'PMOS_W1.2_L0.25', 'w': 1.2, 'l': 0.25},
        {'name': 'PMOS_W4.8_L0.5', 'w': 4.8, 'l': 0.5}
    ]
    
    # 创建图形
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 6))
    
    colors = ['b', 'g', 'r', 'c', 'm', 'y']
    
    for device_idx, device in enumerate(pmos_devices):
        print(f"仿真 {device['name']}...")
        
        # 创建电路 - PMOS需要不同的连接方式
        circuit = Circuit(f"{device['name']} I-V")
        
        # 对于PMOS，源极通常接最高电位
        circuit.V('vdd', 'vdd', circuit.gnd, 5@u_V)  # 电源电压
        circuit.V('gate', 'gate', 'vdd', 0@u_V)      # 栅极电压（相对于Vdd）
        
        # 添加PMOS晶体管模型
        circuit.model('pmos_model', 'pmos', 
                      level=1,
                      kp=40e-6,      # PMOS的kp通常比NMOS小
                      vto=-0.4,      # 负阈值电压
                      lambda_=0.05,  # 沟道长度调制系数
                      gamma=0.5,
                      phi=0.7)
        
        # 添加PMOS - 源极接Vdd
        circuit.MOSFET(1, 'drain', 'gate', 'vdd', 'vdd', 
                      model='pmos_model', 
                      w=device['w']@u_um, 
                      l=device['l']@u_um)
        
        # 添加采样电阻
        circuit.R('sense', 'vdd', 'source_out', 1@u_Ω)  # 1Ω采样电阻
        
        # 在源极节点添加电压源来扫描Vds
        circuit.V('source', 'source_out', 'drain', 0@u_V)
        
        # 不同的Vgs值（对于PMOS，Vgs是负值）
        vgs_values = [-0.5, -1.0, -1.5, -2.0, -2.5, -3.0]
        
        for vgs_idx, vgs in enumerate(vgs_values):
            print(f"  仿真 Vgs = {vgs}V")
            
            try:
                # 创建仿真器
                simulator = circuit.simulator()
                
                # 设置Vgs值
                circuit['Vgate'].dc_value = vgs@u_V
                
                # 扫描Vsource从0到-5V（PMOS的Vds为负）
                analysis = simulator.dc(Vsource=slice(0, -5, -0.05))
                
                # 获取漏极电流Id - 通过测量采样电阻的电压来计算电流
                v_source_out = np.array(analysis['source_out'])
                v_vdd = 5.0  # 固定Vdd电压
                v_sense = v_vdd - v_source_out  # 采样电阻两端的电压
                id_current = v_sense / 1.0  # 电流 = 电压/电阻，电阻=1Ω
                
                # 获取Vds值（绝对值）
                vds = -np.array(analysis['source_out']) + np.array(analysis['drain'])
                
                # 绘制I-V曲线（使用绝对值便于比较）
                if device_idx == 0:
                    ax1.plot(vds, id_current * 1e6, 
                            color=colors[vgs_idx], 
                            linewidth=2,
                            label=f'Vgs = {vgs}V')
                    ax1.set_title(f"PMOS W={device['w']}µm, L={device['l']}µm")
                else:
                    ax2.plot(vds, id_current * 1e6, 
                            color=colors[vgs_idx], 
                            linewidth=2,
                            label=f'Vgs = {vgs}V')
                    ax2.set_title(f"PMOS W={device['w']}µm, L={device['l']}µm")
                    
            except Exception as e:
                print(f"  Vgs={vgs}V 时出错: {e}")
                continue
    
    # 设置图形属性
    for ax in [ax1, ax2]:
        ax.set_xlabel('|Vds| (V)')
        ax.set_ylabel('|Id| (µA)')
        ax.grid(True, alpha=0.3)
        ax.legend()
        ax.set_xlim(0, 5)
    
    plt.tight_layout()
    plt.savefig('pmos_iv_characteristics.png', dpi=150, bbox_inches='tight')
    plt.show()

def analyze_operation_regions():
    """分析并标注工作区域"""
    
    print("""
    MOSFET I-V特性分析:
    
    1. 工作区域:
       a. 截止区 (Cut-off Region):
          - Vgs < Vth (阈值电压)
          - 几乎没有电流流动
          
       b. 线性区/三极管区 (Linear/Triode Region):
          - Vgs > Vth 且 Vds < Vgs - Vth
          - 电流随Vds线性增加
          - 表现为电阻特性
          
       c. 饱和区 (Saturation Region):
          - Vgs > Vth 且 Vds > Vgs - Vth  
          - 电流基本恒定，轻微上升（沟道长度调制效应）
          - 用于放大应用
    
    2. 沟道长度调制效应:
       - 在饱和区，理想情况下Id应该完全平坦
       - 但由于沟道长度调制(lambda参数)，Id会随Vds增加而轻微上升
       - 这在短沟道器件(L较小)中更明显
    
    3. 速度饱和:
       - 在短沟道器件中，当横向电场足够大时，载流子速度达到饱和
       - 表现为: 饱和电流比长沟道器件低，饱和区更早出现
       - 在I-V曲线上看: 饱和电压降低，电流在较低Vds时就趋于饱和
       - 通常L=0.25µm的器件会比L=0.5µm的器件更容易出现速度饱和
    
    观察要点:
    - 比较不同沟道长宽比的器件电流驱动能力
    - 观察饱和区的斜率（沟道长度调制）
    - 注意短沟道器件的饱和特性
    """)

if __name__ == '__main__':
    print("开始绘制MOSFET I-V特性曲线...")
    
    # 绘制NMOS I-V特性
    print("\n=== 绘制NMOS I-V特性 ===")
    plot_nmos_iv_characteristics()
    
    # 绘制PMOS I-V特性  
    print("\n=== 绘制PMOS I-V特性 ===")
    plot_pmos_iv_characteristics()
    
    # 分析工作区域
    print("\n=== 工作区域和效应分析 ===")
    analyze_operation_regions()
    
    print("\n✅ 所有仿真完成!")
    print("生成的图像文件:")
    print("  - nmos_iv_characteristics.png")
    print("  - pmos_iv_characteristics.png")