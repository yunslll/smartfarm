//# smartfarm//


#include <WiFiS3.h>     // 우노 R4 WiFi 전용 라이브러리
#include <DHT.h>
#include <PubSubClient.h>

// --- 하드웨어 핀 및 센서 셋팅 ---
const int relayPin = 5;       // 소형 릴레이 제어 핀 (D5)
const int dhtPin = 4;         // DHT22 센서 핀 (D4)
#define DHTTYPE DHT22         

DHT dht(dhtPin, DHTTYPE);

// --- 네트워크 및 서버 설정 ---
const char* ssid        = //. wifi&router Id;  //       
const char* password    = //. wifi&router Pw;  //

const char* mqtt_server =//. your Ip;  // 
const int   mqtt_port   = //. your port;  //

const char* mqtt_user   = //. your server mqtt Id;  //
const char* mqtt_pass   = //. your server mqtt Pw;  //

WiFiClient r4Client;
PubSubClient client(r4Client);

// --- 상태 관리 변수 ---
int currentTemp = 31;
int currentHumidity = 40;
bool isWatering = false;
bool isAutoMode = true;

// --- 타이머 변수 (millis 기반 비동기) ---
unsigned long wateringStartTime = 0;    
unsigned long wateringDurationMs = 0;   

unsigned long lastSensorTime = 0;
const unsigned long sensorInterval = 2000; // 2초마다 센서 읽기

unsigned long lastPublishTime = 0;
const unsigned long publishInterval = 10000; // 10초마다 구글 서버로 전송

unsigned long lastReconnectAttempt = 0; // 비동기 재연결 타이머

// --- 함수 원형 선언 ---
void sendStatusToGoogle(); //google Cloud server setting
void startWatering(int minutes);
void stopWatering(const char* reason);
void reconnectMQTT();
void callback(char* topic, byte* payload, unsigned int length);

// 1. 구글 서버로 상태 전송 (snprintf 고정 메모리 방식)
void sendStatusToGoogle() {
  char jsonBuffer[128]; // 128바이트 고정 버퍼 사용 (SRAM 파편화 방지)
  
  snprintf(jsonBuffer, sizeof(jsonBuffer),
           "{\"temp\":%d,\"humidity\":%d,\"isWatering\":%s,\"isAutoMode\":%s}",
           currentTemp, currentHumidity,
           isWatering ? "true" : "false",
           isAutoMode ? "true" : "false");
  
  client.publish("smartfarm/status", jsonBuffer);
  Serial.print("구글 서버로 상태 전송 완료: ");
  Serial.println(jsonBuffer);
}

// 2. 관수 시작 공통 함수
void startWatering(int minutes) {
  isWatering = true;
  wateringDurationMs = (unsigned long)minutes * 60 * 1000UL; 
  wateringStartTime = millis(); 
  
  digitalWrite(relayPin, LOW); // 릴레이 ON (마그네트 스위치 작동)
  
  Serial.print("관수 시작 - 설정 시간: ");
  Serial.print(minutes);
  Serial.println("분");

  sendStatusToGoogle(); // 상태 즉시 보고
}

// 3. 관수 중지 공통 함수
void stopWatering(const char* reason) {
  isWatering = false;
  wateringDurationMs = 0;
  
  digitalWrite(relayPin, HIGH); // 릴레이 OFF (마그네트 스위치 해제)
  
  Serial.println(reason);
  sendStatusToGoogle(); // 상태 즉시 보고
}

// 4. 비동기 MQTT 서버 재접속
void reconnectMQTT() {
  unsigned long now = millis();
  
  // 5초에 한 번만 재접속 시도 (아두이노 loop가 멈추지 않음)
  if (now - lastReconnectAttempt > 5000) {
    lastReconnectAttempt = now;
    Serial.print("구글 MQTT 서버 연결 시도 중...");
    
    if (client.connect("UnoR4_SmartFarm_Client", mqtt_user, mqtt_pass)) {
      Serial.println("연결 성공!");
      client.subscribe("smartfarm/command");
    } else {
      Serial.print("실패, 에러코드=");
      Serial.print(client.state());
      Serial.println(" (5초 후 자동 재시도합니다)");
    }
  }
}

// 5. 명령 수신 콜백 함수 (String 제거 및 C-String 안전 파싱)
void callback(char* topic, byte* payload, unsigned int length) {
  char message[64];
  
  // 수신된 페이로드를 고정 버퍼로 안전하게 복사
  if (length < sizeof(message)) {
    memcpy(message, payload, length);
    message[length] = '\0'; // 문자열 끝 처리
  } else {
    return; // 버퍼 초과 시 무시
  }

  Serial.print("구글 서버로부터 명령 도착 [");
  Serial.print(topic);
  Serial.print("] ");
  Serial.println(message);

  // 1) 물 주기 시작 명령 처리 ("START" 또는 "START:10")
  if (strncmp(message, "START", 5) == 0) {
    int durationMinutes = 10; // 기본 10분
    
    char* colonPos = strchr(message, ':');
    if (colonPos != NULL) {
      int parsedMin = atoi(colonPos + 1);
      if (parsedMin > 0) durationMinutes = parsedMin;
    }
    
    isAutoMode = false; // 수동 제어 시 자동모드 해제
    startWatering(durationMinutes);
  } 
  // 2) 물 주기 중지 명령 처리 ("STOP")
  else if (strcmp(message, "STOP") == 0) {
    isAutoMode = false; 
    stopWatering("스마트폰 수동 제어로 관수를 중지합니다.");
  }
  // 3) 자동 제어 모드 복귀 명령 처리 ("AUTO")
  else if (strcmp(message, "AUTO") == 0) {
    isAutoMode = true;
    Serial.println("자동 온습도 제어 모드로 복귀합니다.");
    sendStatusToGoogle();
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  pinMode(relayPin, OUTPUT);
  digitalWrite(relayPin, HIGH); // 초기 상태: 릴레이 OFF

  dht.begin();

  // WiFi 연결
  WiFi.end();
  delay(500);

  Serial.print("Connecting to WiFi: ");
  Serial.println(ssid);
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nWiFi Connected!");
  Serial.print("Uno R4 IP Address: ");
  Serial.println(WiFi.localIP());

  // MQTT 설정
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);
}

void loop() {
  // MQTT 연결 상태 유지 및 비동기 재연결
  if (!client.connected()) {
    reconnectMQTT();
  } else {
    client.loop(); // 서버 명령 감시
  }

  unsigned long currentMillis = millis();

  // --- 1. 관수 타이머 만료 자동 오프 감시 ---
  if (isWatering && (wateringDurationMs > 0)) {
    if (currentMillis - wateringStartTime >= wateringDurationMs) {
      stopWatering("설정한 관수 시간이 마감되어 자동 차단합니다.");
    }
  }

  // --- 2. 센서 읽기 및 자동 모드 제어 루프 ---
  if (currentMillis - lastSensorTime >= sensorInterval) {
    lastSensorTime = currentMillis;
    
    float h = dht.readHumidity();
    float t = dht.readTemperature();
    
    if (!isnan(h) && !isnan(t)) {
      currentHumidity = (int)h;
      currentTemp = (int)t;
      
      if (isAutoMode) {
        if (currentHumidity <= 30 && !isWatering) {
          startWatering(10); // 습도 30% 이하 시 자동 10분 관수
          Serial.println("습도가 낮아 자동 관수를 시작합니다.");
        } else if (currentHumidity >= 50 && isWatering) {
          stopWatering("습도가 충분하여 자동 관수를 중지합니다.");
        }
      }
    }
  }

  // --- 3. 구글 서버로 현재 스마트팜 상태 정기 전송 (10초 간격) ---
  if (currentMillis - lastPublishTime >= publishInterval) {
    lastPublishTime = currentMillis;
    if (client.connected()) {
      sendStatusToGoogle(); 
    }
  }
}
