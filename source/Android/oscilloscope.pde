import io.inventit.processing.android.serial.*;
import java.awt.event.KeyEvent;

// Settings --------------------------------------------------------------------------
int serialBaudRate = 115200;
int bufferSize = 10000000;      // Количество семплов всего
float samplesPerLine = 1;       // Количество семплов на 1 деление при отображении
boolean sync = true;            // Включение синхронизации
float trigLevelLPF = .0001;     // Для фильтра нижних частот
boolean hold = false;           // Включение паузы
int prescaler = 5;              // Предделители АЦП: 0:2 | 1:2 | 2:4 | !3:8 | 4:16 | 5:32 | 6:64 | 7:128
float voltageRange = 5;
// -----------------------------------------------------------------------------------

Serial serial;

byte[] buffer = new byte[bufferSize*2];
int writeIndex, prevWriteIndex, readIndex, trigIndex, trigCounter, loopCounter, windowWidth, windowHeight, offset;
float sps, frequency, trigLevel, timer, lineTime;

int windowX = 30;
int windowY = 50;

boolean connected, devicefound;

String[] list;
String serialPort;

// Кнопки для настройки
int bh = 90;
int bw = 125;
int gap = 10;

Button sizePButton = new Button("+", 10, gap, bw, bh);
Button sizeMButton = new Button("-", 10, gap*2+bh, bw, bh);
Button synchButton = new Button("SYNCH", 10, gap*3+bh*2, bw, bh);
Button stopButton = new Button("STOP", 10, gap*4+bh*3, bw, bh);
Button freqButton = new Button("FREQ", 10, gap*5+bh*4, bw, bh);
Button rightButton = new Button("->", 10, gap*6+bh*5, bw, bh);
Button leftButton = new Button("<-", 10, gap*7+bh*6, bw, bh);

class Button {
  String label;
  float x;    // X верхнего левого угла
  float y;    // Y верхнего левого угла
  float w;    // Ширина кнопки
  float h;    // Высота кнопки
  
  Button(String labelB, float xpos, float ypos, float widthB, float heightB) {
    label = labelB;
    x = xpos;
    y = ypos;
    w = widthB;
    h = heightB;
  }
  
  void drawButton() {
    fill(218);
    stroke(141);
    rect(x, y, w, h, 10);
    //textSize(32);
    textAlign(CENTER, CENTER);
    fill(0);
    text(label, x + (w / 2), y + (h / 2));
  }
  
  boolean mouseIsOver() {
    if (mouseX > x && mouseX < (x + w) && mouseY > y && mouseY < (y + h)) {
      return true;
    }
    return false;
  }
}

void settings() {
  size(1366, 768);
}

void setup() {
  background(0);
  frameRate(50);
}

void draw() {
  windowWidth = width-100;
  windowHeight = height-100;
  String[] list = Serial.list(this);

  if (!connected && list.length > 0) { //Устройство найдено
    devicefound = true;
    background(0, 0, 0);
    text("ARDUINO OSCILLOSCOPE", 25, 25);
    serial = new Serial(this, Serial.list(this)[0], serialBaudRate);
    serial.write((byte)prescaler);
    connected=true;
  }
  else if (connected){ //Устройство подключено
    background(240, 240, 240);
    fill(0,0,0);

    drawInterfaceParts();
    drawSignal();
    thread("dataManaging");
    
    sizePButton.drawButton();
    sizeMButton.drawButton();
    synchButton.drawButton();
    stopButton.drawButton();
    freqButton.drawButton();
    rightButton.drawButton();
    leftButton.drawButton();
  }
  else { //Устройство не найдено
    devicefound = false;
    background(0, 0, 0);
    text("ARDUINO OSCILLOSCOPE\n\nНет устройств!", 25, 25);
  }
}

int getValueFromBuffer(int index) { //Преобразование байтов из буфера в integer                                                                      
  while (index < 0) index += bufferSize;
  return((buffer[index*2]&3)<<8 | buffer[index*2+1]&0xff);
}

void drawInterfaceParts(){ //Отображение сетки и данных
  // Вывод значений напряжения
  for (int n = 0; n <= 10; n++)                                                                           
    text(nf(voltageRange/10*n, 2, 2)+"V", windowX+windowWidth+5, windowY+windowHeight-(n*windowHeight/10));

  // Вывод интерфейса и статистики
  text("СИНХР: "+sync+" | СТОП: "+hold+" | ЧАСТОТА: "+nf((pow(2, prescaler)), 1, 0), 500, 25);
  text("Частота сигнала: "+nf(frequency, 5, 2)+"Гц"
   +" | Среднее напряжение: "+nf(trigLevel/1024*voltageRange, 2, 2)+"V"
   +" | Частота выборки: "+nf(sps, 5, 2)+"Гц"
   +" | Масштаб: "+samplesPerLine+" семплов на деление"
   +" | Длина деления: "+lineTime+"мс", 500, height-10);

  // Вывод значений времени
  int lineNumber = 0;
  for (float n = 0; n <= 0.9*windowWidth; n+=(float)windowWidth/10) {
    text((lineTime*lineNumber)+" мс", n+windowX, windowHeight+windowY+15);
    lineNumber +=1;
  }

  // Вывод уровня запуска
  stroke(0, 0, 100);                                                                                   
  int trigLevelHeight = (int)(trigLevel*(float)windowHeight/1024);
  line(windowX, windowY+windowHeight-trigLevelHeight, windowX+windowWidth, windowY+windowHeight-trigLevelHeight);  

  // Вывод сетки
  stroke(50);
  for (float n = 0; n <= windowWidth; n+=(float)windowWidth/10)
    line(n+windowX, windowY, n+windowX, windowHeight+windowY);
  for (float n = 0; n <= windowHeight; n+=(float)windowHeight/10) 
    line(windowX, n+windowY, windowX+windowWidth, n+windowY);
}

void drawSignal(){ //Отображение сигнала
  stroke(0, 120, 0);
  float prevSampleValue = 0;

  if (sync) readIndex = trigIndex;   // Синхронизация вкл: чтение с последней точки уровня запуска
  if (!sync) readIndex = writeIndex; // Синхронизация выкл: чтение с последнего полученного семпла
  readIndex += offset;

  //Кол-во точек на деление
  float lineIncr = (float)1/samplesPerLine;
  if (lineIncr < 1) lineIncr = 1;

  //Отрисовка
  for (float line = 0; line < windowWidth; line+=lineIncr) {
    float sampleValue=(float)getValueFromBuffer((int)((float)readIndex-line*samplesPerLine)); // Считаем количество на одну линию
    sampleValue*=(float)windowHeight/1024;                                                    // Скалируем относительно размера окна
    if (line > 0)
      line(windowX+windowWidth-line, 
           windowY+windowHeight-prevSampleValue, 
           windowX+windowWidth-line-lineIncr, 
           windowY+windowHeight-sampleValue);
      prevSampleValue=sampleValue;
  }
}

void dataManaging(){ //Работа с входящими данными
  if (hold) {
    serial.clear();                 // "Стоп": Прекращаем получение информации, очищаем буфер
  } else {
    while (serial.available ()>0) { // "Дальше": работа в обычном режиме
      writeIndex++;
      if (writeIndex >= bufferSize) writeIndex = 0;      // Если переполнение, начинаем сначала

      // Добавление в буфер 1 семпла из 2 байтов
      buffer[writeIndex+writeIndex]=(byte)serial.read();
      buffer[writeIndex+writeIndex+1]=(byte)serial.read();

      //Вычисление уровня запуска
      trigLevel=trigLevel*(1-trigLevelLPF)+(float)getValueFromBuffer(writeIndex)*trigLevelLPF;
      if (getValueFromBuffer(writeIndex) >= trigLevel && getValueFromBuffer(writeIndex-1) < trigLevel) {
        trigIndex = writeIndex; //Точка уровня для отрисовки
        trigCounter++;
      }
    }
  }

  // Вычисление частоты и масштаба
  loopCounter++;
  if (loopCounter > frameRate) {  
    loopCounter = 0;
    float elapsedSeconds = (millis()-timer)/1000;
    timer = millis();
    sps = (writeIndex-prevWriteIndex)/elapsedSeconds; // масштаб
    if (sps < 0) sps += bufferSize;
    prevWriteIndex = writeIndex;
    frequency = trigCounter/elapsedSeconds;           // частота сигнала
    trigCounter = 0;
    lineTime = samplesPerLine/sps*(float)width*100;
  }
}

// Управление
void mousePressed() {  
    if (connected) {
      if (sizePButton.mouseIsOver()) {
        samplesPerLine *= 1.1;
        if (samplesPerLine*windowWidth > bufferSize) samplesPerLine = bufferSize/windowWidth;
      }
      if (sizeMButton.mouseIsOver()) {
        samplesPerLine /= 1.1;
        if (samplesPerLine < 1/(float)windowWidth) samplesPerLine = 1/(float)windowWidth;
      }
      if (synchButton.mouseIsOver()) {
        sync = !sync;
      }
      if (stopButton.mouseIsOver()) {
        hold = !hold;
      }
      if (freqButton.mouseIsOver()) {
        if (prescaler > 2) prescaler--;
        else prescaler = 7;
        serial.write((byte)prescaler);
      }
      if (leftButton.mouseIsOver()) {
        offset -= samplesPerLine*20;
        if (offset<-bufferSize) offset = -bufferSize;
      }
      if (rightButton.mouseIsOver()) {
        offset += samplesPerLine*20;
        if (offset > 0) offset = 0;
      }
    } else if (devicefound) {
      serial = new Serial(this, Serial.list(this)[0], serialBaudRate);
      serial.write((byte)prescaler);
      connected=true;
    }
}
