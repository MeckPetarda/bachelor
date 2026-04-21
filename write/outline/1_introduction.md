# OSNOVA PLUS - 1. introduction

- Enterprise attendance tracking - routine operational need feeding payroll, project time allocation, compliance
- Dominant solutions (PIN terminals, HF RFID card readers, biometrics) share a common flaw: require deliberate employee
  interaction at a fixed point; friction, bottlenecks, buddy-punching
- Concrete motivation: need at Navigo Solutions s.r.o. (Brno) - passive, zero-interaction attendance recording feeding
  directly into Navigo3 HR software
- Core technical challenge: (1) passive identification at 2-3 m range through bags and pockets, (2) direction of
  traversal - arrival vs. departure - without physical gates
- UHF RFID (860-960 MHz) - only commercially mature technology meeting the passive, hands-free range requirement
- Direction detection requires two spatially separated units: a single reader cannot distinguish entry from exit;
  **portal model** - two Lighthouse units mounted on opposite sides of a doorway; raw RFID readings jointly analysed
  server-side; traversal direction inferred from temporal sequence
- Each Lighthouse: autonomous embedded device with UHF RFID reader, WiFi/MQTT, battery backup; publishes raw readings
  only - no local direction decisions
- Server hosts detection pipeline, database, operator dashboard, and enterprise integration layer
- Integration target: Navigo3; integration layer isolated behind a connector interface - extensible to other enterprise
  platforms without changes to the core pipeline

**[Figure 1-1: System concept diagram - two Lighthouse units flanking a doorway, person walking through, MQTT to server,
server to Navigo3; simplified version of Figure 3.1-1]**
