# include("adcs/att_err_processing.jl"); 
using CSV
using DataFrames
using Plots
using Plots.PlotMeasures
using DirectConvolution

################
## Plot Setup ##;
################
function hexcolor(r::UInt8, g::UInt8, b::UInt8)
    return RGB(Int(r)/255,Int(g)/255,Int(b)/255)
end

# Ethan's colorblind friendlier color palette
et_black = hexcolor(0x00,0x00,0x00); # black
et_gray = hexcolor(0xd3,0xd3,0xd3); # gray
et_red = hexcolor(0xB3,0x00,0x07); # red
et_reddish_orange = hexcolor(0xD5,0x5E,0x00); # reddish orange
et_orange = hexcolor(0xE6,0x9F,0x00); # orange
et_yellow = hexcolor(0xF0,0xE4,0x42); # yellow
et_green = hexcolor(0x00,0x9E,0x73); # green
et_light_green = hexcolor(0x00,0xDA,0xA0); # green
et_blue = hexcolor(0x00,0x72,0xB2); # blue
et_light_blue = hexcolor(0x56,0xB4,0xE9); # light blue
et_purplish_pink = hexcolor(0xCC,0x79,0xA7); # purplish pink
et_purple = hexcolor(0x91,0x64,0xc2); # purple

ethans_colors = [et_red, et_green, et_blue, et_purple, et_orange, et_light_blue, et_purplish_pink, et_reddish_orange]

# Assuming 50 Ohm system impedance
const impedance_Ohm = 50

function dBm_to_mVpp(dBm)
    # Convert dBm to Watts
    power_W = 10 ^ ((dBm - 30) / 10)
    # Convert power (W) to voltage (V)
    voltage_V = sqrt(power_W * impedance_Ohm)
    # Convert voltage from V to mV
    voltage_mV = voltage_V * 1000
    # Obtain peak to peak voltage
    vpp_mV = voltage_mV * 2 * sqrt(2)
    return vpp_mV
end


# https://github.com/vincent-picaud/DirectConvolution.jl
# https://pixorblog.wordpress.com/2016/07/13/savitzky-golay-filters-julia/
function smooth(signal, filterwidth::Int, polydegree::Int)
    s = Float64[i for i in signal]
    sg = SG_Filter(halfWidth=filterwidth,degree=polydegree)
    ss = apply_SG_filter(s, sg)
    return ss # 1d savitzky-golay smoothed signal
end