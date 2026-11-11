import Foundation
import UserNotifications

class Notice {
    static let shared = Notice()
    
    // 알림 보낸 시간을 저장할 딕셔너리 (키: 알림 구분용, 값: 시간)
    private var lastAlertTime: [String: Date] = [:]
    
    // 쿨타임 설정 (60초)
    private let alertCooldown: TimeInterval = 3600
    
    private init() {}
    
    // 1. 알림 권한 요청
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("알림 권한 허용됨")
            } else if let error = error {
                print(" 알림 권한 거부됨: \(error.localizedDescription)")
            }
        }
    }
    
    // 2. 알림 띄우기 함수
    func sendTemperatureAlert(temp: Int, isHigh: Bool) {
        let alertKey = isHigh ? "HighTemp" : "LowTemp"
        let now = Date()
        
        // 마지막 알림 시간 확인 (쿨타임 검사)
        if let lastTime = lastAlertTime[alertKey], now.timeIntervalSince(lastTime) < alertCooldown {
            print(" \(alertKey) 알림 쿨타임 중입니다.")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = isHigh ? "텃밭 고온 주의" : "텃밭 저온 주의 "
        content.body = "현재 온도가 \(temp)°C입니다. 상태를 확인해주세요!"
        content.sound = .default
        
        // 즉시 발송
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                print(" 알림 발송 실패: \(error.localizedDescription)")
            } else {
          
                DispatchQueue.main.async {
                    self?.lastAlertTime[alertKey] = now
                }
                print(" \(alertKey) 알림 발송 성공!")
            }
        }
    }
}
