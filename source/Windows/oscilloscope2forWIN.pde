import processing.serial.*;
//import io.inventit.processing.android.serial.*;
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
boolean connected = false;
boolean devicefound = false;
String[] list;
String serialPort;
void settings() {
  size(1366, 758);
}

void setup() {
  background(0);
  //surface.setResizable(true);
  frameRate(50);
}

void draw() {
  windowWidth = width-100;
  windowHeight = height-100;
  String[] list = Serial.list();
  if (!connected && list.length > 0) {
    devicefound = true;
    background(0, 0, 0);
    text("ARDUINO OSCILLOSCOPE\n\nPress any key", 25, 25);//text("ARDUINO OSCILLOSCOPE\n\nSelect serial port:", 25, 25);
    //for (int i = 0; i < Serial.list().length; i++)
    //  text("F"+(i+1)+" - "+Serial.list()[i], 25, 80+i*20);
  } else if (connected){ //list.length > 0
    background(240, 240, 240);
    fill(0,0,0);
    // Обновление частоты каждую секунду
    loopCounter++;
    if (loopCounter > frameRate) {  
      loopCounter = 0;
      float elapsedSeconds = (millis()-timer)/1000;
      timer = millis();
      sps = (writeIndex-prevWriteIndex)/elapsedSeconds;  // sample rate
      if (sps < 0) sps += bufferSize;
      prevWriteIndex = writeIndex;
      frequency = trigCounter/elapsedSeconds;            // signal frequency
      trigCounter = 0;
      lineTime = samplesPerLine/sps*(float)width*100;
    }



    // Вывод значений напряжения
    for (int n = 0; n <= 10; n++)                                                                           
      text(nf(voltageRange/10*n, 2, 2)+"V", windowX+windowWidth+5, windowY+windowHeight-(n*windowHeight/10));
    
    
    // Вывод интерфейса и статистики
    text("[F1-F2] МАСШ | [F3] СИНХР: "+sync+" | [F4] СТОП: "+hold+" | [F5-F6] ФИЛЬТР | [F7-F8] ЧАСТОТА: "+nf((pow(2, prescaler)), 1, 0)+" | [<--->] СДВИГ", 25, 25);
    text("Частота сигнала: "+nf(frequency, 5, 2)+"Гц"
      +" | Среднее напряжение: "+nf(trigLevel/1024*voltageRange, 2, 2)+"V"
      +" | Частота выборки: "+nf(sps, 5, 2)+"Гц"
      +" | Масштаб: "+samplesPerLine+" семплов на деление"
      +" | Длина деления: "+lineTime+"мс", 25, height-10);
      
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


    // ------------------------------
    // ОТРИСОВКА РАЗВЕРТКИ
    // ------------------------------
    stroke(0, 120, 0);
    float prevSampleValue = 0;
    if (sync) readIndex = trigIndex;                               // Синхронизация вкл: чтение с последней точки уровня запуска
    if (!sync) readIndex = writeIndex;                             // Синхронизация выкл: чтение с последнего полученного семпла
    readIndex += offset;
    float lineIncr = (float)1/samplesPerLine;
    if (lineIncr < 1) lineIncr = 1;
    for (float line = 0; line < windowWidth; line+=lineIncr) {                                          // Проход по линиям на экране
      float sampleValue=(float)getValueFromBuffer((int)((float)readIndex-line*samplesPerLine));     // Считаем количество на одну линию
      sampleValue*=(float)windowHeight/1024;                                                        // Скалируем относительно размера окна
      if (line > 0)
        line(windowX+windowWidth-line, 
          windowY+windowHeight-prevSampleValue, 
          windowX+windowWidth-line-lineIncr, 
          windowY+windowHeight-sampleValue);
      prevSampleValue=sampleValue;
    }

    // ------------------------------
    // ХРАНЕНИЕ ВХОДЯЩИХ БАЙТОВ И ВЫЧИСЛЕНИЕ УРОВНЯ ЗАПУСКА
    // ------------------------------
    if (hold) {
      serial.clear();                                                                                      // "Стоп": Прекращаем получение информации, очищаем буфер
    } else {
      while (serial.available ()>0) { //serial.available ()>0                                                                     // "Дальше": работа в обычном режиме
        writeIndex++;  
        if (writeIndex >= bufferSize) writeIndex = 0;                                                      // Если переполнение, начинаем сначала
        buffer[writeIndex+writeIndex]=(byte)serial.read();                                                 // Добавляем в буфер один семпл - два байта 
        buffer[writeIndex+writeIndex+1]=(byte)serial.read();
        trigLevel=trigLevel*(1-trigLevelLPF)+(float)getValueFromBuffer(writeIndex)*trigLevelLPF;
        if (getValueFromBuffer(writeIndex) >= trigLevel && getValueFromBuffer(writeIndex-1) < trigLevel) {
          trigIndex = writeIndex;
          trigCounter++;
        }
      }
    }
  } else {
    devicefound = false;
    background(0, 0, 0);
    text("ARDUINO OSCILLOSCOPE\n\nNo devices detected!", 25, 25);
  }
}

// Читаем из буфера байты и преобразуем их в переменную
int getValueFromBuffer(int index) {                                                                      
  while (index < 0) index += bufferSize;
  return((buffer[index*2]&3)<<8 | buffer[index*2+1]&0xff);                                                 // конвертирование байтов в int
}

// Управление
void keyPressed() {  
    if (connected) {
      if (keyCode == KeyEvent.VK_F1) {
        samplesPerLine *= 1.1;
        if (samplesPerLine*windowWidth > bufferSize) samplesPerLine = bufferSize/windowWidth;
      }
      if (keyCode == KeyEvent.VK_F2) {
        samplesPerLine /= 1.1;
        if (samplesPerLine < 1/(float)windowWidth) samplesPerLine = 1/(float)windowWidth;
      }
      if (keyCode == KeyEvent.VK_F3) {
        sync = !sync;
      }
      if (keyCode == KeyEvent.VK_F4) {
        hold = !hold;
      }
      if (keyCode == KeyEvent.VK_F5) {
        if (trigLevelLPF < .01) trigLevelLPF *= 10;
      }
      if (keyCode == KeyEvent.VK_F6) {
        if (trigLevelLPF > .000001) trigLevelLPF /= 10;
      }
      if (keyCode == KeyEvent.VK_F7) {
        if (prescaler > 0) prescaler--;
        serial.write((byte)prescaler);
      }
      if (keyCode == KeyEvent.VK_F8) {
        if (prescaler < 7) prescaler++;
        serial.write((byte)prescaler);
      }
      if (keyCode == LEFT) {
        offset -= samplesPerLine*20;
        if (offset<-bufferSize) offset = -bufferSize;
      }
      if (keyCode == RIGHT) {
        offset += samplesPerLine*20;
        if (offset > 0) offset = 0;
      }
    } else if (devicefound) {
      serial = new Serial(this, Serial.list()[0], serialBaudRate);
      serial.write((byte)prescaler);
      connected=true;
    }
}
