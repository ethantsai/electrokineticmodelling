### A Pluto.jl notebook ###
# v0.19.40

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
end

# ╔═╡ 44bd8931-450e-4019-8dd0-30a5b25d6078
using StatsPlots, CSV, DataFrames, Unitful, Measurements, PlutoUI, Plots.PlotMeasures, RollingFunctions;

# ╔═╡ e6c4f7f0-e159-4231-9801-76a0ec643673
TableOfContents(title="HF Loop Optimization", indent=true, depth=4, aside=true)

# ╔═╡ 4392a6f5-e8dd-4fe6-b765-d21e14c32461
md"
## Introduction and Equations
This code is based off of Cavoit et al., 2006.
"

# ╔═╡ 3660811b-8146-4111-819d-794cec160072
md"
## Import Parameters
"

# ╔═╡ a47c7173-317d-4394-8357-59743f5a0982
md"
## Setup
### Basic Functions
"

# ╔═╡ a1cb22d0-7de2-4033-8643-1d8a89ab3d7d
"""
Returns the number of turns required based on desired frequency range, toroid, and jfet properties. No reliance on noise and self inductance at all.

### Examples
```julia-repl
julia> N = turns_from_freq(100e3, 10e6, 4, A_l, C_jfet, 2)
N = 42.658002367554225
```
"""
function turns_from_freq(F_lo, F_hi, N_toroids, A_l, C_jfet, N_jfet)
	F0 = sqrt(F_lo*F_hi)
	return (2 * pi * F0 * sqrt(N_toroids * A_l * C_jfet / N_jfet))^-1
end

# ╔═╡ 328d3bbc-3aa1-4e68-a3f9-997c9222f78e
"""
Returns the resonant frequency based on specific inductance, given turns, and total C_in.

### Examples
```julia-repl
julia> f_r = get_resonant_frequency(A_l, N_turns, C_jfet/num_jfets)
f_r = 67.4 ± 8.4 MHz
```
"""
function get_resonant_frequency(A_l, N_turns, C_in)
	return (2*pi*sqrt(A_l * N_turns^2 * C_in)^-1) |> u"MHz"
end

# ╔═╡ 4bd00596-c1cb-4e36-81a2-687e1b19ec0e
"""
Calculates maximum turns that can fit in a toroid with given ID and given AWG.
"""
function max_turns_per_toroid(ID, d_total)
	return pi * ID / d_total
end

# ╔═╡ 9dbd2dfd-5899-4c1f-aca4-c53d4c6b7a61
begin
	dBV2gain(dBV) = 10^(dBV/20)
	gain2dBV(gain) = 20*log10(gain)
end

# ╔═╡ 43ef91de-2b99-451a-ad20-6c9e2e5908d0
"""
Returns a range in log scale.

### Examples
```julia-repl
julia> logrange(0.1,100,10) # min, max, n_steps
[.1, 0.215443, 0.464159, 1.0, 2.15443, 4.64159, 10.0, 21.5443, 46.4159, 100.0]
```

"""
logrange(x1, x2, n::Int64) = [10^y for y in range(log10(x1), log10(x2), length=n)]

# ╔═╡ 285d9346-305b-4345-9f46-402240e7e06b
md"""
### Define Properties
#### Environmental Properties
Temperature (T): $(@bind T_unitless NumberField(0:1000, default=300)) K

#### Loop Properties
Loop Surface: $(@bind S_unitless NumberField(0.01:0.01:50000, default=11000)) mm^2

Loop Radius: $(@bind r_loop_unitless NumberField(0.01:0.01:1000, default=106)) mm

Loop Thickness: $(@bind t_loop_unitless NumberField(0.01:0.01:40, default=1)) mm

Loop Resistance: $(@bind r_b_unitless NumberField(0.01:0.01:10, default=2)) Ω

Loop Self Inductance: $(@bind L_0_unitless NumberField(0.01:0.01:10000, default=400)) nH

#### Toroid Properties
Toroid type: $(@bind toroid_type Select(["TN10/6/4-4A11", "TN13/7.5/5-4A11", "TX10/6/4-4C65"]))

Number of toroids: $(@bind num_toroids Slider(1:8, default=4, show_value=true)) toroids

#### Wire Properties
Wire type: $(@bind wire_type Select(["Cu" => "Copper", "Al" => "Aluminum", "HTCCA" => "HTCCA"]))

Wire AWG: $(@bind gauge Slider(24:56, default=30, show_value=true)) AWG

#### Amplifier Properties
Number of jfets: $(@bind num_jfets Slider(1:4, default=2, show_value=true)) jfets

JFET Input Capacitance (C\_jfet): $(@bind C_jfet_unitless NumberField(1:1000; default=20)) pF

JFET Input Voltage Noise (e\_ba): $(@bind e_ba_unitless NumberField(0:10; default=1)) nT/sqrt(Hz)

JFET Input Current Noise (i\_ba): $(@bind i_ba_unitless NumberField(0:10; default=1)) pA/sqrt(Hz)

#### Biasing Circuit Properties
Biasing Circuit Input Resistance (R\_in): $(@bind R_in_unitless NumberField(0:0.01:10; default=100)) kΩ


#### Feedback Properties
Feedback Resisitance (R\_cr): $(@bind R_cr_unitless NumberField(.1:.001:10; default=1.2)) kΩ

#### Define turns for model
Number of Turns: $(@bind N_turns NumberField(1:1000; default=50)) turns

Margin: $(@bind margin Slider(1:0.01:2; default=1.15, show_value=true))x



"""

# ╔═╡ 06f26860-d843-497f-9ae5-25594ddaddef
begin
	const k = 1.38e-23u"m^2*kg/(s^2*K)" # boltzmann constant
	const T = T_unitless*u"K" # K, operating temperature
	
	S = S_unitless * 1u"mm^2"; #mm^2
	r_loop = r_loop_unitless * 1u"mm"; #mm
	A_loop = pi*r_loop^2 #area enclosed by loop
	t_loop = t_loop_unitless * 1u"mm"; #mm, thickness of aluminum loop
	r_b = r_b_unitless * 1u"Ω"; #Ω, loop resistance
	L_0 = L_0_unitless * 1u"nH" #nH, loop self inductance
	@info "Imported loop properties."
	
	# const A_l = 348e-9 ± 0.25*348e-9 # nH, from 4A11 in 
	toroid_list = Dict([
		("TN13/7.5/5-4A11", [13u"mm" ± 0.35u"mm", 6.8u"mm" ± 0.35u"mm", 5.4u"mm" ± 0.35u"mm", 0.1u"mm", 358u"nH" ± 0.25*358u"nH", 700u"H/m" ± 0.2*700u"H/m"]),
		("TN10/6/4-4A11", [10.6u"mm" ± 0.3u"mm", 5.2u"mm" ± 0.3u"mm", 4.4u"mm" ± 0.3u"mm", 0.1u"mm", 348u"nH" ± 0.25*348u"nH", 700u"H/m" ± 0.2*700u"H/m"]),
		("TX10/6/4-4C65", [10.6u"mm" ± 0.3u"mm", 5.2u"mm" ± 0.3u"mm", 4.4u"mm" ± 0.3u"mm", 0.1u"mm", 52u"nH" ± 0.25*52u"nH", 125u"H/m" ± 0.2*125u"H/m"])
	]);
	# https://www.farnell.com/datasheets/650988.pdf
	# https://www.distrelec.biz/Web/Downloads/_t/ds/tn10_eng_tds.pdf
	# https://mm.digikey.com/Volume0/opasdata/d220001/medias/docus/2598/TX10-6-4-4C65%20.pdf
	@info "Imported toroid properties."

	wire_list = Dict([ # in format material => electrical resistivity, wire mass density, insulation mass density, ε_r (permittivity of insulator)
		("Cu", [17.1u"nΩ * m", 8930u"kg/m^3", 1200u"kg/m^3", 3u"F/m"]),
		("Al", [27.9u"nΩ * m", 2700u"kg/m^3", 1200u"kg/m^3", 3u"F/m"]),
		("HTCCA", [27.8u"nΩ * m", 3630u"kg/m^3", 1200u"kg/m^3", 3u"F/m"])
	]); # this is in nΩ * m for resisitvity, and kg/m^3 for density
	# Note: insulation density of 1200 kg/m^3 is valid for P155, PN155, P180, and E180
	# https://www.elektrisola.com/conductor-materials/aluminum-copper-clad-aluminum/aluminum.html
	awg_df = try
	CSV.File("lookup/awg.csv"; header=true, delim=',', types=Float64) |> DataFrame;
	catch
		@warn "No awg.csv file."
	end
	@info "Imported wire properties."

	const C_jfet = C_jfet_unitless * 1u"pF" #pF, from https://www.mouser.com/datasheet/2/676/jfet_if1320_interfet-2888025.pdf
	C_in = C_jfet/num_jfets
	e_ba = e_ba_unitless*1u"nV/sqrt(Hz)"
	i_ba = i_ba_unitless*1u"pA/sqrt(Hz)"
	@info "Imported jfet properties."
	
	R_in = R_in_unitless*1u"kΩ"
	const R_cr = R_cr_unitless * 1u"kΩ"
	@info "Imported circuit properties."
end	

# ╔═╡ 1322f57c-93ff-4c5d-9980-30fd01d5a4d3
"""
Returns the toroid dimensions and specific inductance.

### Examples
```julia-repl
julia> OD_tor, ID_tor, H_tor, chamfer, A_l, μ_i = get_toroid_properties("TN10/6/4-4A11")
[10.6±0.3 mm, 5.2±0.3 mm, 0.1±0.0 mm, 4.4±0.3 mm, 348.0±87.0 nH, 700.0±140.0 H m⁻¹]
```
"""
function get_toroid_properties(toroid_type::String)
	return get(toroid_list, toroid_type, ~)
end

# ╔═╡ f86e3141-2161-4dec-ab51-15612e30bc70
"""
Returns the electrical resistivity, wire mass density, insulation mass density, ε_r (permittivity of insulator).

### Examples
```julia-repl
julia> wire_ρr, wire_ρm, insulation_ρm, ε_r = get_wire_properties("Cu")
[17.1 m nΩ, 8930.0 kg m⁻³, 1200.0 kg m⁻³, 3.0 F m⁻¹]
```
"""
function get_wire_properties(wire_type::String)
	return get(wire_list, wire_type, ~)
end

# ╔═╡ b09a2088-a56a-4479-82ec-995e5cdf27f4
"""
Returns the conductor diameter d_w and insulation thickness t given AWG. Returns nothing if invalid gauge.

### Examples
```julia-repl
julia> d_w, d_total, t = get_diameters_from_awg(32)
(0.203±0.003 mm, 0.231 mm, 0.028±0.003 mm)

julia> d_w, d_total, t = get_diameters_from_awg(22)
(nothing, nothing, nothing)
Warning: Not a valid gauge.
```
"""
function get_diameters_from_awg(awg)
	index = findfirst(x->x==awg, awg_df.awg)
	if isnothing(index)
		@warn "Not a valid gauge."
		return nothing, nothing
	end
	d_w = awg_df.:"conductor diameter"[index][1]u"mm" ± awg_df.:"conductor error"[index][1]u"mm"
	d_total = awg_df.:"total diameter"[index][1]u"mm"
	t = d_total-d_w
	return d_w, d_total, t 
end

# ╔═╡ a17830f1-6c78-46c4-81d5-b26867b1ad31
begin
	d_w, d_total, t = get_diameters_from_awg(gauge)
	wire_ρr, wire_ρm, insulation_ρm, ε_r = get_wire_properties("Cu")
	OD_tor, ID_tor, H_tor, chamfer, A_l, μ_i = get_toroid_properties(toroid_type)
	
	N_max = max_turns_per_toroid(ID_tor, d_total)
	@info "Max number of turns $toroid_type can support is $N_max turns."
	
	l_t = margin*2*((OD_tor - ID_tor - 2*chamfer) + (H_tor - 2*chamfer) + pi*chamfer) # m, turn length
	L_tw = num_toroids*N_turns*l_t |> u"m"# m, total wire length
	@info "$N_turns turns will use $L_tw of $gauge AWG wire w/ $(round(100*(margin-1)))% margin."
	S_w = π * (d_w/2)^2 |> u"mm^2" # mm^2, Wire cross sectional area
	ρ = wire_ρr / S_w |> u"Ω/m" # Ω/m, wire resistivity
	r_s = (L_tw * ρ) |> u"Ω" # total resistance from windings (Ω = kg m^2/s^3 A^2)
	@info "Total winding resisitance: $r_s"
	L = A_l * N_turns^2 |> u"mH"
	@info "Toroid Inductance: $L"

	flux_tor = pi*(OD_tor-ID_tor)^2*pi*(OD_tor+ID_tor) * μ_i / (2 * pi * (OD_tor+ID_tor)/2) |> u"nT*m^3/A"
	@info "flux/I in toroid: $flux_tor" 

	F_res = get_resonant_frequency(A_l, N_turns, C_jfet/num_jfets)
	@info "Resonant frequency will be centered at $F_res."
	
	# N_res = upreferred(turns_from_freq(100u"kHz", 10u"MHz", num_toroids, A_l, C_jfet, num_jfets))
	# @info "Resonant frequency will be centered at $N_res."
	
	e_bt = sqrt(4*k*T*r_s) |> u"nV/sqrt(Hz)" # wound toroid johnson nyquist noise in units of nV/sqrt(Hz)
	@info "Johnson-nyquist noise of wound toroid e_bt: $e_bt"

	e_bR = sqrt(4*k*T*R_in) |> u"nV/sqrt(Hz)" # biasing circuit johnson nyquist noise in units of nV/sqrt(Hz)
	@info "Johnson-nyquist noise of biasing circuit e_bR: $e_bR"
end

# ╔═╡ d63a6833-c113-4511-be9c-6b01514b1f57
md"
## Electrokinetic Modelling
### Transfer Function
In order to properly model the high freuqency loop, there are a few key components to simulate:
 1. the primary loop ($M$)
 2. the toroids ($H_m$)
 3. the preamplifier ($H_a$)
 4. the feedback loop resistance ($Y_{cr}$)

#### Transfer Function Equations

The general equation looks like this:

$\frac{V_s}{B_0} = \frac{
MH
}{
1 - H Y_{cr}
}$

with

$M = \frac{i_b}{B_0}\text{,}\quad H = H_m H_a = \frac{V_e}{i}\frac{V_s}{V_e}=\frac{V_s}{i}\text{,}\quad Y_{cr} = \frac{i_{cr}}{V_s}$

where $V_s$ is the output voltage of the whole thing and $B_0$ is the field to be measured.

So, M is:

$M = \frac{i_b}{B_0} = \frac{
-j\omega S
}{
r_b + j\omega(L_0+A_l)
}$

with $r_b$ and $S$ being the resisitance and surface of the coil, respectively. H is:

$H = \frac{
-j \omega A_l N
}{
1 + \frac{r_s}{R_{in}} - (\omega^2 A_l N^2 C_{in}) + j\omega[(\frac{A_lN^2}{R_{in}})+r_s C_{in}]
}H_a$

with $r_s$ and $R_{in}$ being the winding resisitance and amplifier input resisitance.

The amplifier transfer function $H_a$ is...

And finally, $Y_{cr}$ is just inverse of feedback resistance $1/R_{cr}$, which is on the order of a couple kΩ.

In the frequency range of interest $F_0 \sim 10e6$, $HY_{cr}>>1$, so we can simplify:

$\frac{V_s}{B_0} = \frac{M}{Y_{cr}} = \frac{j\omega S R_{cr}}{r_b + j\omega(L_0 + A_l)} \approx \frac{S R_{cr}}{L_0}$

meaning that the efficiency of our loop is primarily dependent on surface area of primary loop, feedback resistance, and self inductance of the toroids.


However, this has no frequency dependence, which is weird to me, so let's actually derive the proper real component of the equation. The form is:

$\text{re}\Bigg[\frac{iA}{B+iC}\Bigg] = \frac{AC}{B^2 + C^2}$

where, for $\frac{V_s}{B_0}$:

$A =  S R_{cr} \omega,\quad B =  r_{b} ,\quad C =  (L_0+A_l)\omega$

and, for $M$:

$A =  S \omega,\quad B =  r_{b} ,\quad C =  (L_0+A_l)\omega$

and, for $H$:

$A =  -A_l N H_a \omega,\quad B =  1 + \frac{r_s}{R_{in}} - (\omega^2 A_l N^2 C_{in}) ,\quad C =  \Bigg[\frac{A_lN^2}{R_{in}} r_s C_{in}\Bigg]\omega$

#### Transfer Function Functions
"

# ╔═╡ 6f0539b1-a46c-4df7-a8e2-9982bd929288
find_real(A, B, C) = A * C / ( B^2 + C^2 )

# ╔═╡ e18ca91f-0d7c-4799-bd44-bcf768cb3ddd
M(ω) = find_real(
	S*ω,
	r_b,
	(L_0 + A_l) * ω) |> u"A/T"

# ╔═╡ 92f0a942-e5fa-4bdf-aa65-b6e07b1a63b7
Y_cr = 1/R_cr |> u"kΩ^-1"

# ╔═╡ a8959b07-e857-4144-99b2-431a68faf22b
H_a = dBV2gain(40)

# ╔═╡ 9caf6df9-bac8-4ab6-ad8d-a7d578a107aa
H(ω) = find_real(
	-num_toroids * A_l * N_turns * H_a * ω, # this makes sense, it's the inductance / N 
	1 + (r_s/R_in) - (num_toroids * A_l * N_turns^2 * C_in * ω^2),
	((num_toroids * A_l*N_turns^2/R_in) + (r_s*C_in))*ω
) |> u"kΩ"

# ╔═╡ 91a2d5c9-aad9-433f-9cea-6b89f007379d
H(1000u"kHz")

# ╔═╡ 490b91ba-4d2f-4c7f-abd5-7ea64b834178
TF(ω) = abs((M(ω)*H(ω)) / (1-(H(ω)*Y_cr))) |> u"V/nT"

# ╔═╡ 40ab265a-8584-462f-9095-a58cbd6bc2a8
TF2(ω) = find_real(
	S*R_cr*ω,
	r_b,
	(L_0 + A_l) * ω
) |> u"V/nT"

# ╔═╡ ab778fd6-2057-4426-9b71-00974270ba02
TF2(10u"kHz")

# ╔═╡ bab15754-71d0-4f2b-b1e5-eb34e6519aed
begin
	temp_x = logrange(0.1,1000,100)*1u"MHz"
	plot(temp_x, TF.(temp_x), xscale=:log10, yscale=:log10, legend=false, xlim=(0.3, 100), ylim=(0.001,0.1), size = (1000,600), minorticks=true, left_margin = 6mm)
	p1 = plot!(title="Simulated Transfer Function")
	p1 = plot!(p1, xtickfontsize=12, ytickfontsize=12, xguidefontsize=16, yguidefontsize=16, legendfontsize=10, titlefontsize=16)
	# savefig(p1, "Simulated Transfer Function.png")
end

# ╔═╡ d86f77a0-6d4b-4bac-a383-3fca16e0fc23
	plot(temp_x, H.(temp_x), xscale =:log10, legend=false, xlim=(0.3, 100), size = (1000,600), minorticks=true)

# ╔═╡ c702b936-d809-4235-9d11-29e619d31d37
md"
### Modelling Noise

Assume no B input, so add a new noise contributor in system.

#### Noise Equations

Voltage noise from toroids:

$v_{b1} = \frac{e_{bt}}
{ 1 + \frac{A}{R_{in}} - (2 \pi f)^2 C_{in} A_l N_{turns}^2 }$

where:

$A = 2 \pi f A_l N_{turns}^2$

Voltage noise from biasing circuit:

$v_{b2} = \frac{e_{bR}}
{ 1 + \frac{R_{in}}{A}}$

Amplfier current noise:

$v_{b3} = \frac{i_{bA}}
{ \frac{1}{R_{in}} + \frac{1}{A}}$

Amplfier voltage noise:

$v_{b4} = e_{ba}$

#### Noise Equation Functions
"

# ╔═╡ b4ed3094-ba79-4e3e-ab69-96fa6462d07c
A(f) = 2*pi*f*A_l*N_turns^2 |> u"Ω"

# ╔═╡ c2691c78-c918-432a-a28c-2c7d840558ed
v_b1(f) = e_bt / ( 1 + (A(f)/R_in) - (2*pi*f)^2*C_in*A_l*N_turns^2 ) |> u"nV/sqrt(Hz)"

# ╔═╡ 44d0685c-cf1c-4227-89a2-80a1efc389af
v_b2(f) = e_bR / ( 1 + (R_in/A(f)) ) |> u"nV/sqrt(Hz)"

# ╔═╡ 6beab4d1-453a-4aee-bbd1-4cc524f9eedb
v_b3(f) = i_ba / ((1/R_in) + 1/A(f)) |> u"nV/sqrt(Hz)"

# ╔═╡ e1dba096-8eb8-4757-9590-c97d53bd2d5a
v_b4(f) = e_ba

# ╔═╡ 8676533e-169d-4395-867b-297d3fd2768f
v_b(f) = sqrt(v_b1(f)^2 + v_b2(f)^2 + v_b3(f)^2 + v_b4(f)^2)

# ╔═╡ 4c5d1444-811b-4ca2-b97b-154787335cdc
begin
	@info A(1u"MHz")
	@info (2*pi*1u"MHz")^2*(C_jfet/num_jfets)*A_l*N_turns^2 |> NoUnits
	@info v_b1(1u"MHz")
	@info v_b2(1u"MHz")
	@info v_b3(1u"MHz")
	@info v_b4(1u"MHz")
	@info v_b(1u"MHz")
end

# ╔═╡ 92c0b43e-e2c8-4009-a5bb-973eba87427f
md"""
## Plots
Plot Theme: $(@bind plot_theme Select([
:default => "Default",
:bright => "Bright",
:vibrant => "Vibrant",
:sand => "Sand",
:solarized_light => "Solarized Light",
:solarized => "Solarized",
:juno => "Juno",
:dark => "Dark",
:dracula => "Dracula"], default=:juno))
"""

# ╔═╡ b2ebf5ab-f318-4f56-a14d-c91f9e1d1ff2
"""
Takes a list of functions to plot as well the frequency range (in proper units), and formats the data in a way that can be plotted using the errorline function from StatsPlots. Provide a list of labels for the plot, as well as colors. 

### Examples
```julia-repl
julia> system_noise_error_plot(
	[v_b1, v_b2, v_b3, v_b4, v_b],
	[x*1u"MHz" for x in logrange(0.1,10,1000)],
	[
		"v_b1, noise from toroids",
		"v_b2, noise from biasing circuit",
		"v_b3, noise from amplifier current",
		"v_b4, noise from amplifier voltage",
		"v_b, total noise"
	],
	[
		:blue,
		:orange,
		:green,
		:purple,
		:red
	]
)
```
"""
function system_noise_error_plot(f_list, range, label_list, color_list)
	theme(plot_theme)
	p = plot(errorstyle=:ribbon, legend=:outerbottom, title="System Noise Contributors", xlabel="Frequency [MHz]", ylabel = "Voltage Noise [V/sqrt(Hz)]", xscale=:log10, yscale=:log10, xminorticks=10, yminorticks=10, dpi=500, size = (1000,900), left_margin = 20px, titlefontsize=24, xlabelfontsize=18, ylabelfontsize=18, xtickfontsize=12, ytickfontsize=12, legendfontsize=12)
	for i in eachindex(f_list)
		y = ustrip.(Measurements.value.(f_list[i].(range)))
		dy = ustrip.(Measurements.uncertainty.(f_list[i].(range)))
		y_matrix = 1e-9.*[y+dy y-dy]'
		p = errorline!(ustrip.(range), y_matrix, label=label_list[i], errorstyle=:ribbon, linewidth = 3)
		# temporary fix for errorline pallette bug:
		# https://github.com/JuliaPlots/StatsPlots.jl/pull/524
		p[1][i][:linecolor] = color_list[i]
		p[1][i][:fillcolor] = color_list[i]
	end	
	return p
end

# ╔═╡ 4aaa1f90-93a0-4788-a14b-49f7f4f7f3c5
begin
	p2 = system_noise_error_plot(
		[v_b1, v_b2, v_b3, v_b4, v_b],
		[x*1u"MHz" for x in logrange(0.1,10,1000)],
		[
			"v_b1, noise from toroids",
			"v_b2, noise from biasing circuit",
			"v_b3, noise from amplifier current",
			"v_b4, noise from amplifier voltage",
			"v_b, total noise"
		],
		[
			:blue,
			:orange,
			:green,
			:purple,
			:red
		]
	)
	
	# savefig(p2, "noise_plot.png")
end

# ╔═╡ 602199e4-9c56-431c-aa84-d629a099c702
begin
	frequency_range = [x*1u"MHz" for x in logrange(0.05,20,100)]
	plot(frequency_range, TF.(frequency_range), 
		xrange = (0.01, 1000), yminorticks=10, xminorticks=10, xscale=:log10, yscale=:log10, title = "Transfer Function", size = (1000,600), minorticks=true)
end

# ╔═╡ 9777f399-0ee3-40c3-b023-65cf04b71734
md"""
## Measured Values

Loop Current Measurement CSV: $(@bind loop_current_csv_name Select(readdir("data/")[findall(x->x[(end-3):end] == ".csv", readdir("data/"))], default = "Loop current measurement EElab.csv"))

Gain CSV Name 1: $(@bind gain_csv_name_1 Select(readdir("data/")[findall(x->x[(end-3):end] == ".csv", readdir("data/"))], default = "TM7 EElab Gain shield can.csv"))

Noise CSV Name 1: $(@bind noise_csv_name_1 Select(readdir("data/")[findall(x->x[(end-3):end] == ".csv", readdir("data/"))], default = "TM7 EElab noise shield can.csv"))

Gain CSV Name 2: $(@bind gain_csv_name_2 Select(readdir("data/")[findall(x->x[(end-3):end] == ".csv", readdir("data/"))], default = "TM8 EElab Gain shield can.csv"))

Noise CSV Name 2: $(@bind noise_csv_name_2 Select(readdir("data/")[findall(x->x[(end-3):end] == ".csv", readdir("data/"))], default = "TM8 EElab noise shield can.csv"))

CNRS Gain CSV Name 1: $(@bind cnrs_gain_csv_name_1 Select(readdir("data/")[findall(x->x[(end-3):end] == ".csv", readdir("data/"))], default = "TM7_CNRS_TF_gain.csv"))

CNRS Driver Gain CSV Name 1: $(@bind cnrs_gain_driver_csv_name_1 Select(readdir("data/")[findall(x->x[(end-3):end] == ".csv", readdir("data/"))], default = "TM7_CNRS_driver_TF_gain.csv"))

CNRS Noise CSV Name 1: $(@bind cnrs_noise_csv_name_1 Select(readdir("data/")[findall(x->x[(end-3):end] == ".csv", readdir("data/"))], default = "test_csv_noise.csv"))

CNRS Gain CSV Name 2: $(@bind cnrs_gain_csv_name_2 Select(readdir("data/")[findall(x->x[(end-3):end] == ".csv", readdir("data/"))], default = "TM8_CNRS_TF_gain.csv"))

CNRS Driver Gain CSV Name 2: $(@bind cnrs_gain_driver_csv_name_2 Select(readdir("data/")[findall(x->x[(end-3):end] == ".csv", readdir("data/"))], default = "TM8_CNRS_driver_TF_gain.csv"))

CNRS Noise CSV Name 2: $(@bind cnrs_noise_csv_name_2 Select(readdir("data/")[findall(x->x[(end-3):end] == ".csv", readdir("data/"))], default = "test_csv_noise.csv"))



System Impedance: $(@bind impedance_Ohm_unitless NumberField(0.01:0.01:1000, default=50)) Ω

R\_shunt: $(@bind R_shunt_unitless NumberField(0.01:0.01:50, default=1)) Ω

Driver loop distance: $(@bind z_distance_unitless NumberField(0.01:0.01:1000, default=15)) mm

Moving Average: $(@bind moving_avg Slider(0:2:20; default=4, show_value=true))
"""

# ╔═╡ 44ed1931-2f74-4dfe-808d-3a5941dde05e
md"""
## Driver Loop Design

Since direct meausrement of B_0 is not possible, we measure the voltage across the shunt resistor for the driver loop in order to obtain the transfer function.

The transfer function equation is as follows:

$\frac{V_s}{B_0} = \alpha \cdot \frac{V_s}{V_{shunt}}$

where $\alpha$ is a the conversion from V to nT. The B field of a loop with radius R, given at point that is at a point that is Z away from the center of the loop is given by Biot-Savart:

$B_0 = \frac{\mu_0 \cdot I_{loop}}{2R} \frac{R^3}{(Z^2+R^2)^{3/2}} = \frac{\mu_0 \cdot V_{shunt} / R_{shunt}}{2R} \frac{R^3}{(Z^2+R^2)^{3/2}}$

So, if we can measure the shunt voltage and the output signal, then all we need is

$\alpha = \frac{2  R_{shunt} (Z^2+R^2)^{3/2}}{\mu_0 R^2}$

to convert between V and nT.

"""

# ╔═╡ 0e18a6ec-a252-4fbf-ba0b-40d92ff3767f
begin
	impedance_Ohm = impedance_Ohm_unitless * 1u"Ω"; #Ω
	R_shunt = R_shunt_unitless * 1u"Ω"; #Ω
	z_distance = z_distance_unitless  * 1u"mm"; #mm
	V2nT = R_shunt * 2 * (z_distance^2+r_loop^2)^(3/2) / ((4*pi*10^-7)*1u"N/A^2" * r_loop^2 ) |> u"V/nT"
	cnrs_driver_gain = 216u"nT/V"; #nT/V
	
	function dBm_to_Vpp(dBm)
	    # Convert dBm to Watts
	    power_W = 10 ^ ((dBm - 30) / 10)  * 1u"W"
	    # Convert power (W) to voltage (V)
	    voltage_V = sqrt(power_W * impedance_Ohm);
	    # Obtain peak to peak voltage
	    Vpp = voltage_V * 2 * sqrt(2)
	    return Vpp |> u"V"
	end

	function dB_to_V_ratio(dB)
	    # Convert dB to voltage ratio
	    V_ratio = 10 ^ (dB / 20)
	    return V_ratio
	end
	
	df0 = CSV.read("data/$loop_current_csv_name", DataFrame);
	
	df1_gain = CSV.read("data/$gain_csv_name_1", DataFrame);
	df1_noise = CSV.read("data/$noise_csv_name_1", DataFrame);

	df2_gain = CSV.read("data/$gain_csv_name_2", DataFrame);
	df2_noise = CSV.read("data/$noise_csv_name_2", DataFrame);

	cnrs_df1_gain = CSV.read("data/$cnrs_gain_csv_name_1", DataFrame);
	cnrs_df1_noise = CSV.read("data/$cnrs_noise_csv_name_1", DataFrame);
	
	cnrs_df2_gain = CSV.read("data/$cnrs_gain_csv_name_2", DataFrame);
	cnrs_df2_noise = CSV.read("data/$cnrs_noise_csv_name_2", DataFrame);

	cnrs_df1_gain_driver = CSV.read("data/$cnrs_gain_driver_csv_name_1", DataFrame);
	cnrs_df2_gain_driver = CSV.read("data/$cnrs_gain_driver_csv_name_2", DataFrame);

	
	f = df1_gain[:,1] .* 1e-6u"MHz";
	in_Vpp = dBm_to_Vpp.(df0[:,2]);
	out_Vpp_1 = dBm_to_Vpp.(df1_gain[:,2]);
	noise_Vpp_1 = dBm_to_Vpp.(df1_noise[:,2]);
	out_Vpp_2 = dBm_to_Vpp.(df2_gain[:,2]);
	noise_Vpp_2 = dBm_to_Vpp.(df2_noise[:,2]);
	cnrs_f = cnrs_df1_gain[:,1] .* 1e-6u"MHz";
	cnrs_gain_1 = dB_to_V_ratio.(cnrs_df1_gain[:,2]);
	cnrs_gain_2 = dB_to_V_ratio.(cnrs_df2_gain[:,2]);
	cnrs_gain_driver_1 = dB_to_V_ratio.(cnrs_df1_gain_driver[:,2]);
	cnrs_gain_driver_2 = dB_to_V_ratio.(cnrs_df2_gain_driver[:,2]);

	T1 = out_Vpp_1 .* V2nT ./ in_Vpp;
	T2 = out_Vpp_2 .* V2nT ./ in_Vpp;	
	CNRS_T1 = cnrs_gain_1 .* V2nT;
	CNRS_T2 = cnrs_gain_2 .* V2nT;
	CNRS_driver_T1 = cnrs_gain_driver_1 ./ cnrs_driver_gain;
	CNRS_driver_T2 = cnrs_gain_driver_2 ./ cnrs_driver_gain;

	NEMI1 = @. noise_Vpp_1 / T1 / sqrt(f) |> u"nT/sqrt(Hz)"
	NEMI2 = @. noise_Vpp_2 / T2 / sqrt(f) |> u"nT/sqrt(Hz)"
	
	NEMI1_avg = rollmean(NEMI1, moving_avg)
	NEMI2_avg = rollmean(NEMI2, moving_avg)

	T1_avg = rollmean(T1, moving_avg)
	T2_avg = rollmean(T2, moving_avg)
	CNRS_T1_avg = rollmean(CNRS_T1, moving_avg)
	CNRS_T2_avg = rollmean(CNRS_T2, moving_avg)
	CNRS_driver_T1_avg = rollmean(CNRS_driver_T1, moving_avg)
	CNRS_driver_T2_avg = rollmean(CNRS_driver_T2, moving_avg)
	
end

# ╔═╡ 424eb2fd-5fa7-46f2-85e7-75db773eed1d
# ╠═╡ disabled = true
#=╠═╡
begin
	scatter([f, cnrs_f, cnrs_f], ustrip.([T2, CNRS_T2, CNRS_driver_T2]),
		label=false,xscale=:log10, yscale=:log10, xlim=(.01,100), ylim = (.01,1),
		minorticks=true,  markersize=1, markerstrokewidth=0, color = [et_orange et_blue et_green])
	
	p6 = plot!([f[(moving_avg÷2):end-moving_avg÷2], cnrs_f[(moving_avg÷2):end-moving_avg÷2, cnrs_f[(moving_avg÷2):end-moving_avg÷2]], cnrs_f[(moving_avg÷2):end-moving_avg÷2, cnrs_f[(moving_avg÷2):end-moving_avg÷2]]],
		[T2_avg, CNRS_T2_avg, CNRS_driver_T2_avg],
		label = ["UCLA_"*noise_csv_name_2[1:3] "CNRS_"*cnrs_gain_csv_name_2[1:3]],
		title="CNRS Transfer Function Plots", color = [et_orange et_blue])
	
	p6 = plot!(p6, xtickfontsize=12, ytickfontsize=12, xguidefontsize=16, yguidefontsize=16, legendfontsize=10, titlefontsize=16, left_margin = 6mm, bottom_margin = 6mm, size = (1000,600))
	# savefig(p5, "ucla_cnrs_freq_response_tm8.png")
end
  ╠═╡ =#

# ╔═╡ 8043725d-dddf-48d3-9ee8-e4dc36a9f79f
html"""<style>
main {
    max-width: 1200px;
}
"""

# ╔═╡ ba4ac1cc-0e7a-44bf-86a6-003532275ac4
begin
	struct TwoColumn{L, R}
	    left::L
	    right::R
	end
	
	function Base.show(io, mime::MIME"text/html", tc::TwoColumn)
	    write(io, """<div style="display: flex;"><div style="flex: 50%;">""")
	    show(io, mime, tc.left)
	    write(io, """</div><div style="flex: 50%;">""")
	    show(io, mime, tc.right)
	    write(io, """</div></div>""")
	end
end

# ╔═╡ a95db3bc-2999-45f7-84b1-6c33ef4d2366
begin
	plotly()
	
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
	
	ethans_colors = [et_red, et_green, et_blue, et_purple, et_orange, et_light_blue, et_purplish_pink, et_reddish_orange];
end

# ╔═╡ eaf0530e-8250-438a-93cb-d5413384d243
begin
	scatter(f, ustrip.([T1, T2]), xscale=:log10, yscale=:log10, xlim=(.3,50), ylim = (.001,1), minorticks=true,  markersize=1, markerstrokewidth=0, label = [gain_csv_name_1[1:3] gain_csv_name_2[1:3]], color = [et_orange et_blue],size = (1000,600))
	p4 = plot!(title="TM7 (50 turns) and TM8 (40 turns) Transfer Function")
	p4 = plot!(p4, xtickfontsize=12, ytickfontsize=12, xguidefontsize=16, yguidefontsize=16, legendfontsize=10, titlefontsize=16, left_margin = 6mm, bottom_margin = 6mm)
	# savefig(p4, "measured_transfer_function_tm7tm8.png")
end

# ╔═╡ 82f94f15-00c0-494b-a6fd-66b1b31f7862
begin
	scatter(f, [NEMI1, NEMI2], color = [et_orange et_blue], xscale=:log10, yscale=:log10, minorticks=true,  markersize=1, markeralpha=.7, markerstrokewidth=0, label=false, legend=:topleft, ylim=(1e-8,1e-4))
	plot!(f[(moving_avg÷2):end-moving_avg÷2], [NEMI1_avg, NEMI2_avg], label = [noise_csv_name_1[1:3] noise_csv_name_2[1:3]], color = [et_orange et_blue], xlim = (0.3,50), size = (1000,600))
	p3 = plot!(title="TM7 (50 turns) and TM8 (40 turns) Noise Floor")
	p3 = plot!(p3, xtickfontsize=12, ytickfontsize=12, xguidefontsize=16, yguidefontsize=16, legendfontsize=10, titlefontsize=16, left_margin = 6mm, bottom_margin = 6mm)
	# savefig(p3, "measured_noise_floor_tm7tm8.png")
end

# ╔═╡ ffd7b8db-d8d8-41a1-abd6-4a04be7016c1
begin
	scatter([f, cnrs_f], ustrip.([T1, CNRS_T1]),
		label=false,xscale=:log10, yscale=:log10, xlim=(.01,100), ylim = (.001,1),
		minorticks=true,  markersize=[1 0.5], markerstrokewidth=0, color = [et_orange et_blue])
	
	p5 = plot!([f[(moving_avg÷2):end-moving_avg÷2], cnrs_f[(moving_avg÷2):end-moving_avg÷2]],
		ustrip.([T1_avg, CNRS_T1_avg]),
		label = ["UCLA_"*noise_csv_name_1[1:3] "CNRS_"*cnrs_gain_csv_name_1[1:3]],
		title="UCLA/CNRS Transfer Function Plots", color = [et_orange et_blue], ylabel="V/nT")
	
	p5 = plot!(p5, xtickfontsize=12, ytickfontsize=12, xguidefontsize=16, yguidefontsize=16, legendfontsize=10, titlefontsize=16, left_margin = -20mm, right_margin=20mm, bottom_margin = 6mm, size = (1100,600), legend=:right)
	# savefig(p5, "ucla_cnrs_freq_response_tm7.png")
end

# ╔═╡ 5257047a-054a-4944-a3bb-417470cd30e2
begin
	scatter([f, cnrs_f, cnrs_f], ustrip.([T2, CNRS_T2, CNRS_driver_T2]),
		label=false,xscale=:log10, yscale=:log10, xlim=(.01,100), ylim = (.01,1),
		minorticks=true,  markersize=1, markerstrokewidth=0, color = [et_orange et_blue et_green])
	
	p6 = plot!([f[(moving_avg÷2):end-moving_avg÷2], cnrs_f[(moving_avg÷2):end-moving_avg÷2], cnrs_f[(moving_avg÷2):end-moving_avg÷2]],
		ustrip.([T2_avg, CNRS_T2_avg, CNRS_driver_T2_avg]),
		label = ["UCLA_"*noise_csv_name_2[1:3] "CNRS_"*cnrs_gain_csv_name_2[1:3] "CNRS_driver_"*cnrs_gain_driver_csv_name_2[1:3]],
		title="CNRS Transfer Function Plots", color = [et_orange et_blue et_green])
	
	p6 = plot!(p6, xtickfontsize=12, ytickfontsize=12, xguidefontsize=16, yguidefontsize=16, legendfontsize=10, titlefontsize=16, left_margin = 6mm, bottom_margin = 6mm, size = (1000,600))
	# savefig(p6, "ucla_cnrs_freq_response_tm8.png")
end

# ╔═╡ cc0fe7f4-825c-4e63-91d8-77171b43f92c
begin
	tm7_cnrs_noise_csv_name = "202403_CNRS_noise_TM7.csv"
	tm8_cnrs_noise_csv_name = "202403_CNRS_noise_TM8.csv"
	lpc2e_cnrs_noise_csv_name = "202403_CNRS_noise_LPC2E.csv"
	
	tm7_cnrs_noise_df = CSV.read("data/$tm7_cnrs_noise_csv_name", DataFrame);
	tm8_cnrs_noise_df = CSV.read("data/$tm8_cnrs_noise_csv_name", DataFrame);
	lpc2e_cnrs_noise_df = CSV.read("data/$lpc2e_cnrs_noise_csv_name", DataFrame);

	cnrs_noise_index = 7

	cnrs_noise_f = tm7_cnrs_noise_df[:,1] .* 1e-6u"MHz";
	cnrs_noise = tm7_cnrs_noise_df[:,cnrs_noise_index] .* 1u"V/sqrt(Hz)"
	cnrs_noise_avg = rollmean(cnrs_noise, moving_avg)

	lpc2e_noise = tm8_cnrs_noise_df[:,2] .* 1u"V/sqrt(Hz)"
	lpc2e_noise_avg = rollmean(lpc2e_noise, moving_avg)
	
	thing = NEMI1./5
	thing_avg = rollmean(thing, moving_avg)

	cnrs_ucla_noise_compare = scatter([cnrs_noise_f, cnrs_noise_f], ustrip.([cnrs_noise, lpc2e_noise]),
		label=false,xscale=:log10, yscale=:log10, xlim=(.01,100), ylim = (1e-8,1e-5), ylabel = "V/sqrt(Hz)",
		minorticks=true,  markersize=[1 0.5 0.5], markerstrokewidth=0, color = [et_orange et_blue])

	cnrs_ucla_noise_compare = plot!([cnrs_noise_f[(moving_avg÷2):end-moving_avg÷2],
									 cnrs_noise_f[(moving_avg÷2):end-moving_avg÷2]],
									ustrip.([cnrs_noise_avg, lpc2e_noise_avg]),
									label = ["CNRS_TM7" "CNRS_CHARM"],
									title="UCLA/CNRS Noise Floor Comparison (r_cr = 3.1k, gate cap)", color = [et_orange et_blue])
	
	cnrs_ucla_noise_compare = plot!(cnrs_ucla_noise_compare, xtickfontsize=12, ytickfontsize=12, xguidefontsize=16, yguidefontsize=16, legendfontsize=10, titlefontsize=16, left_margin = -20mm, right_margin=20mm, bottom_margin = 6mm, size = (1100,600), legend=:topright)
	
	# savefig(cnrs_ucla_noise_compare, "ucla_cnrs_noise_floor_comparison.png")
	
end

# ╔═╡ de8f2990-6af3-4ea9-b138-182aa06c7e75
cnrs_noise_f[(moving_avg÷2):end-moving_avg÷2]

# ╔═╡ 07928111-006d-4fb1-a019-f3a4ec13f690


# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Measurements = "eff96d63-e80a-5855-80a2-b1b0885c5ab7"
Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
RollingFunctions = "b0e4dd01-7b14-53d8-9b45-175a3e362653"
StatsPlots = "f3b207a7-027a-5e70-b257-86293d7955fd"
Unitful = "1986cc42-f94f-5a68-af5c-568840ba703d"

[compat]
CSV = "~0.10.9"
DataFrames = "~1.5.0"
Measurements = "~2.8.0"
Plots = "~1.38.8"
PlutoUI = "~0.7.50"
RollingFunctions = "~0.8.0"
StatsPlots = "~0.15.4"
Unitful = "~1.12.4"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.9.4"
manifest_format = "2.0"
project_hash = "bde529183b9d60156ba245b6e4eb3811df09bcf7"

[[deps.AbstractFFTs]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "16b6dbc4cf7caee4e1e75c49485ec67b667098a0"
uuid = "621f4979-c628-5d54-868e-fcf4e3e8185c"
version = "1.3.1"
weakdeps = ["ChainRulesCore"]

    [deps.AbstractFFTs.extensions]
    AbstractFFTsChainRulesCoreExt = "ChainRulesCore"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "8eaf9f1b4921132a4cff3f36a1d9ba923b14a481"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.1.4"

[[deps.AccurateArithmetic]]
deps = ["LinearAlgebra", "Random", "VectorizationBase"]
git-tree-sha1 = "07af26e8d08c211ef85918f3e25d4c0990d20d70"
uuid = "22286c92-06ac-501d-9306-4abd417d9753"
version = "0.3.8"

[[deps.Adapt]]
deps = ["LinearAlgebra", "Requires"]
git-tree-sha1 = "cc37d689f599e8df4f464b2fa3870ff7db7492ef"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.6.1"
weakdeps = ["StaticArrays"]

    [deps.Adapt.extensions]
    AdaptStaticArraysExt = "StaticArrays"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.Arpack]]
deps = ["Arpack_jll", "Libdl", "LinearAlgebra", "Logging"]
git-tree-sha1 = "9b9b347613394885fd1c8c7729bfc60528faa436"
uuid = "7d9fca2a-8960-54d3-9f78-7d1dccf2cb97"
version = "0.5.4"

[[deps.Arpack_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "OpenBLAS_jll", "Pkg"]
git-tree-sha1 = "5ba6c757e8feccf03a1554dfaf3e26b3cfc7fd5e"
uuid = "68821587-b530-5797-8361-c406ea357684"
version = "3.5.1+1"

[[deps.ArrayInterface]]
deps = ["Adapt", "LinearAlgebra", "Requires", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "c5aeb516a84459e0318a02507d2261edad97eb75"
uuid = "4fba245c-0d91-5ea0-9b3e-6abc04ee57a9"
version = "7.7.1"

    [deps.ArrayInterface.extensions]
    ArrayInterfaceBandedMatricesExt = "BandedMatrices"
    ArrayInterfaceBlockBandedMatricesExt = "BlockBandedMatrices"
    ArrayInterfaceCUDAExt = "CUDA"
    ArrayInterfaceGPUArraysCoreExt = "GPUArraysCore"
    ArrayInterfaceStaticArraysCoreExt = "StaticArraysCore"
    ArrayInterfaceTrackerExt = "Tracker"

    [deps.ArrayInterface.weakdeps]
    BandedMatrices = "aae01518-5342-5314-be14-df237901396f"
    BlockBandedMatrices = "ffab5731-97b5-5995-9138-79e8c1846df0"
    CUDA = "052768ef-5323-5732-b1bb-66c8b64840ba"
    GPUArraysCore = "46192b85-c4d5-4398-a991-12ede77f4527"
    StaticArraysCore = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
    Tracker = "9f7883ad-71c0-57eb-9f7f-b5c9e6d3789c"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.AxisAlgorithms]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "WoodburyMatrices"]
git-tree-sha1 = "66771c8d21c8ff5e3a93379480a2307ac36863f7"
uuid = "13072b0f-2c55-5437-9ae7-d433b7a33950"
version = "1.0.1"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BitFlags]]
git-tree-sha1 = "43b1a4a8f797c1cddadf60499a8a077d4af2cd2d"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.7"

[[deps.BitTwiddlingConvenienceFunctions]]
deps = ["Static"]
git-tree-sha1 = "0c5f81f47bbbcf4aea7b2959135713459170798b"
uuid = "62783981-4cbd-42fc-bca8-16325de8dc4b"
version = "0.1.5"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[deps.CPUSummary]]
deps = ["CpuId", "IfElse", "PrecompileTools", "Static"]
git-tree-sha1 = "601f7e7b3d36f18790e2caf83a882d88e9b71ff1"
uuid = "2a0fbf3d-bb9c-48f3-b0a9-814d99fd7ab9"
version = "0.2.4"

[[deps.CSV]]
deps = ["CodecZlib", "Dates", "FilePathsBase", "InlineStrings", "Mmap", "Parsers", "PooledArrays", "SentinelArrays", "SnoopPrecompile", "Tables", "Unicode", "WeakRefStrings", "WorkerUtilities"]
git-tree-sha1 = "c700cce799b51c9045473de751e9319bdd1c6e94"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "0.10.9"

[[deps.Cairo_jll]]
deps = ["Artifacts", "Bzip2_jll", "CompilerSupportLibraries_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "JLLWrappers", "LZO_jll", "Libdl", "Pixman_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "4b859a208b2397a7a623a03449e4636bdb17bcf2"
uuid = "83423d85-b0ee-5818-9007-b63ccbeb887a"
version = "1.16.1+1"

[[deps.Calculus]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f641eb0a4f00c343bbc32346e1217b86f3ce9dad"
uuid = "49dc2e85-a5d0-5ad3-a950-438e2897f1b9"
version = "0.5.1"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "c6d890a52d2c4d55d326439580c3b8d0875a77d9"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.15.7"

[[deps.CloseOpenIntervals]]
deps = ["Static", "StaticArrayInterface"]
git-tree-sha1 = "70232f82ffaab9dc52585e0dd043b5e0c6b714f1"
uuid = "fb6a15b2-703c-40df-9091-08a04967cfa9"
version = "0.1.12"

[[deps.Clustering]]
deps = ["Distances", "LinearAlgebra", "NearestNeighbors", "Printf", "Random", "SparseArrays", "Statistics", "StatsBase"]
git-tree-sha1 = "64df3da1d2a26f4de23871cd1b6482bb68092bd5"
uuid = "aaaa29a8-35af-508c-8bc3-b662a17a0fe5"
version = "0.14.3"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "9c209fb7536406834aa938fb149964b985de6c83"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.1"

[[deps.ColorSchemes]]
deps = ["ColorTypes", "ColorVectorSpace", "Colors", "FixedPointNumbers", "Random", "SnoopPrecompile"]
git-tree-sha1 = "aa3edc8f8dea6cbfa176ee12f7c2fc82f0608ed3"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.20.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "eb7f0f8307f71fac7c606984ea5fb2817275d6e4"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.4"

[[deps.ColorVectorSpace]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "SpecialFunctions", "Statistics", "TensorCore"]
git-tree-sha1 = "600cc5508d66b78aae350f7accdb58763ac18589"
uuid = "c3611d14-8923-5661-9e6a-0046d554d3a4"
version = "0.9.10"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "fc08e5930ee9a4e03f84bfb5211cb54e7769758a"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.12.10"

[[deps.Compat]]
deps = ["UUIDs"]
git-tree-sha1 = "7a60c856b9fa189eb34f5f8a6f6b5529b7942957"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.6.1"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.0.5+0"

[[deps.ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "89a9db8d28102b094992472d333674bd1a83ce2a"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.5.1"

    [deps.ConstructionBase.extensions]
    IntervalSetsExt = "IntervalSets"
    StaticArraysExt = "StaticArrays"

    [deps.ConstructionBase.weakdeps]
    IntervalSets = "8197267c-284f-5f27-9208-e0e47529a953"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[[deps.Contour]]
git-tree-sha1 = "d05d9e7b7aedff4e5b51a029dced05cfb6125781"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.6.2"

[[deps.CpuId]]
deps = ["Markdown"]
git-tree-sha1 = "fcbb72b032692610bfbdb15018ac16a36cf2e406"
uuid = "adafc99b-e345-5852-983c-f28acb93d879"
version = "0.3.1"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DataAPI]]
git-tree-sha1 = "e8119c1a33d267e16108be441a287a6981ba1630"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.14.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "Future", "InlineStrings", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrettyTables", "Printf", "REPL", "Random", "Reexport", "SentinelArrays", "SnoopPrecompile", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "aa51303df86f8626a962fccb878430cdb0a97eee"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.5.0"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.DataValues]]
deps = ["DataValueInterfaces", "Dates"]
git-tree-sha1 = "d88a19299eba280a6d062e135a43f00323ae70bf"
uuid = "e7dc6d0d-1eca-5fa6-8ad6-5aecde8b7ea5"
version = "0.4.13"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
git-tree-sha1 = "9e2f36d3c96a820c678f2f1f1782582fcf685bae"
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"
version = "1.9.1"

[[deps.Distances]]
deps = ["LinearAlgebra", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "49eba9ad9f7ead780bfb7ee319f962c811c6d3b2"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.8"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.Distributions]]
deps = ["FillArrays", "LinearAlgebra", "PDMats", "Printf", "QuadGK", "Random", "SparseArrays", "SpecialFunctions", "Statistics", "StatsBase", "StatsFuns", "Test"]
git-tree-sha1 = "da9e1a9058f8d3eec3a8c9fe4faacfb89180066b"
uuid = "31c24e10-a181-5473-b8eb-7969acd0382f"
version = "0.25.86"

    [deps.Distributions.extensions]
    DistributionsChainRulesCoreExt = "ChainRulesCore"
    DistributionsDensityInterfaceExt = "DensityInterface"

    [deps.Distributions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    DensityInterface = "b429d917-457f-4dbc-8f4c-0cc954292b1d"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "2fb1e02f2b635d0845df5d7c167fec4dd739b00d"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.3"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.DualNumbers]]
deps = ["Calculus", "NaNMath", "SpecialFunctions"]
git-tree-sha1 = "5837a837389fccf076445fce071c8ddaea35a566"
uuid = "fa6b7ba4-c1ee-5f82-b5fc-ecf0adba8f74"
version = "0.6.8"

[[deps.EpollShim_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "8e9441ee83492030ace98f9789a654a6d0b1f643"
uuid = "2702e6a9-849d-5ed8-8c21-79e8b8f9ee43"
version = "0.0.20230411+0"

[[deps.Expat_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bad72f730e9e91c08d9427d5e8db95478a3c323d"
uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
version = "2.4.8+0"

[[deps.FFMPEG]]
deps = ["FFMPEG_jll"]
git-tree-sha1 = "b57e3acbe22f8484b4b5ff66a7499717fe1a9cc8"
uuid = "c87230d0-a227-11e9-1b43-d7ebe4e7570a"
version = "0.4.1"

[[deps.FFMPEG_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "JLLWrappers", "LAME_jll", "Libdl", "Ogg_jll", "OpenSSL_jll", "Opus_jll", "PCRE2_jll", "Pkg", "Zlib_jll", "libaom_jll", "libass_jll", "libfdk_aac_jll", "libvorbis_jll", "x264_jll", "x265_jll"]
git-tree-sha1 = "74faea50c1d007c85837327f6775bea60b5492dd"
uuid = "b22a6f82-2f65-5046-a5b2-351ab43fb4e5"
version = "4.4.2+2"

[[deps.FFTW]]
deps = ["AbstractFFTs", "FFTW_jll", "LinearAlgebra", "MKL_jll", "Preferences", "Reexport"]
git-tree-sha1 = "f9818144ce7c8c41edf5c4c179c684d92aa4d9fe"
uuid = "7a1cc6ca-52ef-59f5-83cd-3a7055c09341"
version = "1.6.0"

[[deps.FFTW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c6033cc3892d0ef5bb9cd29b7f2f0331ea5184ea"
uuid = "f5851436-0d7a-5f13-b9de-f02708fd171a"
version = "3.3.10+0"

[[deps.FastBroadcast]]
deps = ["ArrayInterface", "LinearAlgebra", "Polyester", "Static", "StaticArrayInterface", "StrideArraysCore"]
git-tree-sha1 = "a6e756a880fc419c8b41592010aebe6a5ce09136"
uuid = "7034ab61-46d4-4ed7-9d0f-46aef9175898"
version = "0.2.8"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "e27c4ebe80e8699540f2d6c805cc12203b614f12"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.20"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.FillArrays]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "Statistics"]
git-tree-sha1 = "d3ba08ab64bdfd27234d3f61956c966266757fe6"
uuid = "1a297f60-69ca-5386-bcde-b61e274b549b"
version = "0.13.7"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.Fontconfig_jll]]
deps = ["Artifacts", "Bzip2_jll", "Expat_jll", "FreeType2_jll", "JLLWrappers", "Libdl", "Libuuid_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "21efd19106a55620a188615da6d3d06cd7f6ee03"
uuid = "a3f928ae-7b40-5064-980b-68af3947d34b"
version = "2.13.93+0"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "87eb71354d8ec1a96d4a7636bd57a7347dde3ef9"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.10.4+0"

[[deps.FriBidi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "aa31987c2ba8704e23c6c8ba8a4f769d5d7e4f91"
uuid = "559328eb-81f9-559d-9380-de523a88c83c"
version = "1.0.10+0"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.GLFW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libglvnd_jll", "Pkg", "Xorg_libXcursor_jll", "Xorg_libXi_jll", "Xorg_libXinerama_jll", "Xorg_libXrandr_jll"]
git-tree-sha1 = "d972031d28c8c8d9d7b41a536ad7bb0c2579caca"
uuid = "0656b61e-2033-5cc2-a64a-77c0f6c09b89"
version = "3.3.8+0"

[[deps.GR]]
deps = ["Artifacts", "Base64", "DelimitedFiles", "Downloads", "GR_jll", "HTTP", "JSON", "Libdl", "LinearAlgebra", "Pkg", "Preferences", "Printf", "Random", "Serialization", "Sockets", "TOML", "Tar", "Test", "UUIDs", "p7zip_jll"]
git-tree-sha1 = "660b2ea2ec2b010bb02823c6d0ff6afd9bdc5c16"
uuid = "28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"
version = "0.71.7"

[[deps.GR_jll]]
deps = ["Artifacts", "Bzip2_jll", "Cairo_jll", "FFMPEG_jll", "Fontconfig_jll", "GLFW_jll", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "Pixman_jll", "Qt5Base_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "d5e1fd17ac7f3aa4c5287a61ee28d4f8b8e98873"
uuid = "d2c73de3-f751-5644-a686-071e5b155ba9"
version = "0.71.7+0"

[[deps.Gettext_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "9b02998aba7bf074d14de89f9d37ca24a1a0b046"
uuid = "78b55507-aeef-58d4-861c-77aaff3498b1"
version = "0.21.0+0"

[[deps.Glib_jll]]
deps = ["Artifacts", "Gettext_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Libiconv_jll", "Libmount_jll", "PCRE2_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "d3b3624125c1474292d0d8ed0f65554ac37ddb23"
uuid = "7746bdde-850d-59dc-9ae8-88ece973131d"
version = "2.74.0+2"

[[deps.Graphite2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "344bf40dcab1073aca04aa0df4fb092f920e4011"
uuid = "3b182d85-2403-5c21-9c21-1e1f0cc25472"
version = "1.3.14+0"

[[deps.Grisu]]
git-tree-sha1 = "53bb909d1151e57e2484c3d1b53e19552b887fb2"
uuid = "42e2da0e-8278-4e71-bc24-59509adca0fe"
version = "1.0.2"

[[deps.HTTP]]
deps = ["Base64", "CodecZlib", "Dates", "IniFile", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "37e4657cd56b11abe3d10cd4a1ec5fbdb4180263"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.7.4"

[[deps.HarfBuzz_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "Graphite2_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg"]
git-tree-sha1 = "129acf094d168394e80ee1dc4bc06ec835e510a3"
uuid = "2e76f6c2-a576-52d4-95c1-20adfe4de566"
version = "2.8.1+1"

[[deps.HostCPUFeatures]]
deps = ["BitTwiddlingConvenienceFunctions", "IfElse", "Libdl", "Static"]
git-tree-sha1 = "eb8fed28f4994600e29beef49744639d985a04b2"
uuid = "3e5b6fbb-0976-4d2c-9146-d79de83f2fb0"
version = "0.1.16"

[[deps.HypergeometricFunctions]]
deps = ["DualNumbers", "LinearAlgebra", "OpenLibm_jll", "SpecialFunctions", "Test"]
git-tree-sha1 = "709d864e3ed6e3545230601f94e11ebc65994641"
uuid = "34004b35-14d8-5ef3-9330-4cdb6864b03a"
version = "0.3.11"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "8d511d5b81240fc8e6802386302675bdf47737b9"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.4"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "c47c5fa4c5308f27ccaac35504858d8914e102f9"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.4"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

[[deps.IfElse]]
git-tree-sha1 = "debdd00ffef04665ccbb3e150747a77560e8fad1"
uuid = "615f187c-cbe4-4ef1-ba3b-2fcf58d6d173"
version = "0.1.1"

[[deps.IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[deps.InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "9cc2baf75c6d09f9da536ddf58eb2f29dedaf461"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.0"

[[deps.IntelOpenMP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "d979e54b71da82f3a65b62553da4fc3d18c9004c"
uuid = "1d5cc7b8-4909-519e-a0f8-d0f5ad9712d0"
version = "2018.0.3+2"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.Interpolations]]
deps = ["Adapt", "AxisAlgorithms", "ChainRulesCore", "LinearAlgebra", "OffsetArrays", "Random", "Ratios", "Requires", "SharedArrays", "SparseArrays", "StaticArrays", "WoodburyMatrices"]
git-tree-sha1 = "721ec2cf720536ad005cb38f50dbba7b02419a15"
uuid = "a98d9a8b-a2ab-59e6-89dd-64a1c18fca59"
version = "0.14.7"

[[deps.InvertedIndices]]
git-tree-sha1 = "82aec7a3dd64f4d9584659dc0b62ef7db2ef3e19"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.2.0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "630b497eafcc20001bba38a4651b327dcfc491d2"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.2"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLFzf]]
deps = ["Pipe", "REPL", "Random", "fzf_jll"]
git-tree-sha1 = "f377670cda23b6b7c1c0b3893e37451c5c1a2185"
uuid = "1019f520-868f-41f5-a6de-eb00f4b6a39c"
version = "0.1.5"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[deps.JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "6f2675ef130a300a112286de91973805fcc5ffbc"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "2.1.91+0"

[[deps.KahanSummation]]
git-tree-sha1 = "6292e7878fe190651e74148edb11356dbbc2e194"
uuid = "8e2b3108-d4c1-50be-a7a2-16352aec75c3"
version = "0.3.1"

[[deps.KernelDensity]]
deps = ["Distributions", "DocStringExtensions", "FFTW", "Interpolations", "StatsBase"]
git-tree-sha1 = "9816b296736292a80b9a3200eb7fbb57aaa3917a"
uuid = "5ab0869b-81aa-558d-bb23-cbf5423bbe9b"
version = "0.6.5"

[[deps.LAME_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f6250b16881adf048549549fba48b1161acdac8c"
uuid = "c1c5ebd0-6772-5130-a774-d5fcae4a789d"
version = "3.100.1+0"

[[deps.LERC_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bf36f528eec6634efc60d7ec062008f171071434"
uuid = "88015f11-f218-50d7-93a8-a6af411a945d"
version = "3.0.0+1"

[[deps.LZO_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e5b909bcf985c5e2605737d2ce278ed791b89be6"
uuid = "dd4b983a-f0e5-5f8d-a1b7-129d4a5fb1ac"
version = "2.10.1+0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "f2355693d6778a178ade15952b7ac47a4ff97996"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.0"

[[deps.Latexify]]
deps = ["Formatting", "InteractiveUtils", "LaTeXStrings", "MacroTools", "Markdown", "OrderedCollections", "Printf", "Requires"]
git-tree-sha1 = "2422f47b34d4b127720a18f86fa7b1aa2e141f29"
uuid = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
version = "0.15.18"

[[deps.LayoutPointers]]
deps = ["ArrayInterface", "LinearAlgebra", "ManualMemory", "SIMDTypes", "Static", "StaticArrayInterface"]
git-tree-sha1 = "62edfee3211981241b57ff1cedf4d74d79519277"
uuid = "10f19ff3-798f-405d-979b-55457f8fc047"
version = "0.1.15"

[[deps.LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.4.0+0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.0+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.Libffi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "0b4a5d71f3e5200a7dff793393e09dfc2d874290"
uuid = "e9f186c6-92d2-5b65-8a66-fee21dc1b490"
version = "3.2.2+1"

[[deps.Libgcrypt_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgpg_error_jll", "Pkg"]
git-tree-sha1 = "64613c82a59c120435c067c2b809fc61cf5166ae"
uuid = "d4300ac3-e22c-5743-9152-c294e39db1e4"
version = "1.8.7+0"

[[deps.Libglvnd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll", "Xorg_libXext_jll"]
git-tree-sha1 = "6f73d1dd803986947b2c750138528a999a6c7733"
uuid = "7e76a0d4-f3c7-5321-8279-8d96eeed0f29"
version = "1.6.0+0"

[[deps.Libgpg_error_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c333716e46366857753e273ce6a69ee0945a6db9"
uuid = "7add5ba3-2f88-524e-9cd5-f83b8a55f7b8"
version = "1.42.0+0"

[[deps.Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c7cb1f5d892775ba13767a87c7ada0b980ea0a71"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.16.1+2"

[[deps.Libmount_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c30530bf0effd46e15e0fdcf2b8636e78cbbd73"
uuid = "4b2f31a3-9ecc-558c-b454-b3730dcb73e9"
version = "2.35.0+0"

[[deps.Libtiff_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "LERC_jll", "Libdl", "Pkg", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "3eb79b0ca5764d4799c06699573fd8f533259713"
uuid = "89763e89-9b03-5906-acba-b20f662cd828"
version = "4.4.0+0"

[[deps.Libuuid_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "7f3efec06033682db852f8b3bc3c1d2b0a0ab066"
uuid = "38a345b3-de98-5d2b-a5d3-14cd9215e700"
version = "2.36.0+0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "0a1b7c2863e44523180fdb3146534e265a91870b"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.23"

    [deps.LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [deps.LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "cedb76b37bc5a6c702ade66be44f831fa23c681e"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "1.0.0"

[[deps.LoopVectorization]]
deps = ["ArrayInterface", "CPUSummary", "CloseOpenIntervals", "DocStringExtensions", "HostCPUFeatures", "IfElse", "LayoutPointers", "LinearAlgebra", "OffsetArrays", "PolyesterWeave", "PrecompileTools", "SIMDTypes", "SLEEFPirates", "Static", "StaticArrayInterface", "ThreadingUtilities", "UnPack", "VectorizationBase"]
git-tree-sha1 = "0f5648fbae0d015e3abe5867bca2b362f67a5894"
uuid = "bdcacae8-1622-11e9-2a5c-532679323890"
version = "0.12.166"

    [deps.LoopVectorization.extensions]
    ForwardDiffExt = ["ChainRulesCore", "ForwardDiff"]
    SpecialFunctionsExt = "SpecialFunctions"

    [deps.LoopVectorization.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ForwardDiff = "f6369f11-7733-5829-9624-2563aa707210"
    SpecialFunctions = "276daf66-3868-5448-9aa4-cd146d93841b"

[[deps.MIMEs]]
git-tree-sha1 = "65f28ad4b594aebe22157d6fac869786a255b7eb"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "0.1.4"

[[deps.MKL_jll]]
deps = ["Artifacts", "IntelOpenMP_jll", "JLLWrappers", "LazyArtifacts", "Libdl", "Pkg"]
git-tree-sha1 = "2ce8695e1e699b68702c03402672a69f54b8aca9"
uuid = "856f044c-d86e-5d09-b602-aeab76dc8ba7"
version = "2022.2.0+0"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "42324d08725e200c23d4dfb549e0d5d89dede2d2"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.10"

[[deps.ManualMemory]]
git-tree-sha1 = "bcaef4fc7a0cfe2cba636d84cda54b5e4e4ca3cd"
uuid = "d125e4d3-2237-4719-b19c-fa641b8a4667"
version = "0.1.8"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "Random", "Sockets"]
git-tree-sha1 = "03a9b9718f5682ecb107ac9f7308991db4ce395b"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.7"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.2+0"

[[deps.Measurements]]
deps = ["Calculus", "LinearAlgebra", "Printf", "RecipesBase", "Requires"]
git-tree-sha1 = "12950d646ce04fb2e89ba5bd890205882c3592d7"
uuid = "eff96d63-e80a-5855-80a2-b1b0885c5ab7"
version = "2.8.0"

[[deps.Measures]]
git-tree-sha1 = "c13304c81eec1ed3af7fc20e75fb6b26092a1102"
uuid = "442fdcdd-2543-5da2-b0f3-8c86c306513e"
version = "0.3.2"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "f66bdc5de519e8f8ae43bdc598782d35a25b1272"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.1.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2022.10.11"

[[deps.MultivariateStats]]
deps = ["Arpack", "LinearAlgebra", "SparseArrays", "Statistics", "StatsAPI", "StatsBase"]
git-tree-sha1 = "91a48569383df24f0fd2baf789df2aade3d0ad80"
uuid = "6f286f6a-111f-5878-ab1e-185364afe411"
version = "0.10.1"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "0877504529a3e5c3343c6f8b4c0381e57e4387e4"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.2"

[[deps.NearestNeighbors]]
deps = ["Distances", "StaticArrays"]
git-tree-sha1 = "2c3726ceb3388917602169bed973dbc97f1b51a8"
uuid = "b8a86587-4115-5ab1-83bc-aa920d37bbce"
version = "0.4.13"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.Observables]]
git-tree-sha1 = "6862738f9796b3edc1c09d0890afce4eca9e7e93"
uuid = "510215fc-4207-5dde-b226-833fc4488ee2"
version = "0.5.4"

[[deps.OffsetArrays]]
deps = ["Adapt"]
git-tree-sha1 = "82d7c9e310fe55aa54996e6f7f94674e2a38fcb4"
uuid = "6fe1bfb0-de20-5000-8ca7-80f57d26f881"
version = "1.12.9"

[[deps.Ogg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "887579a3eb005446d514ab7aeac5d1d027658b8f"
uuid = "e7412a2a-1a6e-54c0-be00-318e2571c051"
version = "1.3.5+1"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.21+4"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.1+0"

[[deps.OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "6503b77492fd7fcb9379bf73cd31035670e3c509"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.3.3"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9ff31d101d987eb9d66bd8b176ac7c277beccd09"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.20+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.Opus_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51a08fb14ec28da2ec7a927c4337e4332c2a4720"
uuid = "91d4177d-7536-5919-b921-800302f37372"
version = "1.3.2+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[deps.PCRE2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "efcefdf7-47ab-520b-bdef-62a2eaa19f15"
version = "10.42.0+0"

[[deps.PDMats]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "67eae2738d63117a196f497d7db789821bce61d1"
uuid = "90014a1f-27ba-587c-ab20-58faa44d9150"
version = "0.11.17"

[[deps.Parsers]]
deps = ["Dates", "SnoopPrecompile"]
git-tree-sha1 = "478ac6c952fddd4399e71d4779797c538d0ff2bf"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.5.8"

[[deps.Pipe]]
git-tree-sha1 = "6842804e7867b115ca9de748a0cf6b364523c16d"
uuid = "b98c9c47-44ae-5843-9183-064241ee97a0"
version = "1.3.0"

[[deps.Pixman_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b4f5d02549a10e20780a24fce72bea96b6329e29"
uuid = "30392449-352a-5448-841d-b1acce4e97dc"
version = "0.40.1+0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.9.2"

[[deps.PlotThemes]]
deps = ["PlotUtils", "Statistics"]
git-tree-sha1 = "1f03a2d339f42dca4a4da149c7e15e9b896ad899"
uuid = "ccf2f8ad-2431-5c83-bf29-c5338b663b6a"
version = "3.1.0"

[[deps.PlotUtils]]
deps = ["ColorSchemes", "Colors", "Dates", "Printf", "Random", "Reexport", "SnoopPrecompile", "Statistics"]
git-tree-sha1 = "c95373e73290cf50a8a22c3375e4625ded5c5280"
uuid = "995b91a9-d308-5afd-9ec6-746e21dbc043"
version = "1.3.4"

[[deps.Plots]]
deps = ["Base64", "Contour", "Dates", "Downloads", "FFMPEG", "FixedPointNumbers", "GR", "JLFzf", "JSON", "LaTeXStrings", "Latexify", "LinearAlgebra", "Measures", "NaNMath", "Pkg", "PlotThemes", "PlotUtils", "Preferences", "Printf", "REPL", "Random", "RecipesBase", "RecipesPipeline", "Reexport", "RelocatableFolders", "Requires", "Scratch", "Showoff", "SnoopPrecompile", "SparseArrays", "Statistics", "StatsBase", "UUIDs", "UnicodeFun", "Unzip"]
git-tree-sha1 = "f49a45a239e13333b8b936120fe6d793fe58a972"
uuid = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
version = "1.38.8"

    [deps.Plots.extensions]
    FileIOExt = "FileIO"
    GeometryBasicsExt = "GeometryBasics"
    IJuliaExt = "IJulia"
    ImageInTerminalExt = "ImageInTerminal"
    UnitfulExt = "Unitful"

    [deps.Plots.weakdeps]
    FileIO = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
    GeometryBasics = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
    IJulia = "7073ff75-c697-5162-941a-fcdaad2a7d2a"
    ImageInTerminal = "d8c32880-2388-543b-8c61-d9f865259254"
    Unitful = "1986cc42-f94f-5a68-af5c-568840ba703d"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "5bb5129fdd62a2bbbe17c2756932259acf467386"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.50"

[[deps.Polyester]]
deps = ["ArrayInterface", "BitTwiddlingConvenienceFunctions", "CPUSummary", "IfElse", "ManualMemory", "PolyesterWeave", "Requires", "Static", "StaticArrayInterface", "StrideArraysCore", "ThreadingUtilities"]
git-tree-sha1 = "8df43bbe60029526dd628af7e9951f5af680d4d7"
uuid = "f517fe37-dbe3-4b94-8317-1923a5111588"
version = "0.7.10"

[[deps.PolyesterWeave]]
deps = ["BitTwiddlingConvenienceFunctions", "CPUSummary", "IfElse", "Static", "ThreadingUtilities"]
git-tree-sha1 = "240d7170f5ffdb285f9427b92333c3463bf65bf6"
uuid = "1d0040c9-8b98-4ee7-8388-3f51789ca0ad"
version = "0.2.1"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "a6062fe4063cdafe78f4a0a81cfffb89721b30e7"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.2"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "5aa36f7049a63a1528fe8f7c3f2113413ffd4e1f"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.2.1"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "47e5f437cc0e7ef2ce8406ce1e7e24d44915f88d"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.3.0"

[[deps.PrettyTables]]
deps = ["Crayons", "Formatting", "LaTeXStrings", "Markdown", "Reexport", "StringManipulation", "Tables"]
git-tree-sha1 = "96f6db03ab535bdb901300f88335257b0018689d"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "2.2.2"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Qt5Base_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Fontconfig_jll", "Glib_jll", "JLLWrappers", "Libdl", "Libglvnd_jll", "OpenSSL_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libxcb_jll", "Xorg_xcb_util_image_jll", "Xorg_xcb_util_keysyms_jll", "Xorg_xcb_util_renderutil_jll", "Xorg_xcb_util_wm_jll", "Zlib_jll", "xkbcommon_jll"]
git-tree-sha1 = "0c03844e2231e12fda4d0086fd7cbe4098ee8dc5"
uuid = "ea2cea3b-5b76-57ae-a6ef-0a8af62496e1"
version = "5.15.3+2"

[[deps.QuadGK]]
deps = ["DataStructures", "LinearAlgebra"]
git-tree-sha1 = "6ec7ac8412e83d57e313393220879ede1740f9ee"
uuid = "1fd47b50-473d-5c70-9696-f719f8f3bcdc"
version = "2.8.2"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Ratios]]
deps = ["Requires"]
git-tree-sha1 = "dc84268fe0e3335a62e315a3a7cf2afa7178a734"
uuid = "c84ed2f1-dad5-54f0-aa8e-dbefe2724439"
version = "0.4.3"

[[deps.RecipesBase]]
deps = ["SnoopPrecompile"]
git-tree-sha1 = "261dddd3b862bd2c940cf6ca4d1c8fe593e457c8"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.3.3"

[[deps.RecipesPipeline]]
deps = ["Dates", "NaNMath", "PlotUtils", "RecipesBase", "SnoopPrecompile"]
git-tree-sha1 = "e974477be88cb5e3040009f3767611bc6357846f"
uuid = "01d81517-befc-4cb6-b9ec-a95719d0359c"
version = "0.6.11"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.RelocatableFolders]]
deps = ["SHA", "Scratch"]
git-tree-sha1 = "90bc7a7c96410424509e4263e277e43250c05691"
uuid = "05181044-ff0b-4ac5-8273-598c1e38db00"
version = "1.0.0"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[deps.Rmath]]
deps = ["Random", "Rmath_jll"]
git-tree-sha1 = "f65dcb5fa46aee0cf9ed6274ccbd597adc49aa7b"
uuid = "79098fc4-a85e-5d69-aa6a-4863f24498fa"
version = "0.7.1"

[[deps.Rmath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6ed52fdd3382cf21947b15e8870ac0ddbff736da"
uuid = "f50d1b31-88e8-58de-be2c-1cc44531875f"
version = "0.4.0+0"

[[deps.RollingFunctions]]
deps = ["AccurateArithmetic", "FastBroadcast", "KahanSummation", "LinearAlgebra", "LoopVectorization", "Statistics", "StatsBase", "Tables"]
git-tree-sha1 = "4a54152985fea23b0b0e99a77566a87137221a0a"
uuid = "b0e4dd01-7b14-53d8-9b45-175a3e362653"
version = "0.8.0"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.SIMDTypes]]
git-tree-sha1 = "330289636fb8107c5f32088d2741e9fd7a061a5c"
uuid = "94e857df-77ce-4151-89e5-788b33177be4"
version = "0.1.0"

[[deps.SLEEFPirates]]
deps = ["IfElse", "Static", "VectorizationBase"]
git-tree-sha1 = "3aac6d68c5e57449f5b9b865c9ba50ac2970c4cf"
uuid = "476501e8-09a2-5ece-8869-fb82de89a1fa"
version = "0.6.42"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "30449ee12237627992a99d5e30ae63e4d78cd24a"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.2.0"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "77d3c4726515dca71f6d80fbb5e251088defe305"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.3.18"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.Showoff]]
deps = ["Dates", "Grisu"]
git-tree-sha1 = "91eddf657aca81df9ae6ceb20b959ae5653ad1de"
uuid = "992d4aef-0814-514b-bc4d-f2e9a6c4116f"
version = "1.0.3"

[[deps.SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[deps.SnoopPrecompile]]
deps = ["Preferences"]
git-tree-sha1 = "e760a70afdcd461cf01a575947738d359234665c"
uuid = "66db9d55-30c0-4569-8b51-7e840670fc0c"
version = "1.0.3"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "a4ada03f999bd01b3a25dcaa30b2d929fe537e00"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.1.0"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SpecialFunctions]]
deps = ["IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "ef28127915f4229c971eb43f3fc075dd3fe91880"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.2.0"
weakdeps = ["ChainRulesCore"]

    [deps.SpecialFunctions.extensions]
    SpecialFunctionsChainRulesCoreExt = "ChainRulesCore"

[[deps.Static]]
deps = ["IfElse"]
git-tree-sha1 = "b366eb1eb68075745777d80861c6706c33f588ae"
uuid = "aedffcd0-7271-4cad-89d0-dc628f76c6d3"
version = "0.8.9"

[[deps.StaticArrayInterface]]
deps = ["ArrayInterface", "Compat", "IfElse", "LinearAlgebra", "PrecompileTools", "Requires", "SparseArrays", "Static", "SuiteSparse"]
git-tree-sha1 = "5d66818a39bb04bf328e92bc933ec5b4ee88e436"
uuid = "0d7ed370-da01-4f52-bd93-41d350b8b718"
version = "1.5.0"
weakdeps = ["OffsetArrays", "StaticArrays"]

    [deps.StaticArrayInterface.extensions]
    StaticArrayInterfaceOffsetArraysExt = "OffsetArrays"
    StaticArrayInterfaceStaticArraysExt = "StaticArrays"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "Random", "StaticArraysCore", "Statistics"]
git-tree-sha1 = "6aa098ef1012364f2ede6b17bf358c7f1fbe90d4"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.5.17"

[[deps.StaticArraysCore]]
git-tree-sha1 = "6b7ba252635a5eff6a0b0664a41ee140a1c9e72a"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.0"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.9.0"

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f9af7f195fb13589dd2e2d57fdb401717d2eb1f6"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.5.0"

[[deps.StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "d1bf48bfcc554a3761a133fe3a9bb01488e06916"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.21"

[[deps.StatsFuns]]
deps = ["HypergeometricFunctions", "IrrationalConstants", "LogExpFunctions", "Reexport", "Rmath", "SpecialFunctions"]
git-tree-sha1 = "f625d686d5a88bcd2b15cd81f18f98186fdc0c9a"
uuid = "4c63d2b9-4356-54db-8cca-17b64c39e42c"
version = "1.3.0"

    [deps.StatsFuns.extensions]
    StatsFunsChainRulesCoreExt = "ChainRulesCore"
    StatsFunsInverseFunctionsExt = "InverseFunctions"

    [deps.StatsFuns.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.StatsPlots]]
deps = ["AbstractFFTs", "Clustering", "DataStructures", "DataValues", "Distributions", "Interpolations", "KernelDensity", "LinearAlgebra", "MultivariateStats", "NaNMath", "Observables", "Plots", "RecipesBase", "RecipesPipeline", "Reexport", "StatsBase", "TableOperations", "Tables", "Widgets"]
git-tree-sha1 = "e0d5bc26226ab1b7648278169858adcfbd861780"
uuid = "f3b207a7-027a-5e70-b257-86293d7955fd"
version = "0.15.4"

[[deps.StrideArraysCore]]
deps = ["ArrayInterface", "CloseOpenIntervals", "IfElse", "LayoutPointers", "ManualMemory", "SIMDTypes", "Static", "StaticArrayInterface", "ThreadingUtilities"]
git-tree-sha1 = "d6415f66f3d89c615929af907fdc6a3e17af0d8c"
uuid = "7792a7ef-975c-4747-a70f-980b88e8d1da"
version = "0.5.2"

[[deps.StringManipulation]]
git-tree-sha1 = "46da2434b41f41ac3594ee9816ce5541c6096123"
uuid = "892a3eda-7b42-436c-8928-eab12a02cf0e"
version = "0.3.0"

[[deps.SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "Pkg", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "5.10.1+6"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.TableOperations]]
deps = ["SentinelArrays", "Tables", "Test"]
git-tree-sha1 = "e383c87cf2a1dc41fa30c093b2a19877c83e1bc1"
uuid = "ab02a1b2-a7df-11e8-156e-fb1833f50b87"
version = "1.2.0"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "c79322d36826aa2f4fd8ecfa96ddb47b174ac78d"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.10.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.TensorCore]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1feb45f88d133a655e001435632f019a9a1bcdb6"
uuid = "62fd8b95-f654-4bbd-a8a5-9c27f68ccd50"
version = "0.1.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.ThreadingUtilities]]
deps = ["ManualMemory"]
git-tree-sha1 = "eda08f7e9818eb53661b3deb74e3159460dfbc27"
uuid = "8290d209-cae3-49c0-8002-c8c24d57dab5"
version = "0.5.2"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "94f38103c984f89cf77c402f2a68dbd870f8165f"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.11"

[[deps.Tricks]]
git-tree-sha1 = "6bac775f2d42a611cdfcd1fb217ee719630c4175"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.6"

[[deps.URIs]]
git-tree-sha1 = "074f993b0ca030848b897beff716d93aca60f06a"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.4.2"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.UnicodeFun]]
deps = ["REPL"]
git-tree-sha1 = "53915e50200959667e78a92a418594b428dffddf"
uuid = "1cfade01-22cf-5700-b092-accc4b62d6e1"
version = "0.4.1"

[[deps.Unitful]]
deps = ["ConstructionBase", "Dates", "LinearAlgebra", "Random"]
git-tree-sha1 = "bb37ed24f338bc59b83e3fc9f32dd388e5396c53"
uuid = "1986cc42-f94f-5a68-af5c-568840ba703d"
version = "1.12.4"

[[deps.Unzip]]
git-tree-sha1 = "ca0969166a028236229f63514992fc073799bb78"
uuid = "41fe7b60-77ed-43a1-b4f0-825fd5a5650d"
version = "0.2.0"

[[deps.VectorizationBase]]
deps = ["ArrayInterface", "CPUSummary", "HostCPUFeatures", "IfElse", "LayoutPointers", "Libdl", "LinearAlgebra", "SIMDTypes", "Static", "StaticArrayInterface"]
git-tree-sha1 = "7209df901e6ed7489fe9b7aa3e46fb788e15db85"
uuid = "3d5dd08c-fd9d-11e8-17fa-ed2836048c2f"
version = "0.21.65"

[[deps.Wayland_jll]]
deps = ["Artifacts", "EpollShim_jll", "Expat_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "ed8d92d9774b077c53e1da50fd81a36af3744c1c"
uuid = "a2964d1f-97da-50d4-b82a-358c7fce9d89"
version = "1.21.0+0"

[[deps.Wayland_protocols_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4528479aa01ee1b3b4cd0e6faef0e04cf16466da"
uuid = "2381bf8a-dfd0-557d-9999-79630e7b1b91"
version = "1.25.0+0"

[[deps.WeakRefStrings]]
deps = ["DataAPI", "InlineStrings", "Parsers"]
git-tree-sha1 = "b1be2855ed9ed8eac54e5caff2afcdb442d52c23"
uuid = "ea10d353-3f73-51f8-a26c-33c1cb351aa5"
version = "1.4.2"

[[deps.Widgets]]
deps = ["Colors", "Dates", "Observables", "OrderedCollections"]
git-tree-sha1 = "fcdae142c1cfc7d89de2d11e08721d0f2f86c98a"
uuid = "cc8bc4a8-27d6-5769-a93b-9d913e69aa62"
version = "0.6.6"

[[deps.WoodburyMatrices]]
deps = ["LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "de67fa59e33ad156a590055375a30b23c40299d3"
uuid = "efce3f68-66dc-5838-9240-27a6d6f5f9b6"
version = "0.5.5"

[[deps.WorkerUtilities]]
git-tree-sha1 = "cd1659ba0d57b71a464a29e64dbc67cfe83d54e7"
uuid = "76eceee3-57b5-4d4a-8e66-0e911cebbf60"
version = "1.6.1"

[[deps.XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "93c41695bc1c08c46c5899f4fe06d6ead504bb73"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.10.3+0"

[[deps.XSLT_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgcrypt_jll", "Libgpg_error_jll", "Libiconv_jll", "Pkg", "XML2_jll", "Zlib_jll"]
git-tree-sha1 = "91844873c4085240b95e795f692c4cec4d805f8a"
uuid = "aed1982a-8fda-507f-9586-7b0439959a61"
version = "1.1.34+0"

[[deps.Xorg_libX11_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll", "Xorg_xtrans_jll"]
git-tree-sha1 = "5be649d550f3f4b95308bf0183b82e2582876527"
uuid = "4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"
version = "1.6.9+4"

[[deps.Xorg_libXau_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4e490d5c960c314f33885790ed410ff3a94ce67e"
uuid = "0c0b7dd1-d40b-584c-a123-a41640f87eec"
version = "1.0.9+4"

[[deps.Xorg_libXcursor_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXfixes_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "12e0eb3bc634fa2080c1c37fccf56f7c22989afd"
uuid = "935fb764-8cf2-53bf-bb30-45bb1f8bf724"
version = "1.2.0+4"

[[deps.Xorg_libXdmcp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fe47bd2247248125c428978740e18a681372dd4"
uuid = "a3789734-cfe1-5b06-b2d0-1dd0d9d62d05"
version = "1.1.3+4"

[[deps.Xorg_libXext_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "b7c0aa8c376b31e4852b360222848637f481f8c3"
uuid = "1082639a-0dae-5f34-9b06-72781eeb8cb3"
version = "1.3.4+4"

[[deps.Xorg_libXfixes_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "0e0dc7431e7a0587559f9294aeec269471c991a4"
uuid = "d091e8ba-531a-589c-9de9-94069b037ed8"
version = "5.0.3+4"

[[deps.Xorg_libXi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXfixes_jll"]
git-tree-sha1 = "89b52bc2160aadc84d707093930ef0bffa641246"
uuid = "a51aa0fd-4e3c-5386-b890-e753decda492"
version = "1.7.10+4"

[[deps.Xorg_libXinerama_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll"]
git-tree-sha1 = "26be8b1c342929259317d8b9f7b53bf2bb73b123"
uuid = "d1454406-59df-5ea1-beac-c340f2130bc3"
version = "1.1.4+4"

[[deps.Xorg_libXrandr_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "34cea83cb726fb58f325887bf0612c6b3fb17631"
uuid = "ec84b674-ba8e-5d96-8ba1-2a689ba10484"
version = "1.5.2+4"

[[deps.Xorg_libXrender_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "19560f30fd49f4d4efbe7002a1037f8c43d43b96"
uuid = "ea2f1a96-1ddc-540d-b46f-429655e07cfa"
version = "0.9.10+4"

[[deps.Xorg_libpthread_stubs_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6783737e45d3c59a4a4c4091f5f88cdcf0908cbb"
uuid = "14d82f49-176c-5ed1-bb49-ad3f5cbd8c74"
version = "0.1.0+3"

[[deps.Xorg_libxcb_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "XSLT_jll", "Xorg_libXau_jll", "Xorg_libXdmcp_jll", "Xorg_libpthread_stubs_jll"]
git-tree-sha1 = "daf17f441228e7a3833846cd048892861cff16d6"
uuid = "c7cfdc94-dc32-55de-ac96-5a1b8d977c5b"
version = "1.13.0+3"

[[deps.Xorg_libxkbfile_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "926af861744212db0eb001d9e40b5d16292080b2"
uuid = "cc61e674-0454-545c-8b26-ed2c68acab7a"
version = "1.1.0+4"

[[deps.Xorg_xcb_util_image_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "0fab0a40349ba1cba2c1da699243396ff8e94b97"
uuid = "12413925-8142-5f55-bb0e-6d7ca50bb09b"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll"]
git-tree-sha1 = "e7fd7b2881fa2eaa72717420894d3938177862d1"
uuid = "2def613f-5ad1-5310-b15b-b15d46f528f5"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_keysyms_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "d1151e2c45a544f32441a567d1690e701ec89b00"
uuid = "975044d2-76e6-5fbe-bf08-97ce7c6574c7"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_renderutil_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "dfd7a8f38d4613b6a575253b3174dd991ca6183e"
uuid = "0d47668e-0667-5a69-a72c-f761630bfb7e"
version = "0.3.9+1"

[[deps.Xorg_xcb_util_wm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "e78d10aab01a4a154142c5006ed44fd9e8e31b67"
uuid = "c22f9ab0-d5fe-5066-847c-f4bb1cd4e361"
version = "0.4.1+1"

[[deps.Xorg_xkbcomp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxkbfile_jll"]
git-tree-sha1 = "4bcbf660f6c2e714f87e960a171b119d06ee163b"
uuid = "35661453-b289-5fab-8a00-3d9160c6a3a4"
version = "1.4.2+4"

[[deps.Xorg_xkeyboard_config_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xkbcomp_jll"]
git-tree-sha1 = "5c8424f8a67c3f2209646d4425f3d415fee5931d"
uuid = "33bec58e-1273-512f-9401-5d533626f822"
version = "2.27.0+4"

[[deps.Xorg_xtrans_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "79c31e7844f6ecf779705fbc12146eb190b7d845"
uuid = "c5fb5394-a638-5e4d-96e5-b29de1b5cf10"
version = "1.4.0+3"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.13+0"

[[deps.Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "c6edfe154ad7b313c01aceca188c05c835c67360"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.4+0"

[[deps.fzf_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "868e669ccb12ba16eaf50cb2957ee2ff61261c56"
uuid = "214eeab7-80f7-51ab-84ad-2988db7cef09"
version = "0.29.0+0"

[[deps.libaom_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3a2ea60308f0996d26f1e5354e10c24e9ef905d4"
uuid = "a4ae2306-e953-59d6-aa16-d00cac43593b"
version = "3.4.0+0"

[[deps.libass_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "5982a94fcba20f02f42ace44b9894ee2b140fe47"
uuid = "0ac62f75-1d6f-5e53-bd7c-93b484bb37c0"
version = "0.15.1+0"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.8.0+0"

[[deps.libfdk_aac_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "daacc84a041563f965be61859a36e17c4e4fcd55"
uuid = "f638f0a6-7fb0-5443-88ba-1cc74229b280"
version = "2.0.2+0"

[[deps.libpng_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "94d180a6d2b5e55e447e2d27a29ed04fe79eb30c"
uuid = "b53b4c65-9356-5827-b1ea-8c7a1a84506f"
version = "1.6.38+0"

[[deps.libvorbis_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ogg_jll", "Pkg"]
git-tree-sha1 = "b910cb81ef3fe6e78bf6acee440bda86fd6ae00c"
uuid = "f27f6e37-5d2b-51aa-960f-b287f2bc3b7a"
version = "1.3.7+1"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.52.0+1"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+0"

[[deps.x264_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fea590b89e6ec504593146bf8b988b2c00922b2"
uuid = "1270edf5-f2f9-52d2-97e9-ab00b5d0237a"
version = "2021.5.5+0"

[[deps.x265_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ee567a171cce03570d77ad3a43e90218e38937a9"
uuid = "dfaa095f-4041-5dcd-9319-2fabd8486b76"
version = "3.5.0+0"

[[deps.xkbcommon_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Wayland_jll", "Wayland_protocols_jll", "Xorg_libxcb_jll", "Xorg_xkeyboard_config_jll"]
git-tree-sha1 = "9ebfc140cc56e8c2156a15ceac2f0302e327ac0a"
uuid = "d8fb68d0-12a3-5cfd-a85a-d49703b185fd"
version = "1.4.1+0"
"""

# ╔═╡ Cell order:
# ╟─44bd8931-450e-4019-8dd0-30a5b25d6078
# ╟─e6c4f7f0-e159-4231-9801-76a0ec643673
# ╟─4392a6f5-e8dd-4fe6-b765-d21e14c32461
# ╟─3660811b-8146-4111-819d-794cec160072
# ╠═06f26860-d843-497f-9ae5-25594ddaddef
# ╟─a47c7173-317d-4394-8357-59743f5a0982
# ╟─1322f57c-93ff-4c5d-9980-30fd01d5a4d3
# ╟─f86e3141-2161-4dec-ab51-15612e30bc70
# ╟─b09a2088-a56a-4479-82ec-995e5cdf27f4
# ╟─a1cb22d0-7de2-4033-8643-1d8a89ab3d7d
# ╟─328d3bbc-3aa1-4e68-a3f9-997c9222f78e
# ╟─4bd00596-c1cb-4e36-81a2-687e1b19ec0e
# ╟─9dbd2dfd-5899-4c1f-aca4-c53d4c6b7a61
# ╟─43ef91de-2b99-451a-ad20-6c9e2e5908d0
# ╠═285d9346-305b-4345-9f46-402240e7e06b
# ╠═a17830f1-6c78-46c4-81d5-b26867b1ad31
# ╟─d63a6833-c113-4511-be9c-6b01514b1f57
# ╟─6f0539b1-a46c-4df7-a8e2-9982bd929288
# ╟─e18ca91f-0d7c-4799-bd44-bcf768cb3ddd
# ╠═92f0a942-e5fa-4bdf-aa65-b6e07b1a63b7
# ╠═a8959b07-e857-4144-99b2-431a68faf22b
# ╠═9caf6df9-bac8-4ab6-ad8d-a7d578a107aa
# ╠═91a2d5c9-aad9-433f-9cea-6b89f007379d
# ╠═490b91ba-4d2f-4c7f-abd5-7ea64b834178
# ╠═40ab265a-8584-462f-9095-a58cbd6bc2a8
# ╠═ab778fd6-2057-4426-9b71-00974270ba02
# ╠═d86f77a0-6d4b-4bac-a383-3fca16e0fc23
# ╠═bab15754-71d0-4f2b-b1e5-eb34e6519aed
# ╟─c702b936-d809-4235-9d11-29e619d31d37
# ╟─b4ed3094-ba79-4e3e-ab69-96fa6462d07c
# ╟─c2691c78-c918-432a-a28c-2c7d840558ed
# ╟─44d0685c-cf1c-4227-89a2-80a1efc389af
# ╟─6beab4d1-453a-4aee-bbd1-4cc524f9eedb
# ╟─e1dba096-8eb8-4757-9590-c97d53bd2d5a
# ╟─8676533e-169d-4395-867b-297d3fd2768f
# ╟─4c5d1444-811b-4ca2-b97b-154787335cdc
# ╟─92c0b43e-e2c8-4009-a5bb-973eba87427f
# ╟─b2ebf5ab-f318-4f56-a14d-c91f9e1d1ff2
# ╠═4aaa1f90-93a0-4788-a14b-49f7f4f7f3c5
# ╟─602199e4-9c56-431c-aa84-d629a099c702
# ╠═9777f399-0ee3-40c3-b023-65cf04b71734
# ╟─44ed1931-2f74-4dfe-808d-3a5941dde05e
# ╟─0e18a6ec-a252-4fbf-ba0b-40d92ff3767f
# ╠═eaf0530e-8250-438a-93cb-d5413384d243
# ╠═82f94f15-00c0-494b-a6fd-66b1b31f7862
# ╠═ffd7b8db-d8d8-41a1-abd6-4a04be7016c1
# ╠═5257047a-054a-4944-a3bb-417470cd30e2
# ╠═de8f2990-6af3-4ea9-b138-182aa06c7e75
# ╠═cc0fe7f4-825c-4e63-91d8-77171b43f92c
# ╠═424eb2fd-5fa7-46f2-85e7-75db773eed1d
# ╟─8043725d-dddf-48d3-9ee8-e4dc36a9f79f
# ╟─ba4ac1cc-0e7a-44bf-86a6-003532275ac4
# ╟─a95db3bc-2999-45f7-84b1-6c33ef4d2366
# ╠═07928111-006d-4fb1-a019-f3a4ec13f690
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
