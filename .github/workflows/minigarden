import SwiftUI
import Combine
import CocoaMQTT

// ==========================================
// 1. 구글 서버 통신 전담 매니저 클래스
// ==========================================
class SmartFarmManager: NSObject, ObservableObject {
    
    @Published var isConnected: Bool = false
    
    var mqtt: CocoaMQTT?
    
    // UI 화면에 반영될 실시간 변수들
    @Published var currentTemp: Double = 31.0
    @Published var currentHumidity: Double = 40.0
    @Published var isWatering: Bool = false
    @Published var isAutoMode: Bool = true
    @Published var selectedWateringMinutes: Int = 10
    
    @Published var highTempThreshold: Int = 30
    @Published var lowTempThreshold: Int = -10
    
    // 5초 간격 주기적 데이터 요청용 타이머
    private var statusTimer: Timer?
    
    override init() {
        super.init()
        
#if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
#endif
        setupMQTT()
        setupAppLifecycleObservers()
    }
    
    private func setupMQTT() {
        let clientID = "iPhone_SmartFarm_App_" + String(Int.random(in: 1000...9999))
        mqtt = CocoaMQTT(clientID: clientID, host: "127.0.0.1", port: 1880)
        mqtt?.username = "Admin"
        mqtt?.password = "1111"
        mqtt?.keepAlive = 60
        mqtt?.autoReconnect = true
        mqtt?.autoReconnectTimeInterval = 5
        mqtt?.allowUntrustCACertificate = true
        mqtt?.delegate = self
        
        connectMQTT()
    }
    
    func connectMQTT() {
        guard let mqtt = mqtt else { return }
        if mqtt.connState != .connected {
            _ = mqtt.connect()
        }
    }
    
    // MARK: - 앱 라이프사이클 감지 (백그라운드 / 포그라운드 전환)
    private func setupAppLifecycleObservers() {
        // 앱이 화면에 다시 나타날 때
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        // 앱이 다른 앱으로 전환되거나 백그라운드로 내려갈 때
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        print(" 앱이 백그라운드로 전환됨: 타이머 정지")
        stopStatusPolling()
    }
    
    @objc private func appWillEnterForeground() {
        print("앱이 포그라운드로 복귀함: 연결 확인 및 최신 상태 즉시 요청")
        if mqtt?.connState == .connected {
            // 소켓이 유지되어 있다면 바로 최신 상태 요청 및 타이머 재개
            sendCommand("STATUS_REQ")
            startStatusPolling()
        } else {
            // 끊어졌다면 재연결 시도 (연결 완료 후 didConnectAck에서 STATUS_REQ 실행됨)
            connectMQTT()
        }
    }
    
    deinit {
        stopStatusPolling()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 주기적 실시간 상태 요청 타이머
    func startStatusPolling() {
        stopStatusPolling() // 기존 타이머 중복 실행 방지
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            self.sendCommand("STATUS_REQ")
        }
    }

    func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }
    
    func sendCommand(_ command: String) {
        if mqtt?.connState != .connected {
            connectMQTT()
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.mqtt?.publish("smartfarm/command", withString: command)
            print("구글 서버로 명령 전송: \(command)")
        }
    }
    
    func parseArduinoJSON(data: Data) {
        struct ArduinoData: Codable {
            let temp: Double?
            let humidity: Double?
            let isWatering: Bool?
            let isAutoMode: Bool?
        }
        
        do {
            let decodedData = try JSONDecoder().decode(ArduinoData.self, from: data)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                if let temp = decodedData.temp { self.currentTemp = Double(temp) }
                if let humidity = decodedData.humidity { self.currentHumidity = Double(humidity) }
                if let isWatering = decodedData.isWatering { self.isWatering = isWatering }
                if let isAutoMode = decodedData.isAutoMode { self.isAutoMode = isAutoMode }
     
                let tempValue = Int(self.currentTemp)
                if tempValue >= self.highTempThreshold {
                    Notice.shared.sendTemperatureAlert(temp: tempValue, isHigh: true)
                } else if tempValue <= self.lowTempThreshold {
                    Notice.shared.sendTemperatureAlert(temp: tempValue, isHigh: false)
                }
            }
        } catch {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("JSON 파싱 실패 -> 수신 원본: \(jsonString)")
            }
            print("파싱 상세 에러: \(error)")
        }
    }
        }
    
extension SmartFarmManager: CocoaMQTTDelegate {
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck status: CocoaMQTTConnAck) {
        if status == .accept {
            print("구글 클라우드 MQTT 서버 연결 성공!")
            mqtt.subscribe("smartfarm/status")
            
            DispatchQueue.main.async {
                self.isConnected = true
                self.sendCommand("STATUS_REQ") // 연결 즉시 상태 요청
                self.startStatusPolling()      // 타이머 시작
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
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        print("MQTT 연결 해제됨: \(err?.localizedDescription ?? "알 수 없는 오류")")
        DispatchQueue.main.async {
            self.isConnected = false
            self.stopStatusPolling() // 연결 해제 시 타이머 정지
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeAck id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeAck id: UInt16) {}
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
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
                        
    Text(String(format: "현재 밭 온도 : %.1f°C", farm.currentTemp))
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
                        
    Text(String(format: "현재 밭 습도 : %.1f%%", farm.currentHumidity))
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
