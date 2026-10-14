// Pressure room safety interlock - Arduino Uno
// RFID access + pressure check + human presence (from vision host over serial).
// Relay is active-low: HIGH = latched (solenoid off), LOW = unlocked.

#include <SPI.h>
#include <MFRC522.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

#define SS_PIN     10
#define RST_PIN     9
#define BUZZER_PIN  8
#define RELAY_PIN   7
#define POT_PIN    A0

#define DOOR_LATCH   HIGH
#define DOOR_UNLOCK  LOW

const unsigned long CLEAR_LATCH_MS   = 3000;   // auto-latch once bay stays clear this long
const unsigned long SERIAL_STALE_MS  = 2000;   // no update this long -> assume someone's inside
const unsigned long LCD_REFRESH_MS   = 250;

MFRC522 rfid(SS_PIN, RST_PIN);
LiquidCrystal_I2C lcd(0x27, 16, 2);

byte authorizedUID[4] = {0xA3, 0x20, 0xDF, 0x24};

bool isUnlocked      = false;
bool personPresent   = true;    // start true until the host says the bay is clear
unsigned long lastSerialMs   = 0;
unsigned long bayClearSince  = 0;
unsigned long lastLcdMs      = 0;
char lastShownLine0[17] = "";

void readPresence();
void handleRFID();
void serviceAutoLatch();
void refreshDisplay();
void latchDoor(const char *reason);
void beep(unsigned int ms);
void showTwoLines(const char *l1, const char *l2);
void delayMessage(unsigned long ms);

void setup() {
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, DOOR_LATCH);
  digitalWrite(BUZZER_PIN, LOW);

  Serial.begin(9600);

  SPI.begin();
  rfid.PCD_Init();

  lcd.init();
  lcd.backlight();

  lastSerialMs  = millis();
  bayClearSince = 0;
}

void loop() {
  readPresence();
  serviceAutoLatch();
  handleRFID();
  refreshDisplay();
}

// Host streams '1'/'0'. Take the latest byte, ignore anything else.
void readPresence() {
  bool gotUpdate = false;
  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    if (c == '1') { personPresent = true;  gotUpdate = true; }
    else if (c == '0') { personPresent = false; gotUpdate = true; }
  }

  if (gotUpdate) {
    lastSerialMs = millis();
    if (!personPresent) {
      if (bayClearSince == 0) bayClearSince = millis();
    } else {
      bayClearSince = 0;
    }
  }

  if (millis() - lastSerialMs > SERIAL_STALE_MS) {
    personPresent = true;
    bayClearSince = 0;
  }
}

void serviceAutoLatch() {
  if (isUnlocked && !personPresent && bayClearSince != 0) {
    if (millis() - bayClearSince >= CLEAR_LATCH_MS) {
      latchDoor("Bay clear: locked");
    }
  }
}

void handleRFID() {
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) {
    return;
  }

  bool cardMatches = true;
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (i >= 4 || rfid.uid.uidByte[i] != authorizedUID[i]) {
      cardMatches = false;
      break;
    }
  }
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();

  int potPercentage = map(analogRead(POT_PIN), 0, 1023, 0, 100);

  if (cardMatches) {
    if (!isUnlocked) {
      if (potPercentage == 0) {
        isUnlocked = true;
        digitalWrite(RELAY_PIN, DOOR_UNLOCK);
        bayClearSince = 0;
        showTwoLines("Access Granted", "Door Unlocked");
        beep(1000);
        lcd.clear();
        lastShownLine0[0] = '\0';
      } else {
        showTwoLines("Access Denied", "Pressure high!");
        beep(0);
        delayMessage(2000);
        lcd.clear();
        lastShownLine0[0] = '\0';
      }
    } else {
      showTwoLines("Already Unlocked", "Auto-locks clear");
      beep(300);
      lcd.clear();
      lastShownLine0[0] = '\0';
    }
  } else {
    showTwoLines("Invalid Card", "Access Denied");
    digitalWrite(BUZZER_PIN, HIGH); delayMessage(150); digitalWrite(BUZZER_PIN, LOW); delayMessage(150);
    digitalWrite(BUZZER_PIN, HIGH); delayMessage(150); digitalWrite(BUZZER_PIN, LOW);
    delayMessage(800);
    lcd.clear();
    lastShownLine0[0] = '\0';
  }

  rfid.PCD_Init();   // reader tends to lock up after the relay switches
}

void refreshDisplay() {
  if (millis() - lastLcdMs < LCD_REFRESH_MS) return;
  lastLcdMs = millis();

  int potPercentage = map(analogRead(POT_PIN), 0, 1023, 0, 100);

  char line0[17];
  char line1[17];

  if (isUnlocked) {
    if (personPresent) {
      strcpy(line0, "Person inside   ");
    } else {
      strcpy(line0, "Clear-locking...");
    }
    snprintf(line1, sizeof(line1), "Pressure: %d%%   ", potPercentage);
  } else {
    if (!personPresent && potPercentage > 0) {
      strcpy(line0, "PUMP ON: Pressn ");
      snprintf(line1, sizeof(line1), "Pressure: %d%%   ", potPercentage);
    } else {
      strcpy(line0, "Scan card...    ");
      snprintf(line1, sizeof(line1), "Pressure: %d%%   ", potPercentage);
    }
  }

  if (strcmp(line0, lastShownLine0) != 0) {
    lcd.setCursor(0, 0);
    lcd.print(line0);
    strcpy(lastShownLine0, line0);
  }
  lcd.setCursor(0, 1);
  lcd.print(line1);
}

void latchDoor(const char *reason) {
  isUnlocked = false;
  digitalWrite(RELAY_PIN, DOOR_LATCH);
  bayClearSince = 0;
  showTwoLines("Door Latched", reason);
  beep(600);
  lcd.clear();
  lastShownLine0[0] = '\0';
}

void beep(unsigned int ms) {
  if (ms == 0) return;
  digitalWrite(BUZZER_PIN, HIGH);
  delayMessage(ms);
  digitalWrite(BUZZER_PIN, LOW);
}

void showTwoLines(const char *l1, const char *l2) {
  lcd.clear();
  lcd.setCursor(0, 0); lcd.print(l1);
  lcd.setCursor(0, 1); lcd.print(l2);
}

// keep reading presence while a message is on screen so H stays current
void delayMessage(unsigned long ms) {
  unsigned long start = millis();
  while (millis() - start < ms) {
    readPresence();
  }
}
