package processing.test.oscilloscope2;

import processing.core.*; 
import processing.data.*; 
import processing.event.*; 
import processing.opengl.*; 

import io.inventit.processing.android.serial.*; 

import java.util.HashMap; 
import java.util.ArrayList; 
import java.io.File; 
import java.io.BufferedReader; 
import java.io.PrintWriter; 
import java.io.InputStream; 
import java.io.OutputStream; 
import java.io.IOException; 

public class oscilloscope2 extends PApplet {

//import processing.serial.*;

//import java.awt.event.KeyEvent;

// Settings --------------------------------------------------------------------------
int bufferSize = 10000000;      // Количество семплов всего 
float samplesPerLine = 1;       // Количество семплов на 1 деление при отображении
boolean sync = false;            // Включение синхронизации
float trigLevelLPF = .0001f;     // Для фильтра нижних частот
boolean hold = false;           // Включение паузы
int prescaler = 5;              // Предделители АЦП: 0:2 | 1:2 | 2:4 | !3:8 | 4:16 | 5:32 | 6:64 | 7:128
float voltageRange = 5;
// -----------------------------------------------------------------------------------
int testOfBuffer = 0;
int testOfAvailable = 0;
Serial port;

int[] buffer = new int[bufferSize*2]; //byte
int writeIndex, prevWriteIndex, readIndex, trigIndex, trigCounter, loopCounter, windowWidth, windowHeight, offset;
float sps, frequency, trigLevel, timer;
int windowX = 30;
int windowY = 50;

public void settings() {
  size(displayWidth, displayHeight);
}

public void setup() {
  background(0);
  frameRate(50);
  port = new Serial(this, Serial.list(this)[0], 115200); //port = new Serial(this, Serial.list()[0], serialBaudRate);
  //port.setDTR(true);
}

public void draw() {
  testOfAvailable = port.available();
  windowWidth = width-200; //-100
  windowHeight = height-200; //-100
    background(0, 0, 0);
    
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
    }

    text("Available "+testOfAvailable, 500, 500);
    text("List "+Serial.list(this)[0], 400, 400);
    
    // Вывод сетки с напряжением
    for (int n = 0; n <= 10; n++)                                                                           
      text(nf(voltageRange/10*n, 2, 2)+"V", windowX+windowWidth+5, windowY+windowHeight-(n*windowHeight/10));

    // Вывод интерфейса и статистики
    text("[F1-F2] ZOOM | [F3] SYNC: "+sync+" | [F4] HOLD: "+hold+" | [F5-F6] TRIG LPF | [F7-F8] PRESCALER: "+nf((pow(2, prescaler)), 1, 0)+" | [<--->] OFFSET", 25, 25);
    text("frequency: "+nf(frequency, 5, 2)+"Hz"
      +" | average DCV: "+nf(trigLevel/1024*voltageRange, 2, 2)+"V"
      +" | samplerate: "+nf(sps, 5, 2)+"Hz"
      +" | samples per line: "+samplesPerLine
      +" | division: "+samplesPerLine/sps*(float)width*100+"ms", 25, height-20);


    // Вывод уровня запуска
    stroke(0, 0, 100);                                                                                   
    int trigLevelHeight = (int)(trigLevel*(float)windowHeight/1024);
    line(windowX, windowY+windowHeight-trigLevelHeight, windowX+windowWidth, windowY+windowHeight-trigLevelHeight);  

    // Вывод сетки времени
    stroke(50);                                                                                           
    for (float n = 0; n <= windowWidth; n+=(float)windowWidth/10) 
      line(n+windowX, windowY, n+windowX, windowHeight+windowY); 
    for (float n = 0; n <= windowHeight; n+=(float)windowHeight/10) 
      line(windowX, n+windowY, windowX+windowWidth, n+windowY);

    // ------------------------------
    // ОТРИСОВКА РАЗВЕРТКИ
    // ------------------------------
    stroke(255);
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
      //port.clear();                                                                                      // "Стоп": Прекращаем получение информации, очищаем буфер
    } else {
      while (port.available ()>0) { //                                                             // "Дальше": работа в обычном режиме
        writeIndex++;  
        if (writeIndex >= bufferSize) writeIndex = 0;                                                      // Если переполнение, начинаем сначала
        buffer[writeIndex+writeIndex]=port.read();                                                 // Добавляем в буфер один семпл - два байта (byte)
        buffer[writeIndex+writeIndex+1]=port.read();
        testOfBuffer = writeIndex;
        
        trigLevel=trigLevel*(1-trigLevelLPF)+(float)getValueFromBuffer(writeIndex)*trigLevelLPF;
        if (getValueFromBuffer(writeIndex) >= trigLevel && getValueFromBuffer(writeIndex-1) < trigLevel) {
          trigIndex = writeIndex;
          trigCounter++;
        }
      }
    }
}

// Читаем из буфера байты и преобразуем их в переменную
public int getValueFromBuffer(int index) {                                                                      
  while (index < 0) index += bufferSize;
  return((buffer[index*2]&3)<<8 | buffer[index*2+1]&0xff);                                                 // конвертирование байтов в int
}
}
