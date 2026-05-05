import AppKit
import Foundation
import SQLite3

private enum FontCache {
    nonisolated(unsafe) static let ringReadout = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
    nonisolated(unsafe) static let barText = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)
    nonisolated(unsafe) static let minimalBold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    nonisolated(unsafe) static let minimalSep = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
}

enum ColorScheme: String, CaseIterable {
    case warm
    case cool
    case cyberpunk
    case original
}

enum TrackingSpeed: String, CaseIterable {
    case fast
    case medium
    case smooth

    var interval: TimeInterval {
        switch self {
        case .fast: return 0.03
        case .medium: return 0.08
        case .smooth: return 0.12
        }
    }
}

enum AppLanguage: String, CaseIterable {
    case zh
    case en
}

enum DisplayMode: String, CaseIterable {
    case rings
    case bars
    case minimal
}

enum DataSource: String, CaseIterable {
    case both
    case primary
    case secondary
}

enum ReadoutMode: String, CaseIterable {
    case always
    case hover
}

struct LimitRingsSettings {
    var colorScheme: ColorScheme
    var trackingSpeed: TrackingSpeed
    var displayMode: DisplayMode
    var dataSource: DataSource
    var readoutMode: ReadoutMode
    var barOffsetX: CGFloat
    var barOffsetY: CGFloat
    var barThickness: CGFloat
    var language: AppLanguage

    private static let kColorScheme = "CodexPetLimitRings.colorScheme"
    private static let kTrackingSpeed = "CodexPetLimitRings.trackingSpeed"
    private static let kDisplayMode = "CodexPetLimitRings.displayMode"
    private static let kDataSource = "CodexPetLimitRings.dataSource"
    private static let kReadoutMode = "CodexPetLimitRings.readoutMode"
    private static let kBarOffsetX = "CodexPetLimitRings.barOffsetX"
    private static let kBarOffsetY = "CodexPetLimitRings.barOffsetY"
    private static let kBarThickness = "CodexPetLimitRings.barThickness"
    private static let kLanguage = "CodexPetLimitRings.language"

    static func load() -> LimitRingsSettings {
        let d = UserDefaults.standard
        let mode: DisplayMode
        if let saved = d.string(forKey: kDisplayMode), let parsed = DisplayMode(rawValue: saved) {
            mode = parsed
        } else if d.object(forKey: "CodexPetLimitRings.showBars") as? Bool == true {
            mode = .bars
        } else {
            mode = .rings
        }
        return LimitRingsSettings(
            colorScheme: ColorScheme(rawValue: d.string(forKey: kColorScheme) ?? "") ?? .warm,
            trackingSpeed: TrackingSpeed(rawValue: d.string(forKey: kTrackingSpeed) ?? "") ?? .fast,
            displayMode: mode,
            dataSource: DataSource(rawValue: d.string(forKey: kDataSource) ?? "") ?? .both,
            readoutMode: ReadoutMode(rawValue: d.string(forKey: kReadoutMode) ?? "") ?? .always,
            barOffsetX: d.object(forKey: kBarOffsetX) != nil ? CGFloat(d.double(forKey: kBarOffsetX)) : 0,
            barOffsetY: d.object(forKey: kBarOffsetY) != nil ? CGFloat(d.double(forKey: kBarOffsetY)) : 0,
            barThickness: d.object(forKey: kBarThickness) != nil ? CGFloat(d.double(forKey: kBarThickness)) : 4.5,
            language: AppLanguage(rawValue: d.string(forKey: kLanguage) ?? "") ?? .zh
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(colorScheme.rawValue, forKey: Self.kColorScheme)
        d.set(trackingSpeed.rawValue, forKey: Self.kTrackingSpeed)
        d.set(displayMode.rawValue, forKey: Self.kDisplayMode)
        d.set(dataSource.rawValue, forKey: Self.kDataSource)
        d.set(readoutMode.rawValue, forKey: Self.kReadoutMode)
        d.set(Double(barOffsetX), forKey: Self.kBarOffsetX)
        d.set(Double(barOffsetY), forKey: Self.kBarOffsetY)
        d.set(Double(barThickness), forKey: Self.kBarThickness)
        d.set(language.rawValue, forKey: Self.kLanguage)
    }
}

struct L10n {
    static func text(_ zh: String, _ en: String, lang: AppLanguage) -> String {
        lang == .zh ? zh : en
    }

    static func colorSchemeName(_ scheme: ColorScheme, lang: AppLanguage) -> String {
        switch scheme {
        case .warm: return lang == .zh ? "暖色调" : "Warm"
        case .cool: return lang == .zh ? "冷色调" : "Cool"
        case .cyberpunk: return lang == .zh ? "赛博朋克" : "Cyberpunk"
        case .original: return lang == .zh ? "经典" : "Original"
        }
    }

    static func speedName(_ speed: TrackingSpeed, lang: AppLanguage) -> String {
        switch speed {
        case .fast: return lang == .zh ? "快速" : "Fast"
        case .medium: return lang == .zh ? "适中" : "Medium"
        case .smooth: return lang == .zh ? "平滑" : "Smooth"
        }
    }

    static func languageName(_ language: AppLanguage, lang: AppLanguage) -> String {
        switch language {
        case .zh: return lang == .zh ? "中文" : "Chinese"
        case .en: return "English"
        }
    }

    static func displayModeName(_ mode: DisplayMode, lang: AppLanguage) -> String {
        switch mode {
        case .rings: return lang == .zh ? "圆环" : "Rings"
        case .bars: return lang == .zh ? "条状" : "Bars"
        case .minimal: return lang == .zh ? "极简" : "Minimal"
        }
    }

    static func dataSourceName(_ source: DataSource, lang: AppLanguage) -> String {
        switch source {
        case .both: return lang == .zh ? "两者" : "Both"
        case .primary: return lang == .zh ? "短窗口" : "Short"
        case .secondary: return lang == .zh ? "周限额" : "Weekly"
        }
    }

    static func readoutModeName(_ mode: ReadoutMode, lang: AppLanguage) -> String {
        switch mode {
        case .always: return lang == .zh ? "始终显示" : "Always"
        case .hover: return lang == .zh ? "悬停显示" : "Hover"
        }
    }
}

struct LimitBucket {
    var usedPercent: Double
    var windowMinutes: Double?
    var resetAt: TimeInterval?

    var remainingPercent: Double {
        min(max(100.0 - usedPercent, 0.0), 100.0)
    }
}

struct LimitState {
    var planType: String?
    var primary: LimitBucket?
    var secondary: LimitBucket?
    var additional: [(name: String, bucket: LimitBucket)]
    var observedAt: Date
    var source: String

    static let empty = LimitState(planType: nil, primary: nil, secondary: nil, additional: [], observedAt: Date(), source: "none")

    func filtered(for source: DataSource) -> LimitState {
        switch source {
        case .both: return self
        case .primary: return LimitState(planType: planType, primary: primary, secondary: nil, additional: [], observedAt: observedAt, source: self.source)
        case .secondary: return LimitState(planType: planType, primary: nil, secondary: secondary, additional: [], observedAt: observedAt, source: self.source)
        }
    }
}

private let limitStatePollInterval: TimeInterval = 20.0
private let ringsVisibleDefaultsKey = "CodexPetLimitRings.ringsVisible"
private let liveUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

private struct EventPayload: Decodable {
    var type: String
    var plan_type: String?
    var rate_limits: RatePayload?
    var additional_rate_limits: [String: RatePayload]?
}

private struct AuthPayload: Decodable {
    var tokens: AuthTokens?
}

private struct AuthTokens: Decodable {
    var access_token: String?
}

private struct UsagePayload: Decodable {
    var plan_type: String?
    var rate_limit: RatePayload?
    var additional_rate_limits: [AdditionalUsagePayload]?
}

private struct AdditionalUsagePayload: Decodable {
    var limit_name: String?
    var metered_feature: String?
    var rate_limit: RatePayload?
}

private struct RatePayload: Decodable {
    var primary: BucketPayload?
    var secondary: BucketPayload?
    var primary_window: BucketPayload?
    var secondary_window: BucketPayload?
}

private struct BucketPayload: Decodable {
    var used_percent: Double?
    var window_minutes: Double?
    var limit_window_seconds: Double?
    var reset_at: Double?

    func toBucket() -> LimitBucket? {
        guard let used = used_percent else { return nil }
        let minutes = window_minutes ?? limit_window_seconds.map { $0 / 60.0 }
        return LimitBucket(usedPercent: used, windowMinutes: minutes, resetAt: reset_at)
    }
}

struct LimitRingsConfig {
    var codexHome: URL
    var globalStatePath: URL
    var logsPath: URL
    var authPath: URL
    var previewPath: URL?
    var fallbackSize: CGFloat = 220
}

final class LimitStateReader {
    private let logsPath: URL
    private let authPath: URL

    init(logsPath: URL, authPath: URL) {
        self.logsPath = logsPath
        self.authPath = authPath
    }

    func readLatest() -> LimitState {
        if let liveState = readLiveUsage() {
            return liveState
        }
        return readLatestLog()
    }

    private func readLiveUsage() -> LimitState? {
        guard let token = readAccessToken() else {
            return nil
        }

        var request = URLRequest(url: liveUsageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 6.0
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultResponse: URLResponse?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            resultData = data
            resultResponse = response
            semaphore.signal()
        }.resume()

        guard semaphore.wait(timeout: .now() + 7.0) == .success,
              let http = resultResponse as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let data = resultData,
              let payload = try? JSONDecoder().decode(UsagePayload.self, from: data) else {
            return nil
        }

        let primary = (payload.rate_limit?.primary ?? payload.rate_limit?.primary_window)?.toBucket()
        let secondary = (payload.rate_limit?.secondary ?? payload.rate_limit?.secondary_window)?.toBucket()
        let additional = (payload.additional_rate_limits ?? [])
            .compactMap { item -> (String, LimitBucket)? in
                guard let bucket = (item.rate_limit?.primary ?? item.rate_limit?.primary_window ?? item.rate_limit?.secondary ?? item.rate_limit?.secondary_window)?.toBucket() else {
                    return nil
                }
                return (item.limit_name ?? item.metered_feature ?? "Additional", bucket)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }

        return LimitState(planType: payload.plan_type, primary: primary, secondary: secondary, additional: additional, observedAt: Date(), source: "live")
    }

    private func readAccessToken() -> String? {
        guard let data = try? Data(contentsOf: authPath),
              let payload = try? JSONDecoder().decode(AuthPayload.self, from: data),
              let token = payload.tokens?.access_token,
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private func readLatestLog() -> LimitState {
        guard FileManager.default.fileExists(atPath: logsPath.path) else {
            return .empty
        }

        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(logsPath.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard openResult == SQLITE_OK, let db else {
            return .empty
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT feedback_log_body
        FROM logs
        WHERE feedback_log_body LIKE '%"type":"codex.rate_limits"%'
        ORDER BY ts DESC, ts_nanos DESC, id DESC
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return .empty
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let cText = sqlite3_column_text(statement, 0) else {
            return .empty
        }

        let body = String(cString: cText)
        guard let json = extractRateLimitJSON(from: body),
              let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(EventPayload.self, from: data) else {
            return .empty
        }

        let primary = (payload.rate_limits?.primary ?? payload.rate_limits?.primary_window)?.toBucket()
        let secondary = (payload.rate_limits?.secondary ?? payload.rate_limits?.secondary_window)?.toBucket()
        let additional = (payload.additional_rate_limits ?? [:])
            .compactMap { name, payload -> (String, LimitBucket)? in
                guard let bucket = (payload.primary ?? payload.primary_window ?? payload.secondary ?? payload.secondary_window)?.toBucket() else {
                    return nil
                }
                return (name, bucket)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }

        return LimitState(planType: payload.plan_type, primary: primary, secondary: secondary, additional: additional, observedAt: Date(), source: "log")
    }

    private func extractRateLimitJSON(from body: String) -> String? {
        guard let start = body.range(of: "{\"type\":\"codex.rate_limits\"")?.lowerBound else {
            return nil
        }

        var depth = 0
        var inString = false
        var escaping = false
        var endIndex: String.Index?
        var index = start

        while index < body.endIndex {
            let char = body[index]
            if inString {
                if escaping {
                    escaping = false
                } else if char == "\\" {
                    escaping = true
                } else if char == "\"" {
                    inString = false
                }
            } else {
                if char == "\"" {
                    inString = true
                } else if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = body.index(after: index)
                        break
                    }
                }
            }
            index = body.index(after: index)
        }

        guard let endIndex else { return nil }
        return String(body[start..<endIndex])
    }
}

final class PetFrameReader {
    private let globalStatePath: URL

    init(globalStatePath: URL) {
        self.globalStatePath = globalStatePath
    }

    func readPetFrameTopLeft() -> CGRect? {
        guard let data = try? Data(contentsOf: globalStatePath),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              isAvatarOverlayOpen(root),
              let bounds = root["electron-avatar-overlay-bounds"] as? [String: Any],
              let x = number(bounds["x"]),
              let y = number(bounds["y"]),
              let mascot = bounds["mascot"] as? [String: Any],
              let left = number(mascot["left"]),
              let top = number(mascot["top"]),
              let width = number(mascot["width"]),
              let height = number(mascot["height"]) else {
            return nil
        }

        return CGRect(x: x + left, y: y + top, width: width, height: height)
    }

    private func isAvatarOverlayOpen(_ root: [String: Any]) -> Bool {
        if let isOpen = root["electron-avatar-overlay-open"] as? Bool {
            return isOpen
        }
        if let isOpen = root["electron-avatar-overlay-open"] as? NSNumber {
            return isOpen.boolValue
        }
        return true
    }

    private func number(_ value: Any?) -> CGFloat? {
        if let value = value as? NSNumber {
            return CGFloat(truncating: value)
        }
        if let value = value as? Double {
            return CGFloat(value)
        }
        if let value = value as? Int {
            return CGFloat(value)
        }
        return nil
    }
}

struct LimitRingRenderer {
    var state: LimitState
    var phase: Double
    var showsReadout: Bool = false
    var colorScheme: ColorScheme = .warm

    func draw(in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setShouldAntialias(true)
        context.clear(rect)

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let minSide = min(rect.width, rect.height)
        let urgency = max(urgency(for: state.primary), urgency(for: state.secondary))
        let breathe = CGFloat((sin(phase * 2.0 * .pi) + 1.0) * 0.5)
        let pulse = CGFloat(1.0 + urgency * 0.025 * breathe)
        let outerRadius = (minSide * 0.5 - 16.0) * pulse
        let innerRadius = outerRadius - 13.0

        drawHalo(context, center: center, radius: outerRadius, urgency: CGFloat(urgency), breathe: breathe)
        drawTicks(context, center: center, radius: outerRadius + 5.0)

        if let primary = state.primary {
            drawRing(
                context,
                center: center,
                radius: outerRadius,
                lineWidth: 7.0,
                bucket: primary,
                color: color(forRemaining: primary.remainingPercent, role: .primary),
                trackAlpha: 0.20,
                phase: phase
            )
        } else {
            drawMissingRing(context, center: center, radius: outerRadius, lineWidth: 7.0)
        }

        if let secondary = state.secondary {
            drawRing(
                context,
                center: center,
                radius: innerRadius,
                lineWidth: 4.5,
                bucket: secondary,
                color: color(forRemaining: secondary.remainingPercent, role: .secondary),
                trackAlpha: 0.14,
                phase: phase + 0.18
            )
        }

        drawModelLimitDots(context, center: center, radius: outerRadius + 11.0, state: state)
        if showsReadout {
            drawLimitReadouts(context, center: center, outerRadius: outerRadius, innerRadius: innerRadius, bounds: rect)
        }
        context.restoreGState()
    }

    private enum RingRole {
        case primary
        case secondary
    }

    private struct LimitReadout {
        var text: String
        var ringPoint: CGPoint
        var labelRect: CGRect
        var color: NSColor
        var angle: CGFloat
    }

    private func urgency(for bucket: LimitBucket?) -> Double {
        guard let bucket else { return 0.0 }
        return min(max((45.0 - bucket.remainingPercent) / 45.0, 0.0), 1.0)
    }

    private func drawHalo(_ context: CGContext, center: CGPoint, radius: CGFloat, urgency: CGFloat, breathe: CGFloat) {
        context.saveGState()
        let halo = haloColors(urgency: urgency)
        let color = NSColor(calibratedRed: halo.r, green: halo.g, blue: halo.b, alpha: 0.22 + urgency * 0.16)
        context.setLineCap(.round)
        context.setShadow(offset: .zero, blur: 14.0 + urgency * breathe * 5.0, color: color.withAlphaComponent(0.55).cgColor)
        context.setStrokeColor(color.withAlphaComponent(0.20).cgColor)
        context.setLineWidth(8.0)
        context.addArc(center: center, radius: radius + 3.0, startAngle: 0, endAngle: CGFloat.pi * 2.0, clockwise: false)
        context.strokePath()
        context.setShadow(offset: .zero, blur: 0.0, color: nil)
        context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.045).cgColor)
        context.setLineWidth(1.0)
        context.addArc(center: center, radius: radius + 13.0, startAngle: 0, endAngle: CGFloat.pi * 2.0, clockwise: false)
        context.strokePath()
        context.restoreGState()
    }

    private func drawTicks(_ context: CGContext, center: CGPoint, radius: CGFloat) {
        context.saveGState()
        context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor)
        context.setLineWidth(1.2)
        context.setLineCap(.round)
        for i in 0..<24 {
            guard i % 2 == 0 else { continue }
            let angle = -CGFloat.pi / 2.0 + CGFloat(i) / 24.0 * CGFloat.pi * 2.0
            let inner = radius - 1.5
            let outer = radius + 2.5
            context.move(to: point(center: center, radius: inner, angle: angle))
            context.addLine(to: point(center: center, radius: outer, angle: angle))
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawRing(
        _ context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        bucket: LimitBucket,
        color: NSColor,
        trackAlpha: CGFloat,
        phase: Double
    ) {
        let start = -CGFloat.pi / 2.0
        let remaining = CGFloat(bucket.remainingPercent / 100.0)
        let end = start + max(remaining, 0.018) * CGFloat.pi * 2.0

        context.saveGState()
        context.setLineCap(.round)
        context.setLineWidth(lineWidth)
        context.setStrokeColor(NSColor(calibratedWhite: 0.0, alpha: 0.22).cgColor)
        context.addArc(center: center, radius: radius + 1.0, startAngle: 0, endAngle: CGFloat.pi * 2.0, clockwise: false)
        context.strokePath()

        context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: trackAlpha).cgColor)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2.0, clockwise: false)
        context.strokePath()

        context.setShadow(offset: .zero, blur: 10.0, color: color.withAlphaComponent(0.42).cgColor)
        context.setStrokeColor(color.withAlphaComponent(0.30).cgColor)
        context.setLineWidth(lineWidth + 6.0)
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        context.strokePath()

        context.setShadow(offset: .zero, blur: 4.0, color: color.withAlphaComponent(0.52).cgColor)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        context.strokePath()

        let glintAngle = start + CGFloat(phase.truncatingRemainder(dividingBy: 1.0)) * CGFloat.pi * 2.0
        let glint = point(center: center, radius: radius, angle: glintAngle)
        context.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.38).cgColor)
        context.fillEllipse(in: CGRect(x: glint.x - 1.8, y: glint.y - 1.8, width: 3.6, height: 3.6))
        context.restoreGState()
    }

    private func drawMissingRing(_ context: CGContext, center: CGPoint, radius: CGFloat, lineWidth: CGFloat) {
        context.saveGState()
        context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.16).cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 1.74, clockwise: false)
        context.strokePath()
        context.restoreGState()
    }

    private func drawLimitReadouts(_ context: CGContext, center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat, bounds: CGRect) {
        var readouts: [LimitReadout] = []
        if let primary = state.primary {
            readouts.append(makeReadout(
                text: formatPercent(primary.remainingPercent),
                center: center,
                ringRadius: outerRadius,
                labelRadius: outerRadius + 22.0,
                remainingPercent: primary.remainingPercent,
                color: color(forRemaining: primary.remainingPercent, role: .primary),
                bounds: bounds
            ))
        }

        if let secondary = state.secondary {
            readouts.append(makeReadout(
                text: formatPercent(secondary.remainingPercent),
                center: center,
                ringRadius: innerRadius,
                labelRadius: innerRadius + 21.0,
                remainingPercent: secondary.remainingPercent,
                color: color(forRemaining: secondary.remainingPercent, role: .secondary),
                bounds: bounds
            ))
        }

        for readout in resolveReadoutOverlaps(readouts, bounds: bounds) {
            drawReadout(context, readout: readout)
        }
    }

    private func makeReadout(
        text: String,
        center: CGPoint,
        ringRadius: CGFloat,
        labelRadius: CGFloat,
        remainingPercent: Double,
        color: NSColor,
        bounds: CGRect
    ) -> LimitReadout {
        let angle = -CGFloat.pi / 2.0 + CGFloat(max(remainingPercent, 1.8) / 100.0) * CGFloat.pi * 2.0
        let ringPoint = point(center: center, radius: ringRadius, angle: angle)
        let labelPoint = point(center: center, radius: labelRadius, angle: angle)
        let labelSize = CGSize(width: text.count > 3 ? 45 : 38, height: 22)
        var labelRect = CGRect(
            x: labelPoint.x - labelSize.width / 2,
            y: labelPoint.y - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        labelRect = clamp(labelRect, inside: bounds)
        return LimitReadout(text: text, ringPoint: ringPoint, labelRect: labelRect, color: color, angle: angle)
    }

    private func resolveReadoutOverlaps(_ readouts: [LimitReadout], bounds: CGRect) -> [LimitReadout] {
        guard readouts.count > 1 else { return readouts }
        var resolved = readouts

        let averageAngle = resolved.map(\.angle).reduce(0, +) / CGFloat(resolved.count)
        let tangent = CGPoint(x: -sin(averageAngle), y: cos(averageAngle))
        for index in resolved.indices {
            let direction = index == 0 ? -1.0 : 1.0
            resolved[index].labelRect = clamp(resolved[index].labelRect.offsetBy(dx: tangent.x * 12.0 * direction, dy: tangent.y * 12.0 * direction), inside: bounds)
        }

        for _ in 0..<8 {
            var changed = false
            for firstIndex in 0..<resolved.count {
                for secondIndex in (firstIndex + 1)..<resolved.count {
                    let first = expanded(resolved[firstIndex].labelRect)
                    let second = expanded(resolved[secondIndex].labelRect)
                    guard first.intersects(second) else { continue }

                    let xOverlap = min(first.maxX, second.maxX) - max(first.minX, second.minX)
                    let yOverlap = min(first.maxY, second.maxY) - max(first.minY, second.minY)
                    let gap: CGFloat = 6.0
                    if xOverlap <= yOverlap {
                        let direction: CGFloat = resolved[firstIndex].labelRect.midX <= resolved[secondIndex].labelRect.midX ? -1.0 : 1.0
                        let nudge = xOverlap / 2.0 + gap
                        resolved[firstIndex].labelRect = resolved[firstIndex].labelRect.offsetBy(dx: direction * nudge, dy: 0)
                        resolved[secondIndex].labelRect = resolved[secondIndex].labelRect.offsetBy(dx: -direction * nudge, dy: 0)
                    } else {
                        let direction: CGFloat = resolved[firstIndex].labelRect.midY <= resolved[secondIndex].labelRect.midY ? -1.0 : 1.0
                        let nudge = yOverlap / 2.0 + gap
                        resolved[firstIndex].labelRect = resolved[firstIndex].labelRect.offsetBy(dx: 0, dy: direction * nudge)
                        resolved[secondIndex].labelRect = resolved[secondIndex].labelRect.offsetBy(dx: 0, dy: -direction * nudge)
                    }

                    resolved[firstIndex].labelRect = clamp(resolved[firstIndex].labelRect, inside: bounds)
                    resolved[secondIndex].labelRect = clamp(resolved[secondIndex].labelRect, inside: bounds)
                    changed = true
                }
            }
            if !changed { break }
        }

        return resolved
    }

    private func expanded(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: -4.0, dy: -3.0)
    }

    private func clamp(_ rect: CGRect, inside bounds: CGRect) -> CGRect {
        var clamped = rect
        let inset = bounds.insetBy(dx: 4, dy: 4)
        clamped.origin.x = min(max(clamped.minX, inset.minX), inset.maxX - clamped.width)
        clamped.origin.y = min(max(clamped.minY, inset.minY), inset.maxY - clamped.height)
        return clamped
    }

    private func drawReadout(_ context: CGContext, readout: LimitReadout) {
        context.saveGState()
        context.setLineCap(.round)
        context.setStrokeColor(readout.color.withAlphaComponent(0.44).cgColor)
        context.setLineWidth(1.2)
        context.move(to: readout.ringPoint)
        context.addLine(to: CGPoint(x: readout.labelRect.midX, y: readout.labelRect.midY))
        context.strokePath()

        let path = CGPath(roundedRect: readout.labelRect, cornerWidth: 8.0, cornerHeight: 8.0, transform: nil)
        context.setShadow(offset: .zero, blur: 8.0, color: readout.color.withAlphaComponent(0.22).cgColor)
        context.setFillColor(NSColor(calibratedWhite: 0.055, alpha: 0.78).cgColor)
        context.addPath(path)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0.0, color: nil)
        context.setStrokeColor(readout.color.withAlphaComponent(0.42).cgColor)
        context.setLineWidth(1.0)
        context.addPath(path)
        context.strokePath()

        let readoutAttrs: [NSAttributedString.Key: Any] = [
            .font: FontCache.ringReadout,
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        let text = readout.text as NSString
        let textSize = text.size(withAttributes: readoutAttrs)
        text.draw(at: CGPoint(x: readout.labelRect.midX - textSize.width / 2, y: readout.labelRect.midY - textSize.height / 2 + 0.5), withAttributes: readoutAttrs)
        context.restoreGState()
    }

    private func drawModelLimitDots(_ context: CGContext, center: CGPoint, radius: CGFloat, state: LimitState) {
        let dots = Array(state.additional.prefix(8))
        guard dots.count > 0 else { return }
        context.saveGState()
        for (index, item) in dots.enumerated() {
            let angle = -CGFloat.pi / 2.0 + CGFloat(index) / CGFloat(max(dots.count, 1)) * CGFloat.pi * 2.0
            let dot = point(center: center, radius: radius, angle: angle)
            let color = color(forRemaining: item.bucket.remainingPercent, role: .primary)
            context.setShadow(offset: .zero, blur: 5.0, color: color.withAlphaComponent(0.35).cgColor)
            context.setFillColor(color.withAlphaComponent(0.82).cgColor)
            context.fillEllipse(in: CGRect(x: dot.x - 2.4, y: dot.y - 2.4, width: 4.8, height: 4.8))
        }
        context.restoreGState()
    }

    private func color(forRemaining remaining: Double, role: RingRole) -> NSColor {
        if remaining <= 12 {
            switch colorScheme {
            case .warm: return NSColor(calibratedRed: 0.94, green: 0.22, blue: 0.18, alpha: 0.96)
            case .cool: return NSColor(calibratedRed: 0.88, green: 0.22, blue: 0.38, alpha: 0.96)
            case .cyberpunk: return NSColor(calibratedRed: 1.00, green: 0.12, blue: 0.42, alpha: 0.96)
            case .original: return NSColor(calibratedRed: 1.00, green: 0.26, blue: 0.22, alpha: 0.96)
            }
        }
        if remaining <= 30 {
            switch colorScheme {
            case .warm: return NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.15, alpha: 0.96)
            case .cool: return NSColor(calibratedRed: 0.68, green: 0.42, blue: 0.90, alpha: 0.96)
            case .cyberpunk: return NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.12, alpha: 0.96)
            case .original: return NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.20, alpha: 0.96)
            }
        }
        if role == .secondary {
            switch colorScheme {
            case .warm: return NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.28, alpha: 0.90)
            case .cool: return NSColor(calibratedRed: 0.58, green: 0.45, blue: 0.92, alpha: 0.90)
            case .cyberpunk: return NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.72, alpha: 0.90)
            case .original: return NSColor(calibratedRed: 0.36, green: 0.70, blue: 1.00, alpha: 0.90)
            }
        }
        switch colorScheme {
        case .warm: return NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.16, alpha: 0.96)
        case .cool: return NSColor(calibratedRed: 0.42, green: 0.55, blue: 1.00, alpha: 0.96)
        case .cyberpunk: return NSColor(calibratedRed: 0.08, green: 0.96, blue: 0.85, alpha: 0.96)
        case .original: return NSColor(calibratedRed: 0.24, green: 0.92, blue: 0.74, alpha: 0.96)
        }
    }

    private func haloColors(urgency: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch colorScheme {
        case .warm: return (0.85 + urgency * 0.12, 0.60 - urgency * 0.25, 0.18 - urgency * 0.08)
        case .cool: return (0.35 + urgency * 0.35, 0.45 - urgency * 0.10, 0.90 - urgency * 0.30)
        case .cyberpunk: return (0.20 + urgency * 0.55, 0.90 - urgency * 0.50, 0.80 - urgency * 0.35)
        case .original: return (0.23 + urgency * 0.55, 0.85 - urgency * 0.30, 0.78 - urgency * 0.48)
        }
    }

    private func point(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func formatPercent(_ percent: Double) -> String {
        if abs(percent.rounded() - percent) < 0.05 {
            return "\(Int(percent.rounded()))%"
        }
        return String(format: "%.1f%%", percent)
    }
}

final class LimitRingView: NSView {
    var state: LimitState = .empty {
        didSet { needsDisplay = true }
    }
    var phase: Double = 0 {
        didSet { needsDisplay = true }
    }
    var showsReadout: Bool = false {
        didSet { needsDisplay = true }
    }
    var colorScheme: ColorScheme = .warm {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        LimitRingRenderer(state: state, phase: phase, showsReadout: showsReadout, colorScheme: colorScheme).draw(in: bounds)
    }
}

struct LimitBarRenderer {
    var state: LimitState
    var colorScheme: ColorScheme = .warm
    var showsValues: Bool = true
    var barThickness: CGFloat = 4.5

    func draw(in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setShouldAntialias(true)
        context.clear(rect)

        let barHeight: CGFloat = barThickness
        let spacing: CGFloat = 3.0
        let textGap: CGFloat = 6.0
        let barWidth = rect.width

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: FontCache.barText,
            .foregroundColor: NSColor.white.withAlphaComponent(0.82)
        ]

        var cursorY = rect.height

        if let primary = state.primary {
            if showsValues {
                let text = formatPercent(primary.remainingPercent)
                let textSize = (text as NSString).size(withAttributes: textAttrs)
                let textY = cursorY - textGap - textSize.height
                (text as NSString).draw(at: CGPoint(x: 0, y: textY), withAttributes: textAttrs)
                cursorY = textY - spacing
            }
            let color = barColor(forRemaining: primary.remainingPercent, role: .primary)
            let barY = cursorY - barHeight
            drawBar(context, rect: CGRect(x: 0, y: barY, width: barWidth, height: barHeight), remaining: primary.remainingPercent, color: color)
            cursorY = barY - spacing
        }

        if let secondary = state.secondary {
            if showsValues {
                let text = formatPercent(secondary.remainingPercent)
                let textSize = (text as NSString).size(withAttributes: textAttrs)
                let textY = cursorY - textGap - textSize.height
                (text as NSString).draw(at: CGPoint(x: 0, y: textY), withAttributes: textAttrs)
                cursorY = textY - spacing
            }
            let color = barColor(forRemaining: secondary.remainingPercent, role: .secondary)
            let barY = cursorY - barHeight
            drawBar(context, rect: CGRect(x: 0, y: barY, width: barWidth, height: barHeight), remaining: secondary.remainingPercent, color: color)
        }

        context.restoreGState()
    }

    private enum BarRole { case primary, secondary }

    private func drawBar(_ context: CGContext, rect: CGRect, remaining: Double, color: NSColor) {
        let cornerRadius = rect.height / 2.0
        let trackPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.07).cgColor)
        context.addPath(trackPath)
        context.fillPath()

        let fillWidth = max(rect.width * CGFloat(max(remaining, 0.0) / 100.0), rect.height)
        let fillRect = CGRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        let fillPath = CGPath(roundedRect: fillRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.setShadow(offset: .zero, blur: 5.0, color: color.withAlphaComponent(0.30).cgColor)
        context.setFillColor(color.cgColor)
        context.addPath(fillPath)
        context.fillPath()
    }

    private func barColor(forRemaining remaining: Double, role: BarRole) -> NSColor {
        if remaining <= 12 {
            switch colorScheme {
            case .warm: return NSColor(calibratedRed: 0.94, green: 0.22, blue: 0.18, alpha: 0.96)
            case .cool: return NSColor(calibratedRed: 0.88, green: 0.22, blue: 0.38, alpha: 0.96)
            case .cyberpunk: return NSColor(calibratedRed: 1.00, green: 0.12, blue: 0.42, alpha: 0.96)
            case .original: return NSColor(calibratedRed: 1.00, green: 0.26, blue: 0.22, alpha: 0.96)
            }
        }
        if remaining <= 30 {
            switch colorScheme {
            case .warm: return NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.15, alpha: 0.96)
            case .cool: return NSColor(calibratedRed: 0.68, green: 0.42, blue: 0.90, alpha: 0.96)
            case .cyberpunk: return NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.12, alpha: 0.96)
            case .original: return NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.20, alpha: 0.96)
            }
        }
        if role == .secondary {
            switch colorScheme {
            case .warm: return NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.28, alpha: 0.90)
            case .cool: return NSColor(calibratedRed: 0.58, green: 0.45, blue: 0.92, alpha: 0.90)
            case .cyberpunk: return NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.72, alpha: 0.90)
            case .original: return NSColor(calibratedRed: 0.36, green: 0.70, blue: 1.00, alpha: 0.90)
            }
        }
        switch colorScheme {
        case .warm: return NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.16, alpha: 0.96)
        case .cool: return NSColor(calibratedRed: 0.42, green: 0.55, blue: 1.00, alpha: 0.96)
        case .cyberpunk: return NSColor(calibratedRed: 0.08, green: 0.96, blue: 0.85, alpha: 0.96)
        case .original: return NSColor(calibratedRed: 0.24, green: 0.92, blue: 0.74, alpha: 0.96)
        }
    }

    private func formatPercent(_ percent: Double) -> String {
        if abs(percent.rounded() - percent) < 0.05 {
            return "\(Int(percent.rounded()))%"
        }
        return String(format: "%.1f%%", percent)
    }
}

final class LimitBarView: NSView {
    var state: LimitState = .empty {
        didSet { needsDisplay = true }
    }
    var colorScheme: ColorScheme = .warm {
        didSet { needsDisplay = true }
    }
    var showsValues: Bool = true {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    var barThickness: CGFloat = 4.5 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        LimitBarRenderer(state: state, colorScheme: colorScheme, showsValues: showsValues, barThickness: barThickness).draw(in: bounds)
    }
}

struct MinimalRenderer {
    var state: LimitState
    var colorScheme: ColorScheme = .warm

    func draw(in rect: CGRect) {
        guard state.primary != nil || state.secondary != nil else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setShouldAntialias(true)
        context.clear(rect)

        let boldFont = FontCache.minimalBold
        let sepFont = FontCache.minimalSep

        var parts: [(text: String, attrs: [NSAttributedString.Key: Any])] = []
        if let primary = state.primary {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: boldFont,
                .foregroundColor: color(forRemaining: primary.remainingPercent)
            ]
            parts.append((formatPercent(primary.remainingPercent), attrs))
        }
        if state.primary != nil && state.secondary != nil {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: sepFont,
                .foregroundColor: NSColor.white.withAlphaComponent(0.25)
            ]
            parts.append(("  ", attrs))
        }
        if let secondary = state.secondary {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: boldFont,
                .foregroundColor: color(forRemaining: secondary.remainingPercent)
            ]
            parts.append((formatPercent(secondary.remainingPercent), attrs))
        }

        guard !parts.isEmpty else { context.restoreGState(); return }

        let combined = NSMutableAttributedString()
        for part in parts {
            combined.append(NSAttributedString(string: part.text, attributes: part.attrs))
        }

        let textSize = combined.size()
        let bgPadding: CGFloat = 4.0
        let bgRect = CGRect(
            x: 0,
            y: (rect.height - textSize.height) / 2.0 - 1,
            width: textSize.width + bgPadding * 2,
            height: textSize.height + bgPadding
        )

        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 5.0, cornerHeight: 5.0, transform: nil)
        context.setFillColor(NSColor(calibratedWhite: 0.04, alpha: 0.72).cgColor)
        context.addPath(bgPath)
        context.fillPath()

        combined.draw(at: CGPoint(x: bgPadding, y: bgRect.minY + bgPadding / 2))

        context.restoreGState()
    }

    private func color(forRemaining remaining: Double) -> NSColor {
        if remaining <= 12 {
            switch colorScheme {
            case .warm: return NSColor(calibratedRed: 0.94, green: 0.22, blue: 0.18, alpha: 0.96)
            case .cool: return NSColor(calibratedRed: 0.88, green: 0.22, blue: 0.38, alpha: 0.96)
            case .cyberpunk: return NSColor(calibratedRed: 1.00, green: 0.12, blue: 0.42, alpha: 0.96)
            case .original: return NSColor(calibratedRed: 1.00, green: 0.26, blue: 0.22, alpha: 0.96)
            }
        }
        if remaining <= 30 {
            switch colorScheme {
            case .warm: return NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.15, alpha: 0.96)
            case .cool: return NSColor(calibratedRed: 0.68, green: 0.42, blue: 0.90, alpha: 0.96)
            case .cyberpunk: return NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.12, alpha: 0.96)
            case .original: return NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.20, alpha: 0.96)
            }
        }
        switch colorScheme {
        case .warm: return NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.16, alpha: 0.96)
        case .cool: return NSColor(calibratedRed: 0.42, green: 0.55, blue: 1.00, alpha: 0.96)
        case .cyberpunk: return NSColor(calibratedRed: 0.08, green: 0.96, blue: 0.85, alpha: 0.96)
        case .original: return NSColor(calibratedRed: 0.24, green: 0.92, blue: 0.74, alpha: 0.96)
        }
    }

    private func formatPercent(_ percent: Double) -> String {
        if abs(percent.rounded() - percent) < 0.05 {
            return "\(Int(percent.rounded()))%"
        }
        return String(format: "%.1f%%", percent)
    }
}

final class MinimalView: NSView {
    var state: LimitState = .empty {
        didSet { needsDisplay = true }
    }
    var colorScheme: ColorScheme = .warm {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if state.primary != nil || state.secondary != nil {
            MinimalRenderer(state: state, colorScheme: colorScheme).draw(in: bounds)
        }
    }
}

final class SettingsPanelController: NSObject {
    private let window: NSWindow
    private var settings: LimitRingsSettings
    private let onApply: (LimitRingsSettings) -> Void

    private var colorPopup: NSPopUpButton!
    private var speedPopup: NSPopUpButton!
    private var displayPopup: NSPopUpButton!
    private var dataPopup: NSPopUpButton!
    private var readoutPopup: NSPopUpButton!
    private var langPopup: NSPopUpButton!
    private var offsetXField: NSTextField!
    private var offsetYField: NSTextField!
    private var thicknessField: NSTextField!
    private var colorLabel: NSTextField!
    private var speedLabel: NSTextField!
    private var displayLabel: NSTextField!
    private var dataLabel: NSTextField!
    private var readoutLabel: NSTextField!
    private var offsetXLabel: NSTextField!
    private var offsetYLabel: NSTextField!
    private var thicknessLabel: NSTextField!
    private var langLabel: NSTextField!

    init(settings: LimitRingsSettings, onApply: @escaping (LimitRingsSettings) -> Void) {
        self.settings = settings
        self.onApply = onApply

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("设置", "Settings", lang: settings.language)
        window.isReleasedWhenClosed = false
        super.init()

        buildUI()
        localizeLabels()
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = contentView

        let margin: CGFloat = 24
        let rowH: CGFloat = 26
        let gap: CGFloat = 10
        let labelW: CGFloat = 90
        let popupW: CGFloat = 150
        let topY: CGFloat = 370

        func rowOffset(_ index: Int) -> CGFloat {
            topY - CGFloat(index) * (rowH + gap)
        }

        colorLabel = makeLabel(frame: NSRect(x: margin, y: rowOffset(0), width: labelW, height: rowH))
        contentView.addSubview(colorLabel)
        colorPopup = NSPopUpButton(frame: NSRect(x: margin + labelW + 8, y: rowOffset(0), width: popupW, height: rowH))
        colorPopup.target = self
        colorPopup.action = #selector(colorChanged)
        contentView.addSubview(colorPopup)

        speedLabel = makeLabel(frame: NSRect(x: margin, y: rowOffset(1), width: labelW, height: rowH))
        contentView.addSubview(speedLabel)
        speedPopup = NSPopUpButton(frame: NSRect(x: margin + labelW + 8, y: rowOffset(1), width: popupW, height: rowH))
        speedPopup.target = self
        speedPopup.action = #selector(speedChanged)
        contentView.addSubview(speedPopup)

        displayLabel = makeLabel(frame: NSRect(x: margin, y: rowOffset(2), width: labelW, height: rowH))
        contentView.addSubview(displayLabel)
        displayPopup = NSPopUpButton(frame: NSRect(x: margin + labelW + 8, y: rowOffset(2), width: popupW, height: rowH))
        displayPopup.target = self
        displayPopup.action = #selector(displayChanged)
        contentView.addSubview(displayPopup)

        dataLabel = makeLabel(frame: NSRect(x: margin, y: rowOffset(3), width: labelW, height: rowH))
        contentView.addSubview(dataLabel)
        dataPopup = NSPopUpButton(frame: NSRect(x: margin + labelW + 8, y: rowOffset(3), width: popupW, height: rowH))
        dataPopup.target = self
        dataPopup.action = #selector(dataChanged)
        contentView.addSubview(dataPopup)

        readoutLabel = makeLabel(frame: NSRect(x: margin, y: rowOffset(4), width: labelW, height: rowH))
        contentView.addSubview(readoutLabel)
        readoutPopup = NSPopUpButton(frame: NSRect(x: margin + labelW + 8, y: rowOffset(4), width: popupW, height: rowH))
        readoutPopup.target = self
        readoutPopup.action = #selector(readoutChanged)
        contentView.addSubview(readoutPopup)

        langLabel = makeLabel(frame: NSRect(x: margin, y: rowOffset(5), width: labelW, height: rowH))
        contentView.addSubview(langLabel)
        langPopup = NSPopUpButton(frame: NSRect(x: margin + labelW + 8, y: rowOffset(5), width: popupW, height: rowH))
        langPopup.target = self
        langPopup.action = #selector(langChanged)
        contentView.addSubview(langPopup)

        offsetXLabel = makeLabel(frame: NSRect(x: margin, y: rowOffset(6), width: labelW, height: rowH))
        contentView.addSubview(offsetXLabel)
        offsetXField = makeNumericField(frame: NSRect(x: margin + labelW + 8, y: rowOffset(6), width: 70, height: rowH))
        offsetXField.target = self
        offsetXField.action = #selector(offsetXChanged)
        contentView.addSubview(offsetXField)

        offsetYLabel = makeLabel(frame: NSRect(x: margin, y: rowOffset(7), width: labelW, height: rowH))
        contentView.addSubview(offsetYLabel)
        offsetYField = makeNumericField(frame: NSRect(x: margin + labelW + 8, y: rowOffset(7), width: 70, height: rowH))
        offsetYField.target = self
        offsetYField.action = #selector(offsetYChanged)
        contentView.addSubview(offsetYField)

        thicknessLabel = makeLabel(frame: NSRect(x: margin, y: rowOffset(8), width: labelW, height: rowH))
        contentView.addSubview(thicknessLabel)
        thicknessField = makeNumericField(frame: NSRect(x: margin + labelW + 8, y: rowOffset(8), width: 70, height: rowH))
        thicknessField.target = self
        thicknessField.action = #selector(thicknessChanged)
        contentView.addSubview(thicknessField)

        let resetBtn = NSButton(frame: NSRect(x: margin, y: 20, width: 100, height: 28))
        resetBtn.bezelStyle = .rounded
        resetBtn.target = self
        resetBtn.action = #selector(resetDefaults)
        contentView.addSubview(resetBtn)
        resetBtn.title = L10n.text("恢复默认", "Reset", lang: settings.language)

        let okBtn = NSButton(frame: NSRect(x: 320 - margin - 80, y: 20, width: 80, height: 28))
        okBtn.bezelStyle = .rounded
        okBtn.keyEquivalent = "\r"
        okBtn.target = self
        okBtn.action = #selector(applyAndClose)
        okBtn.title = L10n.text("好", "OK", lang: settings.language)
        contentView.addSubview(okBtn)

        populatePopups()
        syncControlsFromSettings()
    }

    private func makeLabel(frame: NSRect) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }

    private func makeNumericField(frame: NSRect) -> NSTextField {
        let field = NSTextField(frame: frame)
        field.alignment = .left
        field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return field
    }

    private func populatePopups() {
        colorPopup.removeAllItems()
        for scheme in ColorScheme.allCases {
            colorPopup.addItem(withTitle: L10n.colorSchemeName(scheme, lang: settings.language))
        }
        speedPopup.removeAllItems()
        for speed in TrackingSpeed.allCases {
            speedPopup.addItem(withTitle: L10n.speedName(speed, lang: settings.language))
        }
        displayPopup.removeAllItems()
        for mode in DisplayMode.allCases {
            displayPopup.addItem(withTitle: L10n.displayModeName(mode, lang: settings.language))
        }
        dataPopup.removeAllItems()
        for source in DataSource.allCases {
            dataPopup.addItem(withTitle: L10n.dataSourceName(source, lang: settings.language))
        }
        readoutPopup.removeAllItems()
        for mode in ReadoutMode.allCases {
            readoutPopup.addItem(withTitle: L10n.readoutModeName(mode, lang: settings.language))
        }
        langPopup.removeAllItems()
        for lang in AppLanguage.allCases {
            langPopup.addItem(withTitle: L10n.languageName(lang, lang: settings.language))
        }
    }

    private func syncControlsFromSettings() {
        colorPopup.selectItem(at: ColorScheme.allCases.firstIndex(of: settings.colorScheme) ?? 0)
        speedPopup.selectItem(at: TrackingSpeed.allCases.firstIndex(of: settings.trackingSpeed) ?? 0)
        displayPopup.selectItem(at: DisplayMode.allCases.firstIndex(of: settings.displayMode) ?? 0)
        dataPopup.selectItem(at: DataSource.allCases.firstIndex(of: settings.dataSource) ?? 0)
        readoutPopup.selectItem(at: ReadoutMode.allCases.firstIndex(of: settings.readoutMode) ?? 0)
        offsetXField.stringValue = String(format: "%.0f", settings.barOffsetX)
        offsetYField.stringValue = String(format: "%.0f", settings.barOffsetY)
        thicknessField.stringValue = String(format: "%.1f", settings.barThickness)
        langPopup.selectItem(at: AppLanguage.allCases.firstIndex(of: settings.language) ?? 0)
    }

    private func localizeLabels() {
        let lang = settings.language
        colorLabel.stringValue = L10n.text("配色方案", "Color Scheme", lang: lang)
        speedLabel.stringValue = L10n.text("跟随速度", "Tracking", lang: lang)
        displayLabel.stringValue = L10n.text("显示模式", "Display", lang: lang)
        dataLabel.stringValue = L10n.text("数据源", "Data Source", lang: lang)
        readoutLabel.stringValue = L10n.text("数值显示", "Readout", lang: lang)
        offsetXLabel.stringValue = L10n.text("条状偏移X", "Bar Offset X", lang: lang)
        offsetYLabel.stringValue = L10n.text("条状偏移Y", "Bar Offset Y", lang: lang)
        thicknessLabel.stringValue = L10n.text("条状粗细", "Bar Thick", lang: lang)
        langLabel.stringValue = L10n.text("界面语言", "Language", lang: lang)
    }

    @objc private func colorChanged() {
        settings.colorScheme = ColorScheme.allCases[colorPopup.indexOfSelectedItem]
        apply()
    }

    @objc private func speedChanged() {
        settings.trackingSpeed = TrackingSpeed.allCases[speedPopup.indexOfSelectedItem]
        apply()
    }

    @objc private func displayChanged() {
        settings.displayMode = DisplayMode.allCases[displayPopup.indexOfSelectedItem]
        apply()
    }

    @objc private func dataChanged() {
        settings.dataSource = DataSource.allCases[dataPopup.indexOfSelectedItem]
        apply()
    }

    @objc private func readoutChanged() {
        settings.readoutMode = ReadoutMode.allCases[readoutPopup.indexOfSelectedItem]
        apply()
    }

    @objc private func langChanged() {
        settings.language = AppLanguage.allCases[langPopup.indexOfSelectedItem]
        window.title = L10n.text("设置", "Settings", lang: settings.language)
        localizeLabels()
        populatePopups()
        syncControlsFromSettings()
        apply()
    }

    @objc private func offsetXChanged() {
        settings.barOffsetX = CGFloat(Double(offsetXField.stringValue) ?? 0)
        apply()
    }

    @objc private func offsetYChanged() {
        settings.barOffsetY = CGFloat(Double(offsetYField.stringValue) ?? 0)
        apply()
    }

    @objc private func thicknessChanged() {
        let val = CGFloat(Double(thicknessField.stringValue) ?? 4.5)
        settings.barThickness = max(val, 1.0)
        apply()
    }

    @objc private func resetDefaults() {
        settings = LimitRingsSettings(
            colorScheme: .warm, trackingSpeed: .fast, displayMode: .rings,
            dataSource: .both, readoutMode: .always,
            barOffsetX: 0, barOffsetY: 0, barThickness: 4.5,
            language: .zh
        )
        localizeLabels()
        populatePopups()
        syncControlsFromSettings()
        apply()
    }

    @objc private func applyAndClose() {
        apply()
        window.orderOut(nil)
    }

    private func apply() {
        settings.save()
        onApply(settings)
    }
}

final class LimitRingsApp: NSObject {
    private let config: LimitRingsConfig
    private let stateReader: LimitStateReader
    private let frameReader: PetFrameReader
    private let panel: NSPanel
    private let ringView: LimitRingView
    private let barPanel: NSPanel
    private let barView: LimitBarView
    private let minimalPanel: NSPanel
    private let minimalView: MinimalView
    private let stateQueue = DispatchQueue(label: "codex-pet-limit-rings.state-reader")
    private var statusItem: NSStatusItem?
    private var summaryItem: NSMenuItem?
    private var showRingsItem: NSMenuItem?
    private var stateTimer: Timer?
    private var frameTimer: Timer?
    private var animationTimer: Timer?
    private var hoverTimer: Timer?
    private var mouseDownMonitor: Any?
    private var mouseDragMonitor: Any?
    private var mouseUpMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var startTime = Date()
    private var currentPetFrameAppKit: CGRect?
    private var dragCenterOffset: CGPoint?
    private var barDragOffset: CGPoint?
    private var minimalDragOffset: CGPoint?
    private var lastPetFrameTopLeft: CGRect?
    private var ringsVisible: Bool
    private var stateReadInFlight = false
    private var lastRawState: LimitState = .empty
    private var holdDraggedFrameUntil: Date?
    private var settings: LimitRingsSettings
    private var settingsController: SettingsPanelController?
    private var settingsItem: NSMenuItem?
    private var refreshItem: NSMenuItem?
    private var quitItem: NSMenuItem?

    init(config: LimitRingsConfig) {
        self.config = config
        self.stateReader = LimitStateReader(logsPath: config.logsPath, authPath: config.authPath)
        self.frameReader = PetFrameReader(globalStatePath: config.globalStatePath)
        self.ringView = LimitRingView(frame: CGRect(origin: .zero, size: CGSize(width: config.fallbackSize, height: config.fallbackSize)))
        self.ringsVisible = UserDefaults.standard.object(forKey: ringsVisibleDefaultsKey) as? Bool ?? true
        self.settings = LimitRingsSettings.load()
        self.panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: config.fallbackSize, height: config.fallbackSize)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = ringView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        self.barView = LimitBarView(frame: .zero)
        self.barPanel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        barPanel.contentView = barView
        barPanel.backgroundColor = .clear
        barPanel.isOpaque = false
        barPanel.hasShadow = false
        barPanel.ignoresMouseEvents = true
        barPanel.level = .statusBar
        barPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        self.minimalView = MinimalView(frame: .zero)
        self.minimalPanel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        minimalPanel.contentView = minimalView
        minimalPanel.backgroundColor = .clear
        minimalPanel.isOpaque = false
        minimalPanel.hasShadow = false
        minimalPanel.ignoresMouseEvents = true
        minimalPanel.level = .statusBar
        minimalPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        super.init()
        applySettingsToViews()
    }

    private func applySettingsToViews() {
        ringView.colorScheme = settings.colorScheme
        barView.colorScheme = settings.colorScheme
        barView.showsValues = settings.readoutMode == .always
        barView.barThickness = settings.barThickness
        minimalView.colorScheme = settings.colorScheme
    }

    func applySettings(_ newSettings: LimitRingsSettings) {
        let speedChanged = newSettings.trackingSpeed != settings.trackingSpeed
        let displayModeChanged = newSettings.displayMode != settings.displayMode
        let dataChanged = newSettings.dataSource != settings.dataSource || newSettings.readoutMode != settings.readoutMode
        let geometryChanged = newSettings.barOffsetX != settings.barOffsetX
            || newSettings.barOffsetY != settings.barOffsetY
            || newSettings.barThickness != settings.barThickness
        settings = newSettings
        applySettingsToViews()
        if speedChanged {
            restartFrameTimer()
        }
        if displayModeChanged || geometryChanged {
            lastPetFrameTopLeft = nil
        }
        if dataChanged {
            let filtered = lastRawState.filtered(for: settings.dataSource)
            ringView.state = filtered
            barView.state = filtered
            minimalView.state = filtered
            updateSummaryMenuItem()
            updateState()
        }
        updateFrame()
        updateRingVisibility()
        rebuildMenuLocalization()
    }

    private func restartFrameTimer() {
        frameTimer?.invalidate()
        frameTimer = Timer.scheduledTimer(withTimeInterval: settings.trackingSpeed.interval, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
    }

    func run() {
        installStatusMenu()
        updateState()
        updateFrame()
        updateRingVisibility()

        stateTimer = Timer.scheduledTimer(withTimeInterval: limitStatePollInterval, repeats: true) { [weak self] _ in
            self?.updateState()
        }
        frameTimer = Timer.scheduledTimer(withTimeInterval: settings.trackingSpeed.interval, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.updateTooltip(at: NSEvent.mouseLocation)
        }
        installDragFollow()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, self.settings.displayMode == .rings else { return }
            self.ringView.phase = Date().timeIntervalSince(self.startTime) / 4.6
        }
    }

    private func updateState() {
        guard !stateReadInFlight else { return }
        stateReadInFlight = true
        stateQueue.async { [weak self] in
            guard let self else { return }
            let state = self.stateReader.readLatest()
            DispatchQueue.main.async {
                self.lastRawState = state
                let filtered = state.filtered(for: self.settings.dataSource)
                self.ringView.state = filtered
                self.barView.state = filtered
                self.minimalView.state = filtered
                self.updateSummaryMenuItem()
                self.stateReadInFlight = false
            }
        }
    }

    private func updateFrame() {
        if dragCenterOffset != nil {
            return
        }
        if let holdDraggedFrameUntil, Date() < holdDraggedFrameUntil {
            return
        }
        holdDraggedFrameUntil = nil

        guard let petFrame = frameReader.readPetFrameTopLeft() else {
            if currentPetFrameAppKit != nil {
                currentPetFrameAppKit = nil
                lastPetFrameTopLeft = nil
                dragCenterOffset = nil
                barDragOffset = nil
                minimalDragOffset = nil
                ringView.showsReadout = false
                panel.orderOut(nil)
                barPanel.orderOut(nil)
                minimalPanel.orderOut(nil)
            }
            return
        }

        let moved = lastPetFrameTopLeft == nil ||
            abs(petFrame.origin.x - lastPetFrameTopLeft!.origin.x) > 0.5 ||
            abs(petFrame.origin.y - lastPetFrameTopLeft!.origin.y) > 0.5 ||
            abs(petFrame.width - lastPetFrameTopLeft!.width) > 0.5 ||
            abs(petFrame.height - lastPetFrameTopLeft!.height) > 0.5

        currentPetFrameAppKit = appKitRectFromTopLeft(petFrame)
        lastPetFrameTopLeft = petFrame

        if moved {
            setPanelFrame(forPetFrameTopLeft: petFrame)
            switch settings.displayMode {
            case .rings: break
            case .bars: setBarPanelFrame(forPetFrameTopLeft: petFrame)
            case .minimal: setMinimalPanelFrame()
            }
        }

        if ringsVisible {
            switch settings.displayMode {
            case .rings:
                if !panel.isVisible { panel.orderFrontRegardless() }
            case .bars:
                if !barPanel.isVisible { barPanel.orderFrontRegardless() }
            case .minimal:
                if !minimalPanel.isVisible { minimalPanel.orderFrontRegardless() }
            }
        }
    }

    private func setPanelFrame(forPetFrameTopLeft petFrame: CGRect) {
        let padding: CGFloat = 38
        let size = max(petFrame.width, petFrame.height) + padding * 2
        let topLeft = CGPoint(x: petFrame.midX - size / 2, y: petFrame.midY - size / 2)
        let origin = appKitOriginFromTopLeft(topLeft, size: CGSize(width: size, height: size))

        panel.setFrame(CGRect(origin: origin, size: CGSize(width: size, height: size)), display: false)
    }

    private func setBarPanelFrame(forPetFrameTopLeft petFrame: CGRect) {
        let barGap: CGFloat = 4.0
        let barH: CGFloat = settings.barThickness
        let spacing: CGFloat = 3.0
        let textGap: CGFloat = 6.0
        let textH: CGFloat = 12.0
        let barWidth = petFrame.width

        var rows: CGFloat = 0
        let showText = settings.readoutMode == .always
        if settings.dataSource != .secondary { rows += 1 }
        if settings.dataSource != .primary { rows += 1 }
        if rows == 0 { rows = 1 }

        var h: CGFloat = rows * barH + max(rows - 1, 0) * spacing
        if showText { h += rows * (textGap + textH) + max(rows - 1, 0) * spacing }

        let barSize = CGSize(width: barWidth, height: h)
        // Place bars ABOVE the pet (head), with user offsets
        let barTopLeft = CGPoint(
            x: petFrame.midX - barWidth / 2 + settings.barOffsetX,
            y: petFrame.minY - barGap - h + settings.barOffsetY
        )
        let barOrigin = appKitOriginFromTopLeft(barTopLeft, size: barSize)
        barPanel.setFrame(CGRect(origin: barOrigin, size: barSize), display: false)
    }

    private func setMinimalPanelFrame() {
        guard let petFrame = currentPetFrameAppKit else { return }
        let hasPrimary = settings.dataSource != .secondary
        let hasSecondary = settings.dataSource != .primary
        let items: CGFloat = (hasPrimary ? 1 : 0) + (hasSecondary ? 1 : 0)
        let w: CGFloat = max(items, 1) * 42 + 10
        let h: CGFloat = 22
        let offsetX: CGFloat = 4.0
        let offsetY: CGFloat = 4.0
        // AppKit coords: maxX = right edge, maxY = top edge (y goes up)
        let origin = CGPoint(x: petFrame.maxX + offsetX, y: petFrame.maxY + offsetY)
        minimalPanel.setFrame(CGRect(origin: origin, size: CGSize(width: w, height: h)), display: false)
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.title = ""
            button.image = makeStatusBarIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "Codex Pet Limit Rings"
        }

        let menu = NSMenu()
        let summary = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        summaryItem = summary

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: "", action: #selector(toggleRings(_:)), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        showRingsItem = showItem

        refreshItem = NSMenuItem(title: "", action: #selector(refreshNow(_:)), keyEquivalent: "r")
        refreshItem?.target = self
        if let refreshItem { menu.addItem(refreshItem) }

        settingsItem = NSMenuItem(title: "", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem?.target = self
        if let settingsItem { menu.addItem(settingsItem) }

        menu.addItem(.separator())

        quitItem = NSMenuItem(title: "", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem?.target = self
        if let quitItem { menu.addItem(quitItem) }

        item.menu = menu
        rebuildMenuLocalization()
        updateSummaryMenuItem()
        updateShowRingsMenuItem()
    }

    private func makeStatusBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setStroke()
        let outer = NSBezierPath()
        outer.appendArc(
            withCenter: NSPoint(x: 9, y: 9),
            radius: 6.7,
            startAngle: 22,
            endAngle: 338,
            clockwise: false
        )
        outer.lineWidth = 2.0
        outer.lineCapStyle = .round
        outer.stroke()

        let inner = NSBezierPath()
        inner.appendArc(
            withCenter: NSPoint(x: 9, y: 9),
            radius: 3.6,
            startAngle: 210,
            endAngle: 82,
            clockwise: false
        )
        inner.lineWidth = 1.6
        inner.lineCapStyle = .round
        inner.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func updateSummaryMenuItem() {
        guard let summaryItem else { return }
        let lang = settings.language
        let primary = ringView.state.primary.map { "\(L10n.text("短窗口", "Short", lang: lang)) \(formatPercent($0.remainingPercent))" }
        let secondary = ringView.state.secondary.map { "\(L10n.text("周限额", "Weekly", lang: lang)) \(formatPercent($0.remainingPercent))" }
        let pieces = [primary, secondary].compactMap { $0 }
        if pieces.isEmpty {
            summaryItem.title = L10n.text("等待限额数据…", "Waiting for Codex limit data", lang: lang)
        } else {
            let source = ringView.state.source == "live"
                ? L10n.text("实时", "Live", lang: lang)
                : L10n.text("缓存", "Cached", lang: lang)
            summaryItem.title = "\(source) " + pieces.joined(separator: " | ")
        }
    }

    private func rebuildMenuLocalization() {
        let lang = settings.language
        showRingsItem?.title = L10n.text("显示", "Show", lang: lang)
        refreshItem?.title = L10n.text("立即刷新", "Refresh Now", lang: lang)
        settingsItem?.title = L10n.text("设置…", "Settings…", lang: lang)
        quitItem?.title = L10n.text("退出 Codex Pet Limit Rings", "Quit Codex Pet Limit Rings", lang: lang)
        updateSummaryMenuItem()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        if settingsController == nil {
            settingsController = SettingsPanelController(settings: settings) { [weak self] newSettings in
                self?.applySettings(newSettings)
            }
        }
        settingsController?.show()
    }

    private func updateShowRingsMenuItem() {
        showRingsItem?.state = ringsVisible ? .on : .off
    }

    private func updateRingVisibility() {
        updateShowRingsMenuItem()
        if ringsVisible, currentPetFrameAppKit != nil {
            switch settings.displayMode {
            case .rings:
                panel.orderFrontRegardless()
                barPanel.orderOut(nil)
                minimalPanel.orderOut(nil)
            case .bars:
                panel.orderOut(nil)
                barPanel.orderFrontRegardless()
                minimalPanel.orderOut(nil)
            case .minimal:
                panel.orderOut(nil)
                barPanel.orderOut(nil)
                minimalPanel.orderFrontRegardless()
            }
            updateTooltip(at: NSEvent.mouseLocation)
        } else {
            ringView.showsReadout = false
            panel.orderOut(nil)
            barPanel.orderOut(nil)
            minimalPanel.orderOut(nil)
        }
    }

    private func setRingsVisible(_ visible: Bool) {
        ringsVisible = visible
        UserDefaults.standard.set(visible, forKey: ringsVisibleDefaultsKey)
        updateRingVisibility()
    }

    @objc private func toggleRings(_ sender: NSMenuItem) {
        setRingsVisible(!ringsVisible)
    }

    @objc private func refreshNow(_ sender: NSMenuItem) {
        updateState()
        updateFrame()
        updateRingVisibility()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func installDragFollow() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.beginDragFollowIfNeeded(at: NSEvent.mouseLocation)
            }
        }
        mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.continueDragFollow(at: NSEvent.mouseLocation)
            }
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.endDragFollow()
            }
        }
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateTooltip(at: NSEvent.mouseLocation)
            }
        }
    }

    private func beginDragFollowIfNeeded(at mouse: CGPoint) {
        guard ringsVisible else { return }
        updateFrame()
        guard let currentPetFrameAppKit else { return }
        let hitTarget = currentPetFrameAppKit.insetBy(dx: -24, dy: -24)
        guard hitTarget.contains(mouse) else { return }

        dragCenterOffset = CGPoint(x: panel.frame.midX - mouse.x, y: panel.frame.midY - mouse.y)
        barDragOffset = CGPoint(x: barPanel.frame.midX - mouse.x, y: barPanel.frame.midY - mouse.y)
        minimalDragOffset = CGPoint(x: minimalPanel.frame.midX - mouse.x, y: minimalPanel.frame.midY - mouse.y)
        holdDraggedFrameUntil = nil
    }

    private func continueDragFollow(at mouse: CGPoint) {
        guard let offset = dragCenterOffset else { return }
        let size = panel.frame.size
        let center = CGPoint(x: mouse.x + offset.x, y: mouse.y + offset.y)
        let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        ringView.showsReadout = false

        if let barOffset = barDragOffset {
            let barSize = barPanel.frame.size
            let barCenter = CGPoint(x: mouse.x + barOffset.x, y: mouse.y + barOffset.y)
            barPanel.setFrame(CGRect(origin: CGPoint(x: barCenter.x - barSize.width / 2, y: barCenter.y - barSize.height / 2), size: barSize), display: false)
        }

        if let minimalOffset = minimalDragOffset {
            let ms = minimalPanel.frame.size
            let mc = CGPoint(x: mouse.x + minimalOffset.x, y: mouse.y + minimalOffset.y)
            minimalPanel.setFrame(CGRect(origin: CGPoint(x: mc.x - ms.width / 2, y: mc.y - ms.height / 2), size: ms), display: false)
        }
    }

    private func endDragFollow() {
        guard dragCenterOffset != nil else { return }
        dragCenterOffset = nil
        barDragOffset = nil
        minimalDragOffset = nil
        holdDraggedFrameUntil = Date().addingTimeInterval(1.25)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) { [weak self] in
            self?.updateFrame()
        }
    }

    private func updateTooltip(at mouse: CGPoint) {
        if !ringsVisible || currentPetFrameAppKit == nil || dragCenterOffset != nil {
            if settings.readoutMode == .hover {
                ringView.showsReadout = false
                barView.showsValues = false
            }
            return
        }

        switch settings.displayMode {
        case .rings:
            if settings.readoutMode == .always {
                ringView.showsReadout = true
            } else {
                ringView.showsReadout = isHoveringRingOrPet(mouse)
            }
            barView.showsValues = false
        case .bars:
            if settings.readoutMode == .always {
                barView.showsValues = true
            } else {
                barView.showsValues = isHoveringBarOrPet(mouse)
            }
            ringView.showsReadout = false
        case .minimal:
            ringView.showsReadout = false
            barView.showsValues = false
        }
    }

    private func isHoveringBarOrPet(_ mouse: CGPoint) -> Bool {
        if let petFrame = currentPetFrameAppKit,
           petFrame.insetBy(dx: -10, dy: -10).contains(mouse) {
            return true
        }
        return barPanel.frame.insetBy(dx: -4, dy: -4).contains(mouse)
    }

    private func isHoveringRingOrPet(_ mouse: CGPoint) -> Bool {
        if let petFrame = currentPetFrameAppKit,
           petFrame.insetBy(dx: -10, dy: -10).contains(mouse) {
            return true
        }

        let frame = panel.frame
        guard frame.insetBy(dx: -4, dy: -4).contains(mouse) else {
            return false
        }

        let local = CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
        let center = CGPoint(x: frame.width / 2, y: frame.height / 2)
        let distance = hypot(local.x - center.x, local.y - center.y)
        let radius = min(frame.width, frame.height) * 0.5 - 16.0
        return distance >= radius - 24.0 && distance <= radius + 19.0
    }

    private func appKitOriginFromTopLeft(_ topLeft: CGPoint, size: CGSize) -> CGPoint {
        let topLeftRect = CGRect(origin: topLeft, size: size)
        guard let screen = screenForTopLeftRect(topLeftRect) else {
            return CGPoint(x: topLeft.x, y: max(0, config.fallbackSize - topLeft.y))
        }

        let screenTopLeftFrame = topLeftFrame(for: screen)
        let localX = topLeft.x - screenTopLeftFrame.minX
        let localY = topLeft.y - screenTopLeftFrame.minY
        return CGPoint(x: screen.frame.minX + localX, y: screen.frame.maxY - localY - size.height)
    }

    private func appKitRectFromTopLeft(_ rect: CGRect) -> CGRect {
        guard let screen = screenForTopLeftRect(rect) else {
            return rect
        }

        let screenTopLeftFrame = topLeftFrame(for: screen)
        let localX = rect.minX - screenTopLeftFrame.minX
        let localY = rect.minY - screenTopLeftFrame.minY
        return CGRect(
            x: screen.frame.minX + localX,
            y: screen.frame.maxY - localY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func screenForTopLeftRect(_ rect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let screen = screens.first(where: { topLeftFrame(for: $0).contains(center) }) {
            return screen
        }

        return screens.min {
            distanceSquared(center, to: topLeftFrame(for: $0)) < distanceSquared(center, to: topLeftFrame(for: $1))
        }
    }

    private func topLeftFrame(for screen: NSScreen) -> CGRect {
        let primaryMaxY = (primaryScreen() ?? NSScreen.screens.first)?.frame.maxY ?? screen.frame.maxY
        return CGRect(
            x: screen.frame.minX,
            y: primaryMaxY - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    private func primaryScreen() -> NSScreen? {
        NSScreen.screens.first { abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5 }
    }

    private func distanceSquared(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }

    private func formatPercent(_ percent: Double) -> String {
        if abs(percent.rounded() - percent) < 0.05 {
            return "\(Int(percent.rounded()))%"
        }
        return String(format: "%.1f%%", percent)
    }
}

func renderPreview(config: LimitRingsConfig) -> Bool {
    let state = LimitStateReader(logsPath: config.logsPath, authPath: config.authPath).readLatest()
    let size = CGSize(width: config.fallbackSize, height: config.fallbackSize)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    LimitRingRenderer(state: state, phase: 0.18, showsReadout: true, colorScheme: .warm).draw(in: CGRect(origin: .zero, size: size))
    image.unlockFocus()

    guard let previewPath = config.previewPath,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        return false
    }

    do {
        try FileManager.default.createDirectory(at: previewPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: previewPath)
        return true
    } catch {
        fputs("codex-pet-limit-rings: could not write preview: \(error)\n", stderr)
        return false
    }
}

func parseConfig() -> LimitRingsConfig? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let codexHome = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path)
    var config = LimitRingsConfig(
        codexHome: codexHome,
        globalStatePath: codexHome.appendingPathComponent(".codex-global-state.json"),
        logsPath: defaultLogsPath(codexHome: codexHome),
        authPath: codexHome.appendingPathComponent("auth.json"),
        previewPath: nil
    )

    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--help", "-h":
            print("""
            Usage: codex-pet-limit-rings [--preview PATH] [--codex-home PATH] [--logs PATH] [--auth PATH] [--state PATH]

            Draws a transparent Codex rate-limit rings around the current pet.
            """)
            exit(0)
        case "--preview":
            guard let value = args.first else { return nil }
            args.removeFirst()
            config.previewPath = URL(fileURLWithPath: value)
        case "--codex-home":
            guard let value = args.first else { return nil }
            args.removeFirst()
            let url = URL(fileURLWithPath: value)
            config.codexHome = url
            config.globalStatePath = url.appendingPathComponent(".codex-global-state.json")
            config.logsPath = defaultLogsPath(codexHome: url)
            config.authPath = url.appendingPathComponent("auth.json")
        case "--logs":
            guard let value = args.first else { return nil }
            args.removeFirst()
            config.logsPath = URL(fileURLWithPath: value)
        case "--auth":
            guard let value = args.first else { return nil }
            args.removeFirst()
            config.authPath = URL(fileURLWithPath: value)
        case "--state":
            guard let value = args.first else { return nil }
            args.removeFirst()
            config.globalStatePath = URL(fileURLWithPath: value)
        case "--size":
            guard let value = args.first, let size = Double(value) else { return nil }
            args.removeFirst()
            config.fallbackSize = CGFloat(size)
        default:
            fputs("codex-pet-limit-rings: unknown argument \(arg)\n", stderr)
            return nil
        }
    }

    return config
}

func defaultLogsPath(codexHome: URL) -> URL {
    let logs2 = codexHome.appendingPathComponent("logs_2.sqlite")
    if FileManager.default.fileExists(atPath: logs2.path) {
        return logs2
    }
    return codexHome.appendingPathComponent("logs_1.sqlite")
}

guard let config = parseConfig() else {
    fputs("codex-pet-limit-rings: invalid arguments. Use --help.\n", stderr)
    exit(2)
}

if config.previewPath != nil {
    exit(renderPreview(config: config) ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let rings = LimitRingsApp(config: config)
rings.run()
app.run()
