# All figure numbers are read straight from the results files in ../results. Nothing is typed by hand.
import pandas as pd, os
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "results")
rd = lambda f: pd.read_csv(os.path.join(R, f))

# fig_wrong_record: LV3 12:00, 1.03 pu, dropout-secure DOE
_dr = rd("doe_dropout_records_lv3.csv")
_a = _dr[(_dr.setting == "day_1200") & (_dr.truth == "l_3432_wrong")].iloc[0]
_b = _dr[(_dr.setting == "day_1200") & (_dr.truth == "all22_wrong")].iloc[0]
assert abs(_a.issued_on_true_worst_V - _b.issued_on_true_worst_V) < 0.01 and _a.correct_kW_true == _b.correct_kW_true
WR = dict(correct=_a.correct_kW_true, issued=_a.issued_kW_records, v_issued=_a.issued_on_true_worst_V)

# fig_key: LV3 source sweep at 12:00 (all 22 service cables wrong, bound-point DOE)
_s = rd("doe_source_sweep.csv"); _s = _s[_s.setting == "day_1200"].sort_values("source_pu")
LV3_SWEEP_PU, LV3_SWEEP_GAP, LV3_SWEEP_BIND = list(_s.source_pu), list(_s.A_gap_kW), list(_s.clean_binding)
LV3_SWEEP_ISSUED = list(_s.clean_kW)
# LV9 sweep (12 shared cables wrong, bound-point DOE, 1 kW loads)
_l = rd("lv9/lv9_sweep.csv"); _l = _l[_l.case == "upstream_12"].sort_values("source_pu")
LV9_SWEEP_PU, LV9_SWEEP_GAP = list(_l.source_pu), list(_l.gap_kW)

# fig_safer: basic (bound-point) vs safer (dropout-secure) gap, same truth / loads / voltage
_dd = rd("doe_dirty_snapshot.csv").iloc[0]                      # CASE A, 1 kW snapshot, 1.03 pu
_rb = rd("doe_robust.csv"); _rb = _rb[(_rb.setting == "day_1200")].iloc[0]
_ld = rd("lv9/lv9_dropout_records.csv")
_ld = _ld[(_ld.source_pu == 0.94) & (_ld.truth == "upstream_12")].iloc[0]
_dsnap = _dr[(_dr.setting == "snapshot_1kW") & (_dr.truth == "all22_wrong")].iloc[0]
_d12 = _dr[(_dr.setting == "day_1200") & (_dr.truth == "all22_wrong")].iloc[0]
SAFER = [
    ("12-home street\neach home uses 1 kW", _dd.issued_limit_kW - _dd.correct_limit_kW, _dsnap.gap_kW),
    ("12-home street\nmidday", _rb.clean_kW - _rb.all_4mm2_kW, _d12.gap_kW),
    ("123-home street\neach home uses 1 kW", float(_l[_l.source_pu == 0.94].gap_kW.iloc[0]), _ld.gap_kW),
]
if __name__ == "__main__":
    print(WR); print(LV3_SWEEP_PU, [round(x, 3) for x in LV3_SWEEP_GAP], LV3_SWEEP_BIND)
    print(LV9_SWEEP_PU, [round(x, 3) for x in LV9_SWEEP_GAP]); print([(a, round(b, 3), round(c, 3)) for a, b, c in SAFER])
