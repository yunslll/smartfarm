import SwiftUI
import Combine
import CocoaMQTT

// ==========================================
// 1. 구글 서버 통신 전담 매니저 클래스
// ==========================================
class SmartFarmManager: NSObject, ObservableObject, CocoaMQTTDelegate {
    
    @Published var isConnected: Bool = false
    
    var mqtt: CocoaMQTT?
    
    // UI 화면에 반영될 실시간 변수들
    @Published var currentTemp: Int = 31
    @Published var currentHumidity: Int = 40
    @Published var isWatering: Bool = false
    @Published var isAutoMode: Bool = true
    
    // 수동 관수 작동 시간 선택 변수 (기본값 10분)
    @Published var selectedWateringMinutes: Int = 10
    
    @Published var highTempThreshold: Int = 30
    @Published var lowTempThreshold: Int = -10
    
    override init() {
        super.init()
        
#if DEBUG
        // Xcode 프리뷰 캔버스 크래시 방지용 안전장치
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
#endif
        
        setupMQTT()
        setupAppLifecycleObservers()
    }
    
    private func setupMQTT() {
        let clientID = "iPhone_SmartFarm_App_" + String(Int.random(in: 1000...9999))
        mqtt = CocoaMQTT(clientID: clientID, host: //"   "//, port: //  //)
        mqtt?.username = //"  "//
        mqtt?.password = //"  "//
        mqtt?.keepAlive = 60
        
        // 자동 재연결 및 소켓 설정
        mqtt?.autoReconnect = true
        mqtt?.autoReconnectTimeInterval = 5 // 끊어졌을 때 5초 간격으로 재연결 시도
        mqtt?.allowUntrustCACertificate = true
        
        mqtt?.delegate = self
        
        // 구글 서버 연결 시작
        connectMQTT()
    }
    
    func connectMQTT() {
        guard let mqtt = mqtt else { return }
        
        // 연결 성공 상태가 아닐 때(초기/끊김/재연결 등) 모두 처리
        if mqtt.connState != CocoaMQTTConnState.connected {
            _ = mqtt.connect()
        }
    }
    
    // 앱이 다시 활성화(포그라운드)될 때 자동 재연결 감지
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appWillEnterForeground() {
        print("앱이 포그라운드로 복귀함: MQTT 연결 상태 확인 중...")
        if mqtt?.connState != .connected {
            connectMQTT()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // 아두이노로 명령을 쏘는 함수 (Publish)
    func sendCommand(_ command: String) {
        if mqtt?.connState != .connected {
            print("서버와 연결되어 있지 않아 연결 재시도 중...")
            connectMQTT()
        }
        
        // 🛠️ [디버깅 3] 명령 전송 작업을 비동기로 처리하여 버튼 렉 해제
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.mqtt?.publish("smartfarm/command", withString: command)
            print("구글 서버로 명령 전송: \(command)")
        }
    }
    
    // JSON 데이터 파싱 내부 함수
    func parseArduinoJSON(data: Data) {
        struct ArduinoData: Codable {
            let temp: Int?
            let humidity: Int?
            let isWatering: Bool
            let isAutoMode: Bool
        }
        
        do {
            let decodedData = try JSONDecoder().decode(ArduinoData.self, from: data)
            
            // UI 업데이트는 반드시 메인 스레드에서 안전하게 실행
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                if let temp = decodedData.temp { self.currentTemp = temp }
                if let humidity = decodedData.humidity { self.currentHumidity = humidity }
                self.isWatering = decodedData.isWatering
                self.isAutoMode = decodedData.isAutoMode
     
                let tempValue = decodedData.temp ?? self.currentTemp
                if tempValue >= self.highTempThreshold {
                    Notice.shared.sendTemperatureAlert(temp: tempValue, isHigh: true)
                } else if tempValue <= self.lowTempThreshold {
                    Notice.shared.sendTemperatureAlert(temp: tempValue, isHigh: false)
        }
    }
            
        } catch {
            print("JSON 파싱 에러: \(error)")
        }
    }
        
    // MARK: - CocoaMQTTDelegate (백그라운드 큐에서 실행됨)
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck status: CocoaMQTTConnAck) {
        if status == .accept {
            print("구글 클라우드 MQTT 서버 연결 성공!")
            mqtt.subscribe("smartfarm/status") // 아두이노 센서값 구독
            
            DispatchQueue.main.async {
                self.isConnected = true
            }
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        if message.topic == "smartfarm/status" {
            if let string = message.string,
               let data = string.data(using: .utf8) {
                self.parseArduinoJSON(data: data)
            }
        }
    }
    
    // 필수 델리게이트 스텁
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeAck id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeAck id: UInt16) {}
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        print("MQTT 연결 해제됨: \(err?.localizedDescription ?? "알 수 없는 오류")")
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}

// ==========================================
// 2. 스마트폰 화면 UI 영역
// ==========================================


struct ConnectionStatusView: View {
    let isConnected: Bool
    let onReconnect: () -> Void
    
    var body: some View {
 
        Button(action: {
            if !isConnected {
                onReconnect()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isConnected ? "wifi" : "wifi.slash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isConnected ? .green : .red)
                
                Text(isConnected ? "서버 연결됨" : "서버 연결 끊김 (터치 시 재연결)")
                    .font(.caption)
                    .bold()
                    .foregroundColor(isConnected ? .green : .red)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isConnected ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
            )
        }
        .disabled(isConnected)
    }
}

struct ContentView: View {
    @StateObject private var farm = SmartFarmManager()
    
    var body: some View {
        ZStack {
        Color(red: 0.9, green: 1.0, blue: 0.9)
            .ignoresSafeArea()
            
        VStack(spacing: 30) {
        VStack(spacing: 10) {       // 상단 타이틀
                Text("Hyejin&Junseo Garden")
                    .font(.title)
                    .bold()
                    .foregroundStyle(.green)
                    .brightness(-0.3)
                    
                Text("Smart setting")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .brightness(-0.5)
                    
        ConnectionStatusView(isConnected: farm.isConnected) {
            farm.connectMQTT()
    }
                .padding(.top, 4)
}
                .padding(.top, 15)
                
            VStack(spacing: 20) {   // 온도 정보 상자
                HStack {
                Image(systemName: "thermometer.sun")
                    .foregroundStyle(.orange)
                    .imageScale(.large)
                        
                Text("현재 밭 온도 : \(farm.currentTemp)°C")
                    .font(.title2)
                    .bold()
            }
                    .padding()
                    .background(Color.yellow.opacity(1.0))
                    .cornerRadius(15)
                    
                   
                    HStack {         // 습도 정보 상자
                        Image(systemName: "humidity")
                            .foregroundStyle(.blue)
                            .imageScale(.large)
                        
                        Text("현재 밭 습도 : \(farm.currentHumidity)%")
                            .font(.title2)
                            .bold()
                    }
                    .padding()
                    .background(Color.blue.opacity(0.4))
                    .cornerRadius(15)
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 20)
                
                // 자동 모드 활성화 상태를 시각적으로 보여주는 상자
                HStack {
                    Image(systemName: farm.isAutoMode ? "cpu.fill" : "hand.raised.fill")
                        .foregroundStyle(farm.isAutoMode ? .purple : .gray)
                    Text(farm.isAutoMode ? "자동 관수 제어 활성화" : "수동 제어 모드 (자동 꺼짐)")
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(farm.isAutoMode ? .purple : .gray)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(farm.isAutoMode ? Color.purple.opacity(0.1) : Color.gray.opacity(0.1))
                .cornerRadius(20)
                
                // 수동 모드일 때 자동 복귀용 버튼
                if !farm.isAutoMode {
                    Button(action: {
                        farm.sendCommand("AUTO")
                    }) {
                        Text("자동 제어 모드로 복귀하기")
                            .font(.caption)
                            .foregroundColor(.purple)
                            .underline()
                    }
                }
                
                Spacer()
                
                // 관수시스템 제어 영역
                VStack(spacing: 15) {
                    Image(systemName: farm.isWatering ? "sprinkler.and.droplets.fill" : "leaf.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(farm.isWatering ? .blue : .green)
                    
                    if farm.isWatering {
                        if farm.isAutoMode {
                            Text("자동 관수 작동 중")
                                .font(.title3)
                                .bold()
                                .foregroundStyle(.blue)
                        } else {
                            Text("수동 관수 작동 중")
                                .font(.title3)
                                .bold()
                                .foregroundStyle(.cyan)
                        }
                    } else {
                        Text(farm.isAutoMode ? "자동 모드 대기 중" : "대기 중")
                            .font(.headline)
                            .foregroundStyle(.gray)
                    }
                    
                    // 제어 버튼
                    HStack {
                        Text("관수 시간 선택:")
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.secondary)
                        
                        Picker("관수 시간", selection: $farm.selectedWateringMinutes) {
                            ForEach(1...60, id: \.self) { minute in
                                Text("\(minute)분").tag(minute)
                            }
                        }
                        .pickerStyle(.menu)
                        .accentColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.05), radius: 2)
                    }
                    
                    Button(action: {
                        if farm.isWatering {
                            farm.sendCommand("STOP")
                        } else {
                            farm.sendCommand("START:\(farm.selectedWateringMinutes)")
                        }
                    }) {
                        Text(farm.isWatering ? "물 주기 정지" : "\(farm.selectedWateringMinutes)분간 물 주기 시작")
                            .font(.title3)
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundStyle(.white)
                            .background(farm.isWatering ? Color.red : Color.blue)
                            .cornerRadius(15)
                    }
                    .padding(.horizontal, 30)
                }
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    ContentView()
}
