#define bytesPerPackage 32//32
#define switch1 4               //sw1 pin
#define switch2 3               //sw2 pin

uint8_t bytesRead;
byte inputBuffer[bytesPerPackage];
byte outputBuffer[bytesPerPackage];
boolean sw1, sw2;

void setup() {
  pinMode(switch1, INPUT);
  digitalWrite(switch1, HIGH);  // enable internal pullup
  pinMode(switch2, INPUT);
  digitalWrite(switch2, HIGH);
  ADMUX =  B01000000;           // set external aref and port
  ADCSRA = B10101101;           // ADC enable, interrupt enable, set default prescaler
  ADCSRB = B00000000;           // free running mode
  sei();		        // enable interrupts
  ADCSRA |=B01000000;           // start first conversion
  Serial.begin(115200);
}

void loop() {
  sw1 = digitalRead(switch1);
  sw2 = digitalRead(switch2);
  if (bytesRead >= bytesPerPackage) {  // Buffer full. Send the package.
    cli();
    bytesRead = 0;
    for (uint8_t i = 0; i < bytesPerPackage; i += 2) {
      byte adch = inputBuffer[i];
      if (!sw1) adch |= B00001000;      // switch position in bits 10 & 11 of each byte pair 
      if (!sw2) adch |= B00000100;
      outputBuffer[i] = adch;
      outputBuffer[i+1] = inputBuffer[i+1];
    }
    sei();
    Serial.write(outputBuffer, bytesPerPackage);
  }
  
  if (Serial.available()) {                // incoming byte -> set prescaler
    byte inByte = (byte)Serial.read();
    cli();
    ADCSRA= B10101000|(inByte&B00000111);  // last 3 bytes of ADCSRA set the prescaler
    sei();
    ADCSRA |=B01000000;                    // start first conversion
  }
}

ISR(ADC_vect) {
  if(bytesRead<bytesPerPackage-1){
    inputBuffer[bytesRead+1] = ADCL;
    inputBuffer[bytesRead] = ADCH;
    bytesRead+=2;
  }
}
