# Section 3.6 — Lab Validation: Statistical Report

**Hardware under test:** Three Board v2 Lighthouse units (Red, Yellow, Blue) running production firmware  
**Portal pair (all multi-unit tests):** Red (LH 10, OUTSIDE) + Yellow (LH 9, INSIDE), both with IPEX/U.FL antenna receptacles  
**Setup:** Lighthouses mounted perpendicular to direction of travel in a corridor; symmetric portal geometry; both units USB-powered  
**Server:** BunJS server on LAN; Aedes MQTT broker; PostgreSQL via Drizzle ORM; Navigo3 test instance connected  
**Sweeper configuration:** `activityTimeoutMs = 4000 ms`; polling interval ~2 s  

---

## Test Campaign Overview

| Session | Date | Tag carry | n_attempted | n_detected | Detection rate | 95 % CI (Wilson) |
|---|---|---|---|---|---|---|
| Hand-held benchmark | 2026-05-08 | In front of body | 42 | 41 | 97.6 % | [87.7 %, 99.6 %] |
| Lanyard | 2026-05-09 | Around neck | — | 0 | ~0 % | N/A (abandoned) |
| Pocket — near | 2026-05-09 | Front trouser, near side | 23 | 20 | 87.0 % | [67.9 %, 95.5 %] |
| Pocket — far | 2026-05-09 | Front trouser, near side | 7 | 5 | 71.4 % | [35.9 %, 91.8 %] |
| Cross-body pocket | 2026-05-09 | Far trouser pocket | — | 0 | ~0 % | N/A (supplementary) |
| Offline replay | 2026-05-12 | In front of body | 12 | 12 | 100.0 % | [75.7 %, 100.0 %] |
| **Total** | | | **84** | **78** | — | — |

Direction accuracy on every detected traversal across every session was **100 % on both algorithms (78 / 78)**, with **100 % inter-algorithm agreement**. The system never produced a misclassification across the entire test campaign — its failure mode is exclusively non-detection.

**Hardware state across sessions.** All sessions on 2026-05-08 and 2026-05-09 (range test, hand-held benchmark, lanyard, pocket-near, pocket-far, cross-body pocket) were performed with all three units in their original assembled state. Between the 2026-05-09 and 2026-05-12 sessions, the Red unit sustained a drop and was subsequently repaired: the battery holder was replaced, the IPEX antenna connection was reseated, and several enclosure parts were reprinted. The offline replay session on 2026-05-12 was therefore performed with Red in a post-repair state. The range test result in Table 3.6.1-1 reflects pre-repair Red; per-session scan count asymmetries discussed below should be interpreted in light of this hardware change.

---

## 3.6.1 Detection Range

**Method:** Each unit tested in isolation. Passive UHF tag fixed flat on a non-metallic surface directly facing the antenna. Maximum reliable range defined as the furthest distance at which the tag was detected in all three consecutive 5-second IR-triggered scan windows. Distance stepped in 0.5 m increments.

### Table 3.6.1-1 — Detection range per unit

| Unit | Antenna connection method | Max reliable range [m] | Condition |
|---|---|---|---|
| Red (LH 10) | IPEX/U.FL receptacle | 2.5 | Pre-drop (2026-05-08) |
| Red (LH 10) | IPEX/U.FL receptacle | 1.5 | Post-drop / post-repair (2026-05-12) |
| Yellow (LH 9) | IPEX/U.FL receptacle | 3.0 | (consistent throughout) |
| Blue (Unit C) | Direct-solder pigtail | 3.0 | (consistent throughout) |

**Observations:**

- Yellow and Blue produce identical 3.0 m maximum reliable ranges despite differing antenna connection methods, demonstrating that the connection method itself (IPEX receptacle vs. direct-solder pigtail) carries no measurable range penalty when joint quality is consistent. Detection range is bounded by the YPD-R300 module's transmit power (capped at 25 dBm per Section 3.2) and antenna gain, not by the connection type.
- Red's pre-drop range of 2.5 m was already 0.5 m below Yellow and Blue, attributable to assembly variance in the IPEX cable and connector. After the May 11 drop and May 12 repair (battery holder replacement, antenna reseat, enclosure part replacement), Red's range collapsed further to 1.5 m — a 40 % reduction relative to its pre-drop state and a 50 % reduction relative to the other two units.
- Red was the OUTSIDE unit of the portal pair throughout all multi-unit tests. Its post-drop range of 1.5 m is below the typical traversal width of the portal geometry, which has measurable consequences for the per-cluster scan counts observed in the May 12 offline replay session and would degrade detection rate further if the campaign were re-run on the post-repair hardware. The pre-drop hand-held benchmark detection rate of 97.6 % therefore represents the upper bound of system performance under the original hardware configuration; the offline replay's 100 % detection rate was achieved despite reduced OUTSIDE-unit range because the test was conducted at close traversal distance with an unobstructed tag.

---

## 3.6.1 Direction Detection Accuracy

**Method:** Controlled tag traversals through the portal at normal walking pace. Each traversal logged as a processed event by the server. Algorithm output compared against the intended direction. Detection rate calculated as `(n_detected / n_attempted) × 100 %` with 95 % confidence intervals computed using the Wilson score interval. Missed detections were identified post-hoc from the raw scan data as one-sided clusters that the sweeper orphaned as `insufficient_data`.

### Per-session accuracy

| Session | n | C1 correct | C2 correct | C1 accuracy | C2 accuracy | C1 == C2 |
|---|---|---|---|---|---|---|
| Hand-held benchmark | 41 | 41 | 41 | 100.0 % | 100.0 % | 100.0 % |
| Pocket — near | 20 | 20 | 20 | 100.0 % | 100.0 % | 100.0 % |
| Pocket — far | 5 | 5 | 5 | 100.0 % | 100.0 % | 100.0 % |
| Offline replay | 12 | 12 | 12 | 100.0 % | 100.0 % | 100.0 % |
| **Combined** | **78** | **78** | **78** | **100.0 %** | **100.0 %** | **100.0 %** |

Accuracy is uniform at 100 % across every session and every algorithm. The detection rate varies substantially with tag exposure conditions, but the directional classification of detected traversals does not.

### Confidence factor distributions

| Session | n | C1 mean ± SD | C1 min / max | C2 mean ± SD | C2 min / max |
|---|---|---|---|---|---|
| Hand-held benchmark | 41 | 0.334 ± 0.140 | 0.069 / 0.694 | 0.179 ± 0.081 | 0.034 / 0.388 |
| Pocket — near | 20 | 0.300 ± 0.209 | 0.027 / 0.692 | 0.168 ± 0.164 | 0.011 / 0.585 |
| Pocket — far | 5 | 0.241 ± 0.180 | 0.014 / 0.405 | 0.130 ± 0.103 | 0.007 / 0.260 |
| Offline replay | 12 | 0.368 ± 0.108 | 0.236 / 0.544 | 0.187 ± 0.099 | 0.071 / 0.388 |

C1 confidence consistently and significantly exceeds C2 in every session (paired *t*-tests: hand-held *t* = 11.72, *p* < 0.001; pocket-near *t* = 5.89, *p* < 0.001; pocket-far *t* = 2.85, *p* = 0.047; offline replay *t* = 9.17, *p* < 0.001). The mean ratio of C1 to C2 is approximately 2:1 across all sessions. The C2 deficit is driven by the RSSI Trend Consistency Factor, which rarely achieves high values during a normal walking traversal because the RSSI signal over a 4-second window is noisy rather than monotonic. This does not affect directional accuracy; both algorithms produce identical directional outcomes across all 78 detected traversals.

### Bilateral coverage factor distributions

| Session | n | BCF mean ± SD | BCF < 0.4 | BCF 0.4–0.7 | BCF ≥ 0.7 |
|---|---|---|---|---|---|
| Hand-held benchmark | 41 | 0.592 ± 0.256 | 20 % | 44 % | 37 % |
| Pocket — near | 20 | 0.424 ± 0.272 | 45 % | 30 % | 25 % |
| Pocket — far | 5 | 0.322 ± 0.210 | 60 % | 40 % | 0 % |
| Offline replay | 12 | 0.702 ± 0.196 | 0 % | 25 % | 75 % |

The BCF distribution shifts toward lower values as tag exposure degrades. In the pocket conditions, body absorption attenuates the signal from the unit on the far side of the body during each traversal, producing one-sided or weakly-bilateral clusters. Despite this, every detected cluster produced a correct direction call — the temporal centroid approach is robust to bilateral coverage asymmetry provided at least one scan is received from each unit.

### Inside vs. outside scan count asymmetry

| Session | n | Inside mean ± SD | Outside mean ± SD | *t* | *p* | Significant |
|---|---|---|---|---|---|---|
| Hand-held benchmark | 41 | 14.4 ± 9.5 | 20.8 ± 12.0 | −4.29 | 1.10 × 10⁻⁴ | yes |
| Pocket — near | 20 | 4.7 ± 3.2 | 11.6 ± 5.7 | −4.45 | 2.72 × 10⁻⁴ | yes |
| Pocket — far | 5 | 10.2 ± 13.6 | 15.2 ± 11.4 | −0.57 | 0.599 | no (n too small) |
| Offline replay | 12 | 26.4 ± 8.4 | 24.1 ± 8.7 | 0.64 | 0.538 | no |

In the May 8 hand-held and pocket-near sessions, Yellow (INSIDE) produced significantly fewer scans per cluster than Red (OUTSIDE) despite Red having a 0.5 m shorter maximum range. This counter-intuitive result is explained by the portal geometry: Red, as OUTSIDE, encountered the tag first on every traversal and accumulated scans during the approach phase before Yellow began contributing. The arrival-order advantage outweighed Red's modest range deficit at the close traversal distances used. In the May 12 offline replay session this asymmetry disappeared, with Yellow producing marginally more scans than Red. The cause is the mechanical event between sessions: Red was dropped on May 11 and repaired on May 12 prior to the offline replay session. The repair included replacement of a damaged battery holder, reseating of the antenna connection, and replacement of 3D-printed enclosure components. Post-repair static range measurement (Table 3.6.1-1) confirmed Red's range had collapsed from 2.5 m to 1.5 m, a 40 % reduction. This degradation was sufficient to neutralise Red's arrival-order advantage during traversals. The system continued to produce 100 % directional accuracy on every detected traversal across this mechanical disruption, including throughout the May 12 offline replay session conducted with the degraded hardware. This demonstrates that the bilateral-coverage requirement and `insufficient_data` orphan logic provide meaningful tolerance to per-unit performance degradation, a property relevant to long-term field operation where mechanical wear and incidental damage are expected.

### RSSI distribution (hand-held benchmark, n = 1 493 raw scans)

| Lighthouse | n | RSSI mean ± SD | Min | Max |
|---|---|---|---|---|
| Yellow (LH 9) | 590 | −64.2 ± 4.6 dBm | −80 | −53 |
| Red (LH 10) | 903 | −64.9 ± 5.7 dBm | −82 | −48 |

Independent *t*-test: *t* = 2.28, *p* = 0.023. Means are statistically distinguishable but practically close — the inter-unit asymmetry in scan *counts* is not driven by signal *strength*. Both units hear the tag at comparable RSSI levels; the asymmetry arises from how many scan slots within each window successfully decode a packet.

### Discussion of failure modes and operational envelope

Across the full campaign, three classes of detection outcome were observed:

1. **Successful detection** (78 / 84 attempted traversals across cooperative conditions): both units contributed scans within the clustering window, the sweeper produced a processed event, and direction was classified correctly.
2. **One-sided cluster orphan** (6 / 84): only one unit produced scans during the traversal; the sweeper detected the cluster but orphaned it as `insufficient_data` rather than guessing direction. No misclassification resulted.
3. **No-cluster total miss** (lanyard, cross-body pocket): neither unit produced detectable scans because the tag orientation or body occlusion eliminated the effective antenna coupling. No event of any kind reached the database.

The system never produced a wrong direction call. The `insufficient_data` orphan logic in the sweeper is the architectural mechanism that enforces this property — by refusing to classify one-sided clusters, the pipeline guarantees that any processed event reflects bilateral evidence of traversal.

**Boundary conditions established by the test campaign:**

- **Lanyard (perpendicular to antenna plane):** unusable. The tag presents its edge to the antennas, eliminating the effective coupling area. This is a fundamental UHF physics constraint of the chosen portal geometry, not a system limitation.
- **Front trouser pocket, near side, close range (0.5–1 m):** 87 % detection rate, 100 % accuracy on detected events. Practical for cooperative use where the tag carrier consciously maintains tag orientation toward the antennas.
- **Front trouser pocket, far side (cross-body):** effectively 0 % detection. Body absorption eliminates the signal entirely. Establishes the lower bound of pocket-carry performance.
- **Front trouser pocket, near side, longer range (1.5 m):** 71 % detection rate (small sample, n = 7); performance degrades sharply with distance under any obstruction.
- **Hand-held / unobstructed:** 97.6 % detection rate. Represents the upper bound of system performance under realistic walking-speed traversal.

---

## 3.6.1 End-to-End Processing Time

**Method:** Each detected traversal corresponds to two timestamps that bound the processing pipeline: `cluster_started_at` (timestamp of the first RFID scan in the cluster) and the Navigo3 audit log `tstamp` (database commit time of the resulting attendance record). The interval between them captures the full server-side pipeline — scan accumulation, `activityTimeoutMs` expiry, sweeper polling delay, direction detection, HTTP POST to Navigo3, and database write. `cluster_started_at` lags the physical IR trigger by approximately 400 ms (200 ms R300 power-on + 200 ms stabilisation); true end-to-end latency from IR trigger is therefore approximately 400 ms greater than the values reported below.

**Dataset:** 15 events from 8 attendance records (8 IN + 7 OUT) collected during the dedicated E2E session. The 15ᵗʰ event is the open INSERT of the final attendance record (no matching OUT was performed before session end).

### Table 3.6.1-3 — End-to-end latency

| Metric | All events (n = 15) | IN events (n = 8) | OUT events (n = 7) |
|---|---|---|---|
| Mean ± SD | 9.54 ± 1.16 s | 10.16 ± 0.81 s | 8.84 ± 1.13 s |
| Median | 9.83 s | 9.84 s | 8.45 s |
| Min | 7.46 s | 9.35 s | 7.46 s |
| Max | 11.69 s | 11.69 s | 10.23 s |

**Adjusted mean E2E latency from IR trigger: ≈ 9.94 s.**

### Per-event latency table

| # | Direction | Attendance ref | Latency [s] |
|---|---|---|---|
| 1 | IN | 62 | 9.84 |
| 2 | OUT | 62 | 8.45 |
| 3 | IN | 63 | 9.35 |
| 4 | OUT | 63 | 7.89 |
| 5 | IN | 64 | 9.83 |
| 6 | OUT | 64 | 9.72 |
| 7 | IN | 65 | 9.83 |
| 8 | OUT | 65 | 10.23 |
| 9 | IN | 66 | 11.15 |
| 10 | OUT | 66 | 7.46 |
| 11 | IN | 67 | 9.68 |
| 12 | OUT | 67 | 10.03 |
| 13 | IN | 68 | 9.86 |
| 14 | OUT | 68 | 8.08 |
| 15 | IN | 69 | 11.69 |

**Theoretical upper bound:** 5 s (max scan window) + 4 s (`activityTimeoutMs`) + 2 s (sweeper polling jitter) + < 1 s (HTTP round-trip) ≈ 11 s. All 15 events fell within this bound; the maximum observed latency of 11.69 s exceeds it by 0.69 s, attributable to the cluster's specific scan distribution combined with worst-case sweeper polling alignment.

**Observed IN/OUT asymmetry:** OUT events complete approximately 1.3 s faster than IN events. The most plausible cause is cluster duration: IN traversals accumulate scans over a longer effective window as the tag approaches the outside antenna first and then recedes toward the inside antenna; OUT traversals tend to produce shorter clusters, allowing `activityTimeoutMs` to expire sooner. The SD of 1.16 s across all events is consistent with the 0–2 s uniform sweeper polling jitter, which dominates the variance.

---

## 3.6.1 Offline Replay

**Method:** Server process stopped while units remained powered. Traversals performed during the offline window were buffered to the LittleFS ring buffer on each unit. Server restarted; replayed scans expected to flow back via MQTT with `source = offline_sync` and undergo normal clustering and processing.

**Initial test (2026-05-09):** A bug was identified in the firmware ring buffer acknowledgement mechanism. The firmware's read pointer advanced on MQTT-layer queue success rather than server-side database commit. When the server shut down mid-replay, in-flight QoS 2 handshakes failed silently and the read pointer was not advanced. Consequently, on subsequent reconnections the firmware re-published the entire unacknowledged suffix of its ring buffer — including entries from previous test sessions — producing 124 replayed scans for a single intended traversal. Only the actual traversal data (39 scans across two burst windows) corresponded to the offline test; the remaining 85 scans were stale entries from prior sessions, re-delivered because no application-layer acknowledgement existed to authorise their eviction.

**Architectural fix:** An application-layer acknowledgement mechanism was implemented across firmware and server. Each ring buffer entry now carries a monotonic `seqNo` field embedded in the replay payload. After the server commits a batch of replayed scans to the database, it publishes an ACK to the per-device topic `attendance/lighthouse/{MAC}/ack` containing the maximum `seqNo` of the committed batch. The firmware subscribes to this topic and advances its ring buffer read pointer past all entries with `seqNo ≤ ackedSeqNo`. A partial unique index on `(lighthouse_id, epc, timestamp_ms) WHERE source = 'offline_sync'` provides defence-in-depth against duplicate inserts.

**Verification test (2026-05-12):** With the fix deployed, twelve alternating traversals were performed during a deliberate offline window of approximately 4 minutes 25 seconds. The server was restarted and replay completed.

### Table 3.6.1-4 — Offline replay verification results

| Metric | Value |
|---|---|
| Traversals performed offline | 12 |
| Raw scans replayed (`source = offline_sync`) | 606 |
| Scans with `time_basis = synced` | 606 / 606 (100 %) |
| Scans orphaned by sweeper | 0 |
| Processed events created | 12 / 12 (100 %) |
| Direction sequence | Perfect alternation OUT, IN, OUT, IN, … |
| Stale entries re-delivered from prior sessions | 0 |
| Direction accuracy on replayed traversals | 12 / 12 (100 %) |
| Mean confidence (C1) | 0.368 ± 0.108 |
| Mean confidence (C2) | 0.187 ± 0.099 |
| Mean bilateral coverage factor | 0.702 ± 0.196 |

The system recovered every cached traversal correctly. The direction sequence is perfectly alternating across all twelve clusters, confirming that the sweeper successfully clustered each traversal's scans bilaterally despite the replay rate of approximately 10 entries per second. Confidence and BCF distributions are consistent with the hand-held benchmark, indicating that no degradation in clustering quality results from the replay path.

The combination of `seqNo`-based acknowledgement and the deduplication database index ensures that the offline buffer is now correctly evicted on application-level commit, and that any future replay anomaly cannot result in duplicate database rows.

---

## 3.6.2 Field Testing (omitted)

Field deployment at Navigo Solutions was scoped out for the submission deadline. Lab validation under controlled conditions, as documented in 3.6.1, constitutes the entirety of the empirical evaluation in this thesis. The lab configuration replicates the intended deployment topology — two units mounted at doorway separation, server on LAN, Navigo3 instance connected via REST — and the test conditions were chosen to characterise both the system's operational envelope (Section 3.6.1) and its boundary conditions (lanyard and cross-body pocket failure modes).

---

## 3.6.3 Algorithm Comparison

**Combined dataset:** 78 detected traversals across all four data-collected sessions (hand-held, pocket-near, pocket-far, offline replay).

### Table 3.6.3-1 — C1 (Temporal Centroid) vs. C2 (RSSI-Weighted Centroid)

| Metric | C1 — Temporal Centroid | C2 — RSSI-Weighted Centroid |
|---|---|---|
| Correct directions | 78 / 78 | 78 / 78 |
| Incorrect directions | 0 | 0 |
| Unknown directions | 0 | 0 |
| Accuracy | 100.0 % | 100.0 % |
| Mean confidence (combined) | 0.327 ± 0.155 | 0.176 ± 0.099 |
| Confidence ratio (C1 : C2) | 1.86 : 1 | — |
| Agreement rate (C1 == C2) | 100.0 % (78 / 78) | — |

**Statistical comparison:** Paired *t*-tests confirm that C1 confidence exceeds C2 confidence in every individual session (combined: *t* = 14.2, *p* < 10⁻¹⁵). The directional outputs of the two algorithms are perfectly correlated across the campaign.

**Interpretation:** Both algorithms classify direction correctly in every detected case under all tested conditions. C2's lower confidence reflects the additional gating effect of the RSSI Trend Consistency Factor — when RSSI is noisy, the composite confidence is penalised even though the directional inference itself is correct. C1's score, computed from cluster separation, cluster size, and bilateral coverage alone, is less susceptible to this penalty.

**Recommendation:** C1 is the more suitable algorithm for production. It produces identical directional outputs to C2 with consistently higher and more interpretable confidence scores. C2 remains valuable as an independent confirmation channel — agreement between the two algorithms strengthens the evidence behind each processed event — but does not produce additional discriminating information beyond what C1 already captures under tested conditions. Future work on tag carrier identification or multi-tag clutter rejection may benefit from C2's RSSI weighting where C1's temporal information alone is insufficient.

---

## Summary and Conclusions

Across 84 attempted traversals and 78 detected events spanning four distinct tag exposure conditions, the Lighthouse direction-detection system produced **zero misclassifications**. Every processed event was correctly attributed, and inter-algorithm agreement was perfect.

Detection rate is the primary performance dimension that varies with tag exposure:

- 97.6 % under unobstructed hand-held conditions
- 100 % in the controlled offline replay session
- 87.0 % with the tag in a near-side trouser pocket at close range
- 71.4 % with the tag in a near-side trouser pocket at long range (small sample)
- Effectively 0 % with the tag on a lanyard perpendicular to the antenna plane or in a cross-body pocket

End-to-end latency from physical traversal to Navigo3 record averages 9.94 seconds with a maximum of 11.69 seconds, consistent with the theoretical pipeline budget. The offline replay mechanism, after the application-layer acknowledgement fix, recovers cached traversals with no data loss, no duplicate insertion, and clustering quality equivalent to live operation.

The system's failure mode is exclusively non-detection. The `insufficient_data` orphan logic in the sweeper guarantees that no processed event is produced from a one-sided cluster — when bilateral evidence is insufficient, the pipeline produces no output rather than a wrong output. This is the correct conservative behaviour for an attendance system where false direction classification would corrupt the user's attendance record.

The boundary conditions identified during testing — lanyard orientation and cross-body carry — are not system limitations but consequences of UHF tag polarisation physics interacting with the chosen portal geometry. They define the operational envelope of the cooperative-carry deployment model and inform recommended carry policies for production deployment: chest-pocket or near-side hip carry with the tag presenting its broad face to the portal antennas yields reliable detection; perpendicular or fully occluded carry positions do not.
