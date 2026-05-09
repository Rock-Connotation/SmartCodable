//
//  SmartSentinel.swift
//  BTCodable
//
//  Created by Mccc on 2023/8/7.
//

import Foundation


// MARK: - SmartSentinel 诊断系统总控

/// 解码诊断系统的对外入口。只观察和记录，不参与解码逻辑。
///
/// **WHAT**: 提供全局 debugMode 开关、parsingMark 生成、字段级 monitorLog、统一 monitorLogs 输出。
///
/// **WHY**: 原生 JSONDecoder 遇到第一个错误就抛，SmartCodable 回退默认值继续解析。
/// 如果没有诊断系统，开发者不知道哪些字段被修正了。SmartSentinel 在不影响解码结果的前提下，
/// 记录所有字段级问题，一次解析全部暴露。
///
/// **HOW (数据流)**:
/// smartDecode → parsingMark() 生成 UUID → 注入 userInfo →
/// 容器解码失败 → monitorLog → LogCache.save(按 parsingMark 聚合) →
/// 解析结束 → monitorLogs → LogCache.formatLogs → print + onLogGenerated 回调 → clearCache
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Diagnostics.md`
public struct SmartSentinel {
    
    /// 全局调试模式，默认 .none。NSLock 保护读写，生产环境保持 .none。
    public static var debugMode: Level {
        get { return _mode }
        set { _mode = newValue }
    }

    /// 设置日志回调，闭包在主线程执行。通过 handlerQueue 串行队列保护写入。
    public static func onLogGenerated(handler: @escaping (String) -> Void) {
        handlerQueue.sync {
            self.logsHandler = handler
        }
    }

    /// 缩进空格
    public static let space: String = "   "
    /// keyed 容器标记
    public static let keyContainerSign: String = "╆━ "
    /// unkeyed 容器标记
    public static let unKeyContainerSign: String = "╆━ "
    /// 属性字段标记
    public static let attributeSign: String = "┆┄ "
    
    
    fileprivate static var isValid: Bool {
        return debugMode != .none
    }

    private static var _mode = Level.none
    /// 全局日志缓存，按 parsingMark 聚合多次解析的日志
    private static var cache = LogCache()
    /// 回调闭包，handlerQueue 保护读写，主线程派发执行
    private static var logsHandler: ((String) -> Void)?
    /// 串行队列，保证 logsHandler 的读写安全
    private static let handlerQueue = DispatchQueue(label: "com.smartcodable.handler", qos: .utility)

}


// MARK: - 字段级日志

extension SmartSentinel {
    /// 字段解码失败时由容器调用。根据 value 状态分三种日志类型：
    /// - nil（缺 key）→ keyNotFound（verbose）
    /// - .null       → valueNotFound（verbose）
    /// - 其他         → typeMismatch（alert）
    /// isOptionalLog 为 true 时跳过缺 key 和 null（预期行为），类型不匹配不受影响。
    static func monitorLog<T>(impl: JSONDecoderImpl, isOptionalLog: Bool = false,
                              forKey key: CodingKey?, value: JSONValue?, type: T.Type) {

        guard SmartSentinel.debugMode != .none else { return }
        guard let key = key else { return }
        // SmartIgnored 的值不由 JSON 决定，跳过日志避免噪声
        let typeString = String(describing: T.self)
        guard !typeString.starts(with: "SmartIgnored<") else { return }
        
        let className = impl.cache.findSnapShot(with: impl.codingPath)?.objectTypeName ?? ""
        var path = impl.codingPath
        path.append(key)
        
        var address = ""
        if let parsingMark = CodingUserInfoKey.parsingMark {
            address = impl.userInfo[parsingMark] as? String ?? ""
        }
        
        if let entry = value {
            if entry.isNull { // 值为null
                if isOptionalLog { return }
                let error = DecodingError._valueNotFound(key: key, expectation: T.self, codingPath: path)
                SmartSentinel.verboseLog(error, className: className, parsingMark: address)
            } else { // value类型不匹配
                let error = DecodingError._typeMismatch(at: path, expectation: T.self, desc: entry.debugDataTypeDescription)
                SmartSentinel.alertLog(error: error, className: className, parsingMark: address)
            }
        } else { // key不存在或value为nil
            if isOptionalLog { return }
            let error = DecodingError._keyNotFound(key: key, codingPath: path)
            SmartSentinel.verboseLog(error, className: className, parsingMark: address)
        }
    }
    
    private static func verboseLog(_ error: DecodingError, className: String, parsingMark: String) {
        logIfNeeded(level: .verbose) {
            cache.save(error: error, className: className, parsingMark: parsingMark)
        }
    }
    
    private static func alertLog(error: DecodingError, className: String, parsingMark: String) {
        logIfNeeded(level: .alert) {
            cache.save(error: error, className: className, parsingMark: parsingMark)
        }
    }
    
    /// 解析结束时统一输出。从 userInfo 读 header/footer 上下文，调 LogCache.formatLogs 拼接，
    /// 打印到控制台并通过 onLogGenerated 回调派发到主线程，最后 clearCache 清理缓存。
    static func monitorLogs(in name: String, parsingMark: String, impl: JSONDecoderImpl) {
        
        guard SmartSentinel.isValid else { return }
        
        var header: String?
        if let key = CodingUserInfoKey.logContextHeader {
            header = impl.userInfo[key] as? String
        }
        
        var footer: String?
        if let key = CodingUserInfoKey.logContextFooter {
            footer = impl.userInfo[key] as? String
        }

        
        if let format = cache.formatLogs(parsingMark: parsingMark) {
            var message: String = ""
            message += getHeader(context: header)
            message += name + " 👈🏻 👀\n"
            message += format
            message += getFooter(context: footer)
            print(message)
            
            handlerQueue.sync {
                if let handler = logsHandler {
                    DispatchQueue.main.async {
                        handler(message)
                    }
                }
            }
        }
        
        cache.clearCache(parsingMark: parsingMark)
    }
}



// MARK: - 入口级日志

extension SmartSentinel {
    /// 入口级错误日志（如 JSON 格式错误、designatedPath 不存在）。
    /// 不走 LogCache 聚合，立即格式化输出。适用于解析根本无法启动的场景。
    static func monitorAndPrint(level: SmartSentinel.Level = .alert, debugDescription: String, error: Error? = nil, in type: Any.Type?) {
        logIfNeeded(level: level) {
            let decodingError = (error as? DecodingError) ?? DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: debugDescription, underlyingError: error))
            if let logItem = LogItem.make(with: decodingError) {
                
                var message: String = ""
                message += getHeader()
                if let type = type {
                    message += "\(type) 👈🏻 👀\n"
                }
                message += logItem.formartMessage + "\n"
                message += getFooter()
                print(message)
                
                handlerQueue.sync {
                    if let handler = logsHandler {
                        DispatchQueue.main.async {
                            handler(message)
                        }
                    }
                }
            }
        }
    }
}


// MARK: - 工具方法

extension SmartSentinel {
    /// 生成 `"SmartMark" + UUID` 标记。每次 smartDecode 调用生成新标记，
    /// 通过 userInfo 传播给所有子容器，实现同一次解析的日志聚合。
    static func parsingMark() -> String {
        let mark = "SmartMark" + UUID().uuidString
        return mark
    }
}


extension SmartSentinel {

    /// 日志级别，按 rawValue 过滤：
    /// - `.none(0)`：不记录
    /// - `.verbose(1)`：全部记录（缺 key + null + 类型不匹配）
    /// - `.alert(2)`：仅类型不匹配
    public enum Level: Int, Sendable {
        case none       // 不记录
        case verbose    // 详细（缺 key + null + 类型不匹配）
        case alert      // 仅类型不匹配
    }


    static func getHeader(context: String? = nil) -> String {
        let line = "\n================================  [Smart Sentinel]  ================================\n"
        
        if let c = context, !c.isEmpty {
            return line + c + "\n\n"
            
        } else {
            return line
        }
    }
    
    static func getFooter(context: String? = nil) -> String {
        let line = "====================================================================================\n"
        
        if let c = context, !c.isEmpty {
            return "\n" + c + "\n" + line
        } else {
            return line
        }
    }
    
    /// 级别过滤：debugMode ≤ 传入 level 时记录。
    /// debugMode 是全局允许级别，level 是当前日志严重级别。
    /// .verbose(1) 允许 rawValue ≤ 1 的日志（即 verbose 和 alert 都记录）。
    /// .alert(2) 只允许 rawValue ≤ 2 的日志（即只有 alert 被记录）。
    private static func logIfNeeded(level: SmartSentinel.Level, callback: () -> ()) {
        if SmartSentinel.debugMode.rawValue <= level.rawValue {
            callback()
        }
    }
}
