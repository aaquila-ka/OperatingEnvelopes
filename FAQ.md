# Frequently asked questions

**What is a Dynamic Operating Envelope (DOE)?**
A limit the network sends to each home: "you may export up to x kW right now". It changes through the day. Here it is calculated with an optimal power flow: the largest equal export for every home that keeps every home's voltage at or below 253 V and respects each inverter's settings.

**What exactly is "wrong" in the records?**
The records (the network model) say every service cable, the short cable from the street to a home, is 16 mm² copper. We then build "true" streets where some of those cables differ: either small random changes in resistance ("scatter", 5 %, 10 % or 20 %) or a different cable type (4 mm² copper; the dataset's own line codes give it 3.07 times the resistance of the 16 mm² cable). The records are never changed; only the true street is. The limit from the records is then tested on the true street.

**Is 4 mm² a real fault you found?**
No. It is a test case built from the dataset's own cable library. Real-world evidence that recorded cable values can differ from measured ones comes from Project EDGE: on one of the two feeders studied, the checked model's aggregated positive-sequence resistance was 170 % higher and its reactance 400 % higher than in the original (unchecked) model (see ACKNOWLEDGEMENTS.md).

**Why 253 V?**
Australian standard voltage is 230 V +10 % / -6 % (AS 60038:2012), so the upper limit is 253 V. The results are all about this upper limit. The limit is checked phase-to-neutral at each home's own connection.

**Why a supply voltage of 1.03 pu?**
It puts the street near its voltage limit, where the export limit is set by voltage and the cable matters. It is also the value used in Frederik Geth's PowerOptLab LV3 study. REPRODUCE.md step 11 sweeps 1.00 to 1.035 pu. For the basic (bound-point) DOE at 12:00, the gap is small at 1.00 pu (0.14 kW) and largest at 1.03 pu (2.29 kW). Always read a result together with its supply voltage.

**What do "bound-point", "phase-secure" and "dropout-secure" mean?**
They are three levels of care in calculating the limit:
- bound-point: safe when every home exports exactly the limit at once;
- phase-secure: also safe when the homes on one or two phases export nothing;
- dropout-secure: also safe when any one or two homes stop exporting (LV3) or any one home (LV9), checked with the realised reading. This is the one used for the headline result. The idea comes from Liu and Braslavsky (IEEE Access, 2022) and PowerOptLab's `doe_dropout_utilizations` (F. Geth).

**What is the "realised reading"?**
What actually happens on the true street when the limit is sent: each home may export up to its limit, and the inverters keep their Volt-VAr, Volt-Watt and 5 kVA settings. No voltage limit is imposed, so we can see how high the voltage really goes.

**Why is the gap sometimes zero or small?**
Either the limit is set by something other than voltage (for example the 5 kVA inverter size), or the supply voltage leaves plenty of room. A wrong cable record only matters when voltage is what sets the limit.

**Can I trust the calculator?**
With the same inverter outputs given to both programs, BMOPFTools and OpenDSS agree within 0.11 V (largest difference 0.103 V) at all 55 points of the 12-home street (neutral within 0.024 V). A separate rebuild of the main cases directly in OpenDSS (written with AI assistance and checked by the author; its files are not included in this repository) reproduced the key numbers (DATA_CARD.md, "How much to trust it"). Known differences and open points are listed in REPRODUCE.md section 6.

**Where does each number in the slides, plots or thesis come from?**
From the CSV files in `results/`. DATA_CARD.md explains every file and column, and the scripts in `figures/` draw the plots straight from those files.

**Is the AI part done?**
Not yet. This repository has the physics part. A labelled dataset is in progress. Testing whether a model trained on simulated smart-meter data can avoid the over-promise is a proposed next step, not yet agreed with my supervisors (README.md, "Status").

**Why are there scripts that are not in REPRODUCE.md?**
`scripts/01`-`05`, `count_linecodes.jl`, `sensitivity_service_cable.jl` and `scripts/study/` are early exploration on an older setup, kept so the history is complete. Each says so in its header.

**I found a problem.**
Please open an issue on GitHub. Thank you.
