# scripts/bmopf/dataset/gen_lv3.jl
#
# DATASET STEP 2: clean vs dirty DOE dataset on LV3, built from the AusNet house-usage pool.
#
# One scenario = (day, half-hour, 12 households, source voltage).
#   days:      5 per month (3 from training weeks, 1 validation week, 1 test week) + day 350
#              (17 Dec, the day used so far) + day 15 (16 Jan heatwave) = about 62 days
#   times:     09:00 to 15:30 (half-hours 19-32)
#   voltages:  1.00, 1.01, 1.02, 1.025, 1.03, 1.035 pu
#   houses:    12 households drawn per day from the matching split, skipping missing days;
#              Q = 0.539743 x P (power factor 0.88, as the LV3 loads); PV available = 5 kW x PV shape
# Networks:   records = all service cables 16 mm2 (what the utility believes); four fixed "true"
#             feeders: T0 records correct, T1 only l_3432 is 4 mm2, T2 five random customer cables
#             4 mm2, T3 all 12 customer cables 4 mm2.
# Labels:     issued equal DOE (records), correct equal DOE (each truth), realised outcome of the
#             issued DOE on each truth. Bound-point equal DOEs (1 solve each).
# Splits:     households 240 / 51 / 51 (train / val / test, balanced by annual energy); days by
#             whole weeks (1 validation and 1 test week per month); a scenario's houses always come
#             from the same split as its day, so test = test households on test days.
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/dataset/gen_lv3.jl")
#   julia> gen_plan()                     # writes the plan (scenarios, splits, truths), seconds
#   julia> gen_run(pilot = true)          # 20 scenarios spread over the plan, to time it
#   julia> gen_run()                      # everything; resumable (skips scenarios already done)
# OUTPUT results/dataset/lv3_v1/  (scenarios.csv, households.csv, days.csv, truths.csv,
#        labels.csv; pilot -> labels_pilot.csv)

using Distributed, Random
include(joinpath(pwd(), "scripts", "bmopf", "dataset", "pool_profiles.jl"))
include(joinpath(pwd(), "scripts", "bmopf", "dataset", "gen_lv3_worker.jl"))

const GEN_DIR   = joinpath(pwd(), "results", "dataset", "lv3_v1")
const GEN_SEED  = 20261014
const GEN_TIMES = 19:32
const GEN_PUS   = [1.00, 1.01, 1.02, 1.025, 1.03, 1.035]
const GEN_QP    = 0.539743

# ---------------------------------------------------------------------------- plan (master only)
function gen_plan(; seed = GEN_SEED)
    mkpath(GEN_DIR)
    rng = MersenneTwister(seed)
    R, PV = load_pool()
    valid = pool_valid(R)
    nh, nd = size(R, 1), size(R, 2)
    # households: sort by annual energy, groups of 20 -> 14 train, 3 val, 3 test
    annual = [0.5 * sum((sum(@view R[h, d, :]) for d in 1:nd if valid[h, d]); init = 0.0) for h in 1:nh]
    hsplit = fill("train", nh)
    for g in Iterators.partition(sortperm(annual), 20)
        length(g) < 20 && continue
        s = shuffle(rng, collect(g))
        hsplit[s[15:17]] .= "val"; hsplit[s[18:20]] .= "test"
    end
    # weeks (7-day blocks from 1 Jan); per month 1 val and 1 test week
    week(d) = (d - 1) ÷ 7 + 1
    wsplit = Dict(w => "train" for w in 1:week(nd))
    for m in 1:12
        ws = unique(week(d) for d in 1:nd if month(pool_date(d)) == m && month(pool_date(7 * (week(d) - 1) + 1)) == m)
        ws = shuffle(rng, ws)
        wsplit[ws[1]] = "val"; wsplit[ws[2]] = "test"
    end
    dsplit(d) = wsplit[week(d)]
    # days: per month 3 train + 1 val + 1 test, plus day indices 350 and 15
    days = Int[]
    for m in 1:12
        md = [d for d in 1:nd if month(pool_date(d)) == m]
        for (sp, k) in (("train", 3), ("val", 1), ("test", 1))
            cand = shuffle(rng, [d for d in md if dsplit(d) == sp])
            append!(days, cand[1:k])
        end
    end
    for d in (351, 16)                                     # 1-based Julia day = index + 1
        d in days || push!(days, d)
    end
    sort!(days)
    # loads of LV3 (sorted names) and their phases
    net = make_net(1.03)
    loads = sort(collect(keys(net["load"])))
    phase(ld) = string(last(ld))
    # truths
    cc = customer_cables(net)
    t2 = sort(shuffle(rng, cc)[1:5])
    truths = [("T0_records_correct", String[]), ("T1_l_3432", ["l_3432"]),
              ("T2_five_random", t2), ("T3_all_12_customer", sort(cc))]
    # scenarios
    rows = String[]; sid = 0
    hdr = "sid,day_index,date,weekday,week,split,half_hour,time,source_pu,pv_shape," *
          join(["c$(i)_load,c$(i)_phase,c$(i)_household,c$(i)_P_kW,c$(i)_Q_kvar" for i in 1:12], ",")
    for d in days
        sp = dsplit(d)
        cand = [h for h in 1:nh if hsplit[h] == sp && valid[h, d]]
        length(cand) >= 12 || error("day $d: only $(length(cand)) valid $sp households")
        hh = shuffle(rng, cand)[1:12]
        for t in GEN_TIMES, pu in GEN_PUS
            sid += 1
            cust = join([@sprintf("%s,%s,%d,%.4f,%.4f", loads[i], phase(loads[i]), hh[i] - 1,
                                  R[hh[i], d, t], GEN_QP * R[hh[i], d, t]) for i in 1:12], ",")
            push!(rows, @sprintf("%d,%d,%s,%s,%d,%s,%d,%s,%.3f,%.4f,%s", sid, d - 1, pool_date(d),
                                 Dates.dayname(pool_date(d)), week(d), sp, t, tlabel(t), pu, PV[d, t], cust))
        end
    end
    open(io -> (println(io, hdr); foreach(l -> println(io, l), rows)), joinpath(GEN_DIR, "scenarios.csv"), "w")
    open(joinpath(GEN_DIR, "households.csv"), "w") do io
        println(io, "household,split,annual_kWh,valid_days")
        for h in 1:nh
            @printf(io, "%d,%s,%.1f,%d\n", h - 1, hsplit[h], annual[h], count(valid[h, :]))
        end
    end
    open(joinpath(GEN_DIR, "days.csv"), "w") do io
        println(io, "day_index,date,weekday,week,split,in_dataset")
        for d in 1:nd
            @printf(io, "%d,%s,%s,%d,%s,%s\n", d - 1, pool_date(d), Dates.dayname(pool_date(d)), week(d), dsplit(d), d in days)
        end
    end
    open(joinpath(GEN_DIR, "truths.csv"), "w") do io
        println(io, "truth,segments_really_4mm2")
        for (n, ids) in truths
            println(io, n, ",", join(ids, " "))
        end
    end
    nsplit = Dict(s => count(d -> dsplit(d) == s, days) for s in ("train", "val", "test"))
    @printf("plan: %d days (train %d, val %d, test %d) x %d times x %d voltages = %d scenarios\n",
            length(days), nsplit["train"], nsplit["val"], nsplit["test"], length(GEN_TIMES), length(GEN_PUS), sid)
    @printf("households: train %d, val %d, test %d; T2 random cables: %s\n",
            count(==("train"), hsplit), count(==("val"), hsplit), count(==("test"), hsplit), join(t2, " "))
    println("written ", GEN_DIR, " (scenarios.csv, households.csv, days.csv, truths.csv)")
end

# ---------------------------------------------------------------------------- run
function gen_read_plan()
    lines = collect(eachline(joinpath(GEN_DIR, "scenarios.csv")))
    hdr = split(lines[1], ",")
    col(n) = findfirst(==(n), hdr)
    scs = map(lines[2:end]) do l
        f = split(l, ",")
        loads = [(String(f[col("c$(i)_load")]), parse(Float64, f[col("c$(i)_P_kW")]),
                  parse(Float64, f[col("c$(i)_Q_kvar")])) for i in 1:12]
        (sid = parse(Int, f[col("sid")]), pu = parse(Float64, f[col("source_pu")]),
         pv = parse(Float64, f[col("pv_shape")]), loads = loads)
    end
    truths = map(collect(eachline(joinpath(GEN_DIR, "truths.csv")))[2:end]) do l
        n, ids = split(l, ","; limit = 2)
        (String(n), String.(split(ids)))
    end
    return scs, truths
end

function gen_workers(n)
    nw = nprocs() == 1 ? 0 : nworkers()
    nw < n && addprocs(n - nw; exeflags = "--project=$(Base.active_project())", dir = pwd())
    wf = joinpath(pwd(), "scripts", "bmopf", "dataset", "gen_lv3_worker.jl")
    @everywhere workers() begin
        using Logging; disable_logging(Logging.Warn)
        include($wf)
    end
    println("workers ready: ", nworkers())
end

function gen_run(; pilot = false, nworkers_wanted = 4, chunk = 40)
    t0 = time()
    scs, truths = gen_read_plan()
    file = joinpath(GEN_DIR, pilot ? "labels_pilot.csv" : "labels.csv")
    if pilot
        idx = unique(round.(Int, range(1, length(scs); length = 20)))
        scs = scs[idx]
        isfile(file) && rm(file)
    end
    done = Set{Int}()
    if isfile(file)
        for l in Iterators.drop(eachline(file), 1)
            push!(done, parse(Int, split(l, ",")[1]))
        end
    else
        open(io -> println(io, GEN_LABEL_HEADER), file, "w")
    end
    todo = [s for s in scs if !(s.sid in done)]
    @printf("%d scenarios to do (%d already done), %d truths each\n", length(todo), length(done), length(truths))
    isempty(todo) && return
    gen_workers(nworkers_wanted)
    t1 = time(); ndone = 0; nerr = 0
    for part in Iterators.partition(todo, chunk)
        res = pmap(sc -> gen_one(sc, truths), collect(part))
        open(file, "a") do io
            for rows in res, r in rows
                println(io, r)
                nerr += endswith(r, "\"")
            end
        end
        ndone += length(part)
        left = length(todo) - ndone
        @printf("  %d / %d done, %.1f s per scenario overall, about %.0f min left, error rows %d\n",
                ndone, length(todo), (time() - t1) / ndone, left * (time() - t1) / ndone / 60, nerr)
    end
    @printf("finished: %s (%.0f min)\n", file, (time() - t0) / 60)
end
