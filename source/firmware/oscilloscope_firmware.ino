#define bytesPerPackage 32
#define switch1 4
#define switch2 3

uint8_t bytesRead;
byte inputBuffer[bytesPerPackage];
byte outputBuffer[bytesPerPackage];
boolean sw1, sw2;

void setup() {
  pinMode(switch1, INPUT);
  digitalWrite(switch1, HIGH);
  pinMode(switch2, INPUT);
  digitalWrite(switch2, HIGH);
  ADMUX =  B01000000; //Внешний источник напряжения
  ADCSRA = B10101101; //Настройка АЦП
  ADCSRB = B00000000;
  sei();		          //Разрешение прерываний
  ADCSRA |=B01000000; //Включение АЦП
  Serial.begin(115200);
}

void loop() {
  sw1 = digitalRead(switch1); //Считывание данных от делителей
  sw2 = digitalRead(switch2);
  if (bytesRead >= bytesPerPackage) { //Если буфер полон
    cli();
    bytesRead = 0;
    for (uint8_t i = 0; i < bytesPerPackage; i += 2) {
      byte adch = inputBuffer[i];
      if (!sw1) adch |= B00001000; //Если работают делители
      if (!sw2) adch |= B00000100;
      outputBuffer[i] = adch;
      outputBuffer[i+1] = inputBuffer[i+1];
    }
    sei();
    Serial.write(outputBuffer, bytesPerPackage); //Буфер на отправку
  }
  
  if (Serial.available()) { //Если пришли настройки
    byte inByte = (byte)Serial.read();
    cli();
    ADCSRA= B10101000|(inByte&B00000111); //Замена байтов на новые
    sei();
    ADCSRA |=B01000000; //Запуск АЦП с новыми настройками
  }
}

ISR(ADC_vect) { //Если преобразование завершено
  if(bytesRead<bytesPerPackage-1){
    inputBuffer[bytesRead+1] = ADCL;
    inputBuffer[bytesRead] = ADCH;
    bytesRead+=2;
  }
}
