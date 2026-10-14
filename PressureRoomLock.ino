#include <SPI.h>
#include <MFRC522.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

#define SS_PIN 10
#define RST_PIN 9
#define BUZZER_PIN 8
#define RELAY_PIN 7
#define POT_PIN A0

MFRC522 rfid(SS_PIN, RST_PIN);
LiquidCrystal_I2C lcd(0x27, 16, 2); 

byte authorizedUID[4] = {0xA3, 0x20, 0xDF, 0x24}; 
bool isUnlocked = false;

void setup() {
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, HIGH); // Relay active LOW (HIGH = locked)
  digitalWrite(BUZZER_PIN, LOW);

  SPI.begin();
  rfid.PCD_Init();
  
  lcd.init();
  lcd.backlight();
}

void loop() {
  int rawPot = analogRead(POT_PIN);
  int potPercentage = map(rawPot, 0, 1023, 0, 100);

  // Dynamic header text based on system lock state
  if (isUnlocked) {
    updateDefaultDisplay("Scan again lock ", potPercentage);
  } else {
    updateDefaultDisplay("Scan card...    ", potPercentage);
  }

  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) {
    return;
  }

  bool cardMatches = true;
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (rfid.uid.uidByte[i] != authorizedUID[i]) {
      cardMatches = false;
      break;
    }
  }

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();

  if (cardMatches) {
    if (!isUnlocked) {
      if (potPercentage == 0) {
        isUnlocked = true;
        digitalWrite(RELAY_PIN, LOW); // Unlock
        
        updateDefaultDisplay("Access Granted  ", potPercentage);
        
        digitalWrite(BUZZER_PIN, HIGH); 
        delay(1000);                    
        digitalWrite(BUZZER_PIN, LOW);  
      } else {
        updateDisplay("Access Denied", "Pressure high!");
        delay(2000);
        lcd.clear();
      }
    } else {
      isUnlocked = false;
      digitalWrite(RELAY_PIN, HIGH); // Relatch (Solenoid OFF)
      
      updateDisplay("Card Rescanned", "Lock Latched");
      
      digitalWrite(BUZZER_PIN, HIGH);   
      delay(1500);                      
      digitalWrite(BUZZER_PIN, LOW);    
      
      lcd.clear();
    }
  } else {
    updateDisplay("Invalid Card", "Access Denied");
    
    digitalWrite(BUZZER_PIN, HIGH);
    delay(150);
    digitalWrite(BUZZER_PIN, LOW);
    delay(150);
    digitalWrite(BUZZER_PIN, HIGH);
    delay(150);
    digitalWrite(BUZZER_PIN, LOW);
    
    delay(1000);
    lcd.clear();
  }

  // FORCE RE-INITIALIZE RFID MODULE TO RECOVER FROM RELAY EMI SPIKES
  rfid.PCD_Init(); 
}

void updateDefaultDisplay(String headerText, int percent) {
  lcd.setCursor(0, 0);
  lcd.print(headerText);
  
  lcd.setCursor(0, 1);
  lcd.print("Pressure: ");
  lcd.print(percent);
  lcd.print("%   ");
}

void updateDisplay(String line1, String line2) {
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print(line1);
  lcd.setCursor(0, 1);
  lcd.print(line2);
}