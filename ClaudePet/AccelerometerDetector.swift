import Foundation
import IOKit
import IOKit.hid

// MARK: - 파일 스코프 @convention(c) 콜백
//
// Swift는 일반 함수를 @Sendable 로 추론해 IOKit의 @convention(c) 타입과 충돌합니다.
// IOHIDDeviceCallback / IOHIDReportCallback 타입으로 명시적으로 선언한 non-capturing
// 클로저를 사용하면 Swift가 올바르게 @convention(c) 로 브릿징합니다.

private let accelDeviceMatchedCB: IOHIDDeviceCallback = { context, _, _, device in
    guard let ctx = context else { return }
    Unmanaged<AccelerometerDetector>.fromOpaque(ctx)
        .takeUnretainedValue()
        .attachReportCallback(to: device)
}

private let accelReportCB: IOHIDReportCallback = { context, _, _, _, _, report, reportLength in
    guard let ctx = context, reportLength >= 18 else { return }
    Unmanaged<AccelerometerDetector>.fromOpaque(ctx)
        .takeUnretainedValue()
        .processReport(UnsafePointer(report), length: reportLength)
}

// MARK: - AccelerometerDetector

/// Apple Silicon 내장 Bosch BMI286 가속도계를 IOKit HID 로 직접 읽어
/// 충격 이벤트를 감지합니다.
///
/// ### taigrr/spank 동일 프로토콜
/// - Usage Page 0x0020 (HID Sensor), Usage 0x0073 (3D Accelerometer)
/// - 22-byte HID 리포트: X/Y/Z 는 Int32 little-endian, 각 오프셋 6·10·14
/// - 65536 으로 나누면 g 단위
///
/// ### 동작 방식
/// start() 는 IOHIDManager 를 설정하고 런루프에 등록합니다.
/// 디바이스 매칭은 비동기로 일어나므로 start() 에서 성공 여부를 확인하지 않습니다.
/// onImpact 콜백은 실제 충격이 감지됐을 때만 호출됩니다.
final class AccelerometerDetector {

    // MARK: - 설정
    var impactThreshold: Double = 2.0   // g 단위 — 낮출수록 가벼운 충격도 감지
    var cooldownSec:     Double = 0.8   // 연속 트리거 방지 쿨다운 (초)
    var onImpact: (() -> Void)?

    // MARK: - Private
    private var manager:     IOHIDManager?
    private var lastHitDate: Date = .distantPast

    // C 콜백에 넘길 고정 리포트 버퍼
    private let reportBuf: UnsafeMutablePointer<UInt8> = {
        let p = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
        p.initialize(repeating: 0, count: 256)
        return p
    }()

    deinit {
        stop()
        reportBuf.deallocate()
    }

    // MARK: - Public API

    /// IOKit HID 매니저를 시작합니다.
    /// 디바이스 매칭은 런루프 기반 비동기로 동작하므로 호출 즉시 성공 여부를 반환하지 않습니다.
    /// 충격이 감지되면 onImpact 가 호출됩니다.
    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // BMI286 은 Usage Page 0x0020 (Sensor) + Usage 0x0073 (3D Accelerometer)
        // 혹은 0x0076 (Gyroscope) 으로 식별됩니다.
        // IOHIDManagerSetDeviceMatchingMultiple 로 두 Usage 모두 감지합니다.
        let criteria: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: 0x0020, kIOHIDDeviceUsageKey: 0x0073],
            [kIOHIDDeviceUsagePageKey: 0x0020, kIOHIDDeviceUsageKey: 0x0076],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, criteria as CFArray)

        // open 실패 시 조용히 종료 (미지원 기기 — onImpact 가 호출되지 않음)
        guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return
        }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, accelDeviceMatchedCB, ctx)

        // 런루프에 등록 — 이후 디바이스 매칭과 리포트 수신이 비동기로 처리됩니다
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.manager = mgr
    }

    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(
            mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
    }

    // MARK: - C 콜백 수신

    func attachReportCallback(to device: IOHIDDevice) {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device, reportBuf, 256, accelReportCB, ctx
        )
        IOHIDDeviceScheduleWithRunLoop(
            device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
        )
    }

    func processReport(_ report: UnsafePointer<UInt8>, length: CFIndex) {
        // ── BMI286 HID 리포트 레이아웃 ─────────────────────────────────
        //   offset  0– 5 : 헤더 / 센서 ID
        //   offset  6– 9 : X 축 (Int32 little-endian) ÷ 65536 → g
        //   offset 10–13 : Y 축
        //   offset 14–17 : Z 축
        //   정지 상태 벡터 크기 ≈ 1.0g (중력), 강한 충격 시 2g 이상
        // ─────────────────────────────────────────────────────────────
        let x = Double(le32(report, offset: 6))  / 65536.0
        let y = Double(le32(report, offset: 10)) / 65536.0
        let z = Double(le32(report, offset: 14)) / 65536.0
        let magnitude = (x*x + y*y + z*z).squareRoot()

        guard magnitude > impactThreshold else { return }

        let now = Date()
        guard now.timeIntervalSince(lastHitDate) > cooldownSec else { return }
        lastHitDate = now

        DispatchQueue.main.async { [weak self] in
            self?.onImpact?()
        }
    }

    // MARK: - Helpers

    private func le32(_ p: UnsafePointer<UInt8>, offset: Int) -> Int32 {
        let raw =  UInt32(p[offset])
                 | UInt32(p[offset + 1]) << 8
                 | UInt32(p[offset + 2]) << 16
                 | UInt32(p[offset + 3]) << 24
        return Int32(bitPattern: raw)
    }
}
