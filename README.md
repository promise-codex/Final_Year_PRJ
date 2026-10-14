# Vision-Gated Safety Interlock for High-Pressure Test Bays

Firmware, vision host, and simulation code for a microcontroller-driven safety
interlock system that unifies pressure sensing, RFID authentication, and
computer-vision human-presence detection into one deterministic decision.

This repository accompanies the paper *"A Microcontroller-Driven, Vision-Gated
Safety Interlock System for High-Pressure Industrial Test Bays"* (Osunyemi,
Department of Electronic and Electrical Engineering, Obafemi Awolowo University).

## Control law
    M = NOT H                     (door latches only when the bay is clear)
    P = M AND (NOT H) AND Pr       (pressurise only when sealed, clear, rising)
A detected person (H=1) both prevents the door from latching and blocks
pressurisation.

## Repository layout
    firmware/
      PressureRoomLock_CV.ino   Arduino (ATmega328P) interlock firmware, with the
                                computer-vision presence layer over serial.
      PressureRoomLock.ino      Earlier RFID/pressure/lock firmware (reference).
    vision/
      cv_serial_bridge.py       Host-side YOLOv8 person detector with multi-camera
                                OR-fusion and asymmetric debounce; sends a single
                                '1'/'0' presence byte to the Arduino over serial.
    simulation/
      build_interlock_model.m   Builds the Simulink/Stateflow model of the control
                                logic programmatically and runs a test scenario.
      pressure_vector.m         Models the 4-20 mA -> shunt -> ADC chain and plots
                                the digital threshold against analog hysteresis.

## Requirements
- Firmware: Arduino IDE; libraries MFRC522 and LiquidCrystal_I2C.
- Vision: Python 3.9+, `pip install ultralytics opencv-python pyserial`.
- Simulation: MATLAB with Simulink and Stateflow (R2023b or later).

## Hardware
Arduino Uno (ATmega328P), MFRC522 RFID reader, SRD-05VDC-SL-C relay module,
12 V solenoid lock (fail-secure), 16x2 I2C LCD, active buzzer, 10 kOhm rheostat
(pressure proxy on A0), 1N4007 flyback diode, 12 V 2 A supply. Pin map: RFID on
SPI (D10-D13, D9), LCD on I2C (A4/A5), rheostat on A0, relay on D7, buzzer on D8,
presence flag over USB serial.

## How to run the demonstration
1. Upload `firmware/PressureRoomLock_CV.ino` to the Arduino.
2. Set `SERIAL_PORT` and `CAMERA_SOURCES` in `vision/cv_serial_bridge.py`.
3. Close the Arduino Serial Monitor, then run `python vision/cv_serial_bridge.py`.
4. Step into the camera view to raise H and observe the interlock respond.

## License
MIT License (see LICENSE).

## Citation
If you use this work, please cite the paper and this archive (see CITATION.cff).
