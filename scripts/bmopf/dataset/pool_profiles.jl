# =============================================================================
# pool_profiles.jl: read and check Team-Nando's AusNet house-usage pool (.npy files)
#
# What it does (plain English):
#   Loads Team-Nando's AusNet house-usage pool (342 households x 365 days x 48 half-hours,
#   average kW) and the matching PV shape (365 days x 48), and checks them: SHA1 of both
#   files, shapes, missing (all-zero) days, value ranges, mean daily kWh per house (lowest,
#   median and highest day), PV daily energy. Then checks that the 99 OE1 profiles used in
#   the day runs equal the pool's day index 350 (the lowest-demand day in the dataset).
#   No extra packages: a small reader for the .npy format is written here.
#   Day indices are printed 0-based (as in the Python source); Julia arrays are 1-based, so
#   day index 350 is Julia day 351. The year is not stated in the source data; the printed
#   calendar dates use an inferred start date (POOL_DAY0) and are labels only.
#
# Inputs:   data/profiles/pool/ (download once, see data/profiles/pool/README_pool.md):
#             Residential load data 30-min resolution.npy
#             Residential PV data 30-min resolution.npy
#             README_pool.md, TeamNando_LICENSE.txt
#           data/profiles/TeamNando_OE1_LoadShapes.txt (for the OE1 cross-check).
# Outputs:  results/dataset/pool_check.txt (same lines as printed).
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   include("scripts/bmopf/dataset/pool_profiles.jl")   then   check_pool()   (a few seconds)
# Used for: the profile-day statements in REPRODUCE.md section 2 (day index 350, 9.71 vs
#           12.06 kWh, OE1 shapes equal the pool values); planned source for more days.
# Credits:  Team-Nando OE1-Ideal / MV-LV-Networks / OEs-The-Basics profiles (BSD-3, AusNet
#           smart-meter data).
# =============================================================================

using Printf, SHA, Dates

const POOL_DIR  = joinpath(pwd(), "data", "profiles", "pool")
const POOL_LOAD = joinpath(POOL_DIR, "Residential load data 30-min resolution.npy")
const POOL_PV   = joinpath(POOL_DIR, "Residential PV data 30-min resolution.npy")
const POOL_SHA  = Dict(POOL_LOAD => "145d73c070f7e95c14524db684918b47daaf1e6e",
                       POOL_PV   => "59cf9e081d22f54a272ede4a7a8dfaa1c7dd48ce")
# start date for printed labels only: the year is not stated in the data and is inferred
const POOL_DAY0 = Date(2014, 1, 1)          # inferred year (see README_pool.md)

# read a little-endian float64, C-ordered .npy file into a Julia array with the same index order
function read_npy(path)
    open(path) do io
        magic = read(io, 6)
        magic == UInt8[0x93, UInt8('N'), UInt8('U'), UInt8('M'), UInt8('P'), UInt8('Y')] || error("$path is not a .npy file")
        major = read(io, UInt8); read(io, UInt8)
        hlen  = major == 1 ? Int(ltoh(read(io, UInt16))) : Int(ltoh(read(io, UInt32)))
        hdr   = String(read(io, hlen))
        occursin("'descr': '<f8'", hdr)          || error("$path: expected little-endian float64, header: $hdr")
        occursin("'fortran_order': False", hdr)  || error("$path: expected C order, header: $hdr")
        m = match(r"'shape': \(([^)]*)\)", hdr)
        dims = Tuple(parse(Int, strip(x)) for x in split(m[1], ",") if !isempty(strip(x)))
        data = Vector{Float64}(undef, prod(dims))
        read!(io, data)
        ENDIAN_BOM == 0x04030201 || (data .= ltoh.(data))
        eof(io) || error("$path: extra bytes after the data")
        A = reshape(data, reverse(dims)...)            # C order -> reversed Julia dims
        return permutedims(A, collect(length(dims):-1:1))
    end
end

# R[h, d, t]: household h (1..342), day d (1..365), half-hour t (1..48), average kW
# PV[d, t]:   per-unit PV shape (year max 1.0)
load_pool() = (read_npy(POOL_LOAD), read_npy(POOL_PV))

pool_date(d) = POOL_DAY0 + Day(d - 1)                  # d is 1-based

# usable (household, day) pairs: not an all-zero day
pool_valid(R) = [any(!iszero, @view R[h, d, :]) for h in axes(R, 1), d in axes(R, 2)]

# the 99 OE1 profiles (5-min, kW) averaged to half-hours, by their Load_shape_k number k
function oe1_halfhour()
    f = joinpath(pwd(), "data", "profiles", "TeamNando_OE1_LoadShapes.txt")
    out = Dict{Int,Vector{Float64}}()
    for line in eachline(f)
        m = match(r"^New Loadshape\.Load_shape_(\d+)"i, line)
        m === nothing && continue
        v = parse.(Float64, split(strip(match(r"Pmult=\[([^\]]*)\]", line)[1]), r"[,\s]+"; keepempty = false))
        length(v) == 288 || error("Load_shape_$(m[1]): expected 288 points")
        out[parse(Int, m[1])] = [sum(v[6i-5:6i]) / 6 for i in 1:48]
    end
    return out
end

function check_pool()
    lines = String[]
    say(s) = (println(s); push!(lines, s))
    for (f, h) in POOL_SHA
        isfile(f) || error("missing $f (see README_pool.md)")
        got = bytes2hex(open(sha1, f))
        say(@sprintf("%-45s SHA1 %s %s", basename(f), got, got == h ? "OK" : "MISMATCH (expected $h)"))
    end
    R, PV = load_pool()
    say("load pool shape $(size(R)) (households x days x half-hours), PV shape $(size(PV))")
    size(R) == (342, 365, 48) && size(PV) == (365, 48) || error("unexpected shapes")
    valid = pool_valid(R)
    nzero = count(!, valid)
    say(@sprintf("all-zero (missing) days: %d, in %d households", nzero, count(h -> !all(valid[h, :]), 1:342)))
    say(@sprintf("load kW: min %.3f, mean %.3f, max %.2f; negative values: %d", minimum(R), sum(R) / length(R),
                 maximum(R), count(<(0), R)))
    daily = [valid[h, d] ? sum(R[h, d, :]) * 0.5 : NaN for h in 1:342, d in 1:365]
    dmean = [sum(filter(!isnan, daily[:, d])) / count(!isnan, daily[:, d]) for d in 1:365]
    order = sortperm(dmean)
    say(@sprintf("mean kWh per house per day: median day %.2f; lowest day index %d (%s, %.2f); highest %d (%s, %.2f)",
                 sort(dmean)[183], order[1] - 1, pool_date(order[1]), dmean[order[1]],
                 order[end] - 1, pool_date(order[end]), dmean[order[end]]))
    say(@sprintf("PV: max %.3f, daily energy (pu-hours) median %.2f, max %.2f", maximum(PV),
                 sort(vec(sum(PV; dims = 2)) .* 0.5)[183], maximum(sum(PV; dims = 2)) * 0.5))
    # cross-check against the 99 profiles used so far (expected: day index 350 = Julia day 351)
    oe1 = oe1_halfhour()
    worst = maximum(maximum(abs.(R[k + 1, 351, :] .- v)) for (k, v) in oe1)
    say(@sprintf("OE1 check: %d profiles vs pool day index 350 (%s): max difference %.2e kW -> %s",
                 length(oe1), pool_date(351), worst, worst < 1e-9 ? "MATCH" : "NO MATCH"))
    mkpath(joinpath(pwd(), "results", "dataset"))
    open(joinpath(pwd(), "results", "dataset", "pool_check.txt"), "w") do io
        foreach(l -> println(io, l), lines)
    end
    println("written results/dataset/pool_check.txt")
end
