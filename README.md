# Vision-Gated Safety Interlock for High-Pressure Test Bays

Firmware, vision host, and simulation code for a microcontroller-driven safety
interlock system that unifies pressure sensing, RFID authentication, and
computer-vision human-presence detection into one deterministic decision.

**Author:** Promise Oluwaseyi Osunyemi, Department of Electronic and Electrical
Engineering, Obafemi Awolowo University, Ile-Ife, Nigeria

This repository accompanies the paper *"A Microcontroller-Driven, Vision-Gated
Safety Interlock System for High-Pressure Industrial Test Bays"* (Osunyemi).

## Control logic
The door is a three-state machine, the same in the firmware and the Stateflow model:

    LATCHED  -> UNLOCKED   valid card AND pressure reads zero
    UNLOCKED -> CLEARING   bay reads clear (H = 0)
    CLEARING -> UNLOCKED   person seen again (H = 1), clear timer restarts
    CLEARING -> LATCHED    bay has stayed clear for 3 s

    M = 1 only in LATCHED
    P = M AND (NOT H) AND Pr       (pressurise only when sealed, clear, rising)

A person detected while the door is latched does not unlock it; it removes the
pressurisation permission. A person detected while the door is open stops it
from latching. If the vision host stops sending for 2 s, the firmware treats
the bay as occupied.

## Repository layout
    PressureRoomLock_CV.ino     Arduino (ATmega328P) interlock firmware, with the
                                computer-vision presence layer over serial.
    PressureRoomLock.ino        Earlier RFID/pressure/lock firmware (reference).
    cv_serial_bridge.py         Host-side YOLOv8 person detector with multi-camera
                                OR-fusion and asymmetric debounce; sends a single
                                '1'/'0' presence byte to the Arduino over serial.
    build_interlock_model.m     Builds the Simulink/Stateflow model of the control
                                logic programmatically, runs the test scenario and
                                prints the switching times.
    pressure_vector.m           Illustrative model of a 4-20 mA -> shunt -> ADC
                                chain for a future transducer (see the note below).
    control_loop_pseudocode.txt The interlock loop in plain steps.

## Requirements
- Firmware: Arduino IDE; libraries MFRC522 and LiquidCrystal_I2C.
- Vision: Python 3.9+, `pip install ultralytics opencv-python pyserial`.
- Simulation: MATLAB with Simulink and Stateflow (R2023b or later).

## Hardware
Arduino Uno (ATmega328P), MFRC522 RFID reader, SRD-05VDC-SL-C relay module,
12 V electric lock, 16x2 I2C LCD, active buzzer, 10 kOhm rheostat
(pressure proxy on A0), 1N4007 flyback diode, 12 V 2 A supply. Pin map: RFID on
SPI (D10-D13, D9), LCD on I2C (A4/A5), rheostat on A0, relay on D7, buzzer on D8,
presence flag over USB serial.

## Notes and known limitations
- Pressure on the prototype is a rheostat on A0. The firmware treats pressure as
  zero when `map(analogRead(A0), 0, 1023, 0, 100) == 0`, that is an ADC code of
  10 or below (about 1% of span). It does not use a 4 mA live zero.
- With the rheostat, a broken wire reads as zero pressure, so a card could unlock
  a pressurised bay. This is not covered in the prototype. A real deployment
  should use a 4-20 mA transducer and treat a reading below about 3.6 mA as a
  fault (NAMUR NE 43), with the firmware threshold moved to the 4 mA zero.
- Whether the door fails locked or unlocked on power loss depends on the lock
  type and on whether it is wired to the relay's normally open or normally
  closed contact. Check this for your own build.
- The door being "provably unoccupied" when latched holds only if the detector
  never misses a person. Missed detections are a failure mode in their own right.
- `pressure_vector.m` is an illustration of the signal chain, not a measurement.

## Changes in v1.1
- `build_interlock_model.m`: the chart now has three states (LATCHED, UNLOCKED,
  CLEARING). In v1.0, `after(3,sec)[H==0]` counted from when the door unlocked,
  not from when the bay went clear, so in the test scenario the door latched at
  12 s instead of 15 s. The v1.1 model matches the firmware. Expected output:
  M falls at 7 s and rises at 15 s; P rises at 2 s, falls at 5 s, rises at 16 s.
- README and pseudocode now describe the state machine used by the firmware.

## How to run the demonstration
1. Upload `PressureRoomLock_CV.ino` to the Arduino.
2. Set `SERIAL_PORT` and `CAMERA_SOURCES` in `cv_serial_bridge.py`.
3. Close the Arduino Serial Monitor, then run `python cv_serial_bridge.py`.
4. Step into the camera view to raise H and observe the interlock respond.

## License
MIT License (see LICENSE).

## Citation
If you use this work, please cite the paper and this archive (see CITATION.cff).
