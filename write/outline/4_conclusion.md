# OSNOVA PLUS - 4. conclusion

- A passive, hands-free UHF RFID attendance system was designed and implemented from the ground up: two custom
  Lighthouse units, a BunJS/PostgreSQL server with an embedded MQTT broker, a SolidJS operator dashboard, and a Navigo3
  integration layer
- The system achieves the goal of zero employee interaction: tags are detected passively at walking pace without
  any deliberate action from the tag carrier
- All four thesis goals from the assignment were addressed:
  - (1) review of identification technologies and direction detection methods - completed in Chapter 2
  - (2) architecture design - portal model with server-side processing documented in Chapter 3
  - (3) prototype implementation - two Board v2 units in enclosures, full firmware and server pipeline
  - (4) system verification - lab validation performed; field deployment at Navigo Solutions pending
- Lab validation confirmed end-to-end operation: tag traversal through the portal produces a correctly
  directed attendance record in Navigo3; detection range and direction detection accuracy measured and documented
  in Section 3.6.1
- Both direction detection algorithms (Temporal Centroid C1, RSSI-Weighted Centroid C2) were implemented and
  evaluated; algorithm comparison findings and the deployment recommendation are in Section 3.6.3
- Known limitations of the current prototype:
  - Absence of a hardware RTC on the ESP32 - timekeeping relies on SNTP; timestamp quality degrades during
    prolonged network outages (mitigated by `timeBasis` field and NVS-persisted last-known time)
  - Single antenna per unit - no spatial diversity; detection reliability is sensitive to antenna placement
    and the quality of the RF feed path (antenna cable joint)
- The integration layer is isolated behind a connector interface - the system is not inherently tied to Navigo3
  and can be extended to other enterprise platforms
- Directions for future work:
  - Hardware RTC on a future board revision to eliminate timestamp degradation during offline periods
  - Refinement and proper IPEX/U.FL receptacle placement on the PCB to eliminate antenna connection variability
  - Extended field testing over a full working day with real employee traffic
  - Improved API and web interface with proper authentification and session management
