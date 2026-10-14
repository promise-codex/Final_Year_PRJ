"""
Vision host for the safety interlock. Runs YOLO on one or more cameras,
fuses them, and sends a presence byte ('1' person / '0' clear) to the Arduino
over serial each cycle. Clear is only reported when every camera agrees.

Needs: pip install ultralytics opencv-python pyserial
"""

import time
import cv2
from ultralytics import YOLO
import serial
import serial.tools.list_ports

# one webcam -> [0]; for the bay use the RTSP URLs of the IP cameras
CAMERA_SOURCES = [0]

SERIAL_PORT    = "AUTO"      # or e.g. "COM5" / "/dev/ttyACM0"
BAUD_RATE      = 9600
CONF_THRESHOLD = 0.35
CLEAR_FRAMES   = 8           # clear frames in a row before dropping H to 0
MODEL_NAME     = "yolov8n.pt"
USE_DSHOW      = True        # Windows webcams
SHOW_WINDOWS   = True


def find_arduino_port():
    ports = list(serial.tools.list_ports.comports())
    for p in ports:
        desc = (p.description or "").lower()
        manu = (p.manufacturer or "").lower()
        if any(k in desc for k in ["arduino", "ch340", "usb-serial", "usb serial", "wch"]) \
           or "arduino" in manu or "wch" in manu:
            return p.device
    if len(ports) == 1:
        return ports[0].device
    return None


def open_serial():
    port = SERIAL_PORT
    if port == "AUTO":
        port = find_arduino_port()
    if not port:
        print("No Arduino serial port found. Ports available:")
        for p in serial.tools.list_ports.comports():
            print("  ", p.device, "-", p.description)
        print("Set SERIAL_PORT manually and re-run.")
        return None
    try:
        ser = serial.Serial(port, BAUD_RATE, timeout=0)
        time.sleep(2)   # Uno resets when the port opens
        print("Serial open on", port, "@", BAUD_RATE)
        return ser
    except Exception as e:
        print("Could not open", port, ":", e)
        return None


def open_cameras():
    caps = []
    for src in CAMERA_SOURCES:
        if isinstance(src, int) and USE_DSHOW:
            cap = cv2.VideoCapture(src, cv2.CAP_DSHOW)
        else:
            cap = cv2.VideoCapture(src)
        if cap.isOpened():
            print("Opened camera", src)
            caps.append((src, cap))
        else:
            print("Could not open camera", src, "- skipping")
    return caps


def detect_person(model, frame):
    results = model(frame, classes=[0], verbose=False)
    found = False
    for r in results:
        for box in r.boxes:
            conf = float(box.conf[0])
            if conf > CONF_THRESHOLD:
                found = True
                x1, y1, x2, y2 = map(int, box.xyxy[0])
                cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
                cv2.putText(frame, f"Person {conf:.2f}", (x1, y1 - 8),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
    return found, frame


def main():
    print("Loading model...")
    model = YOLO(MODEL_NAME)

    ser = open_serial()
    caps = open_cameras()
    if not caps:
        print("No cameras opened. Check the index / privacy settings / RTSP URLs.")
        return

    print(len(caps), "camera(s) running. Press q to quit.")

    H = 1               # assume occupied until a run of clear frames
    clear_streak = 0
    last_sent = None

    try:
        while True:
            per_camera = []
            for src, cap in caps:
                ret, frame = cap.read()
                if not ret:
                    per_camera.append(True)   # no frame -> can't prove clear
                    continue
                found, annotated = detect_person(model, frame)
                per_camera.append(found)
                if SHOW_WINDOWS:
                    tag = "PERSON" if found else "clear"
                    col = (0, 0, 255) if found else (0, 255, 0)
                    cv2.putText(annotated, f"Cam {src}: {tag}", (10, 30),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.8, col, 2)
                    cv2.imshow(f"Camera {src}", annotated)

            # person if any camera sees one
            if any(per_camera):
                H = 1
                clear_streak = 0
            else:
                clear_streak += 1
                if clear_streak >= CLEAR_FRAMES:
                    H = 0

            if ser is not None:
                try:
                    ser.write(b'1' if H else b'0')
                except Exception as e:
                    print("Serial write failed:", e)

            if H != last_sent:
                print(("H=1 PERSON DETECTED" if H else "H=0 BAY CLEAR"),
                      "| per-camera:", per_camera)
                last_sent = H

            if SHOW_WINDOWS and cv2.waitKey(1) == ord('q'):
                break
            if not SHOW_WINDOWS:
                time.sleep(0.03)

    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        # leave the Arduino with "person present" so it won't latch once we're gone
        if ser is not None:
            try:
                ser.write(b'1')
                ser.close()
            except Exception:
                pass
        for _, cap in caps:
            cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
