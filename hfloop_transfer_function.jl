include("helpers.jl")

csv_name = "data/test_csv.csv"
df = CSV.read(csv_name, DataFrame)

f = df.Frequency
out_dBm = df.var" Trace 1 Output Power (dBm)"
in_dBm = df.var" Trace 3 Loop Resistor Power (dBm)"

out_mVpp = dBm_to_mVpp.(out_dBm)
in_mVpp = dBm_to_mVpp.(in_dBm)

T = out_mVpp ./ in_mVpp

scatter(f, T)