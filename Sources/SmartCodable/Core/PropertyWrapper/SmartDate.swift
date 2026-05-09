//
//  SmartDate.swift
//  SmartCodable
//
//  Created by Mccc on 2025/4/30.
//

import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - @SmartDate 属性包装器

/// 单字段多格式日期解析器。自动识别时间戳（秒/毫秒）和 8 种日期字符串格式。
///
/// **WHAT**: 同时支持时间戳和字符串日期，每个字段可独立指定编码格式。
/// 解码时自动识别输入格式并记录，编码时默认沿用输入格式的策略。
///
/// **HOW**: 内置 DateParser 按以下顺序尝试：
/// 1. 时间戳（Double 值，>1_000_000_000_000 为毫秒，否则为秒）
/// 2. 8 种已知字符串格式（yyyy-MM-dd HH:mm:ss 等）
/// 3. ISO8601DateFormatter 作为兜底
///
/// **vs .date(options:)**: 整个模型格式统一用 `.date(options:)` 全局配置；
/// 单字段格式特殊或需要自动识别多种格式时用 `@SmartDate`。
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Property-Wrappers.md`
@propertyWrapper
public struct SmartDate: PropertyWrapperable {
    
    public var wrappedValue: Date?
    public init(wrappedValue: Date?) {
        self.wrappedValue = wrappedValue
        self.encodeFormat = nil
    }
    
    public func wrappedValueDidFinishMapping() -> SmartDate? {
        // Date 不是 SmartDecodable 模型，不需要 didFinishMapping
        return nil
    }
    public static func createInstance(with value: Any) -> SmartDate? {
        if let value = value as? Date {
            return SmartDate(wrappedValue: value)
        }
        return nil
    }
    

    
    private var encodeFormat: DateStrategy?

    public init(wrappedValue: Date?, encodeFormat: SmartDate.DateStrategy? = nil) {
        self.wrappedValue = wrappedValue
        self.encodeFormat = encodeFormat
    }
}


extension SmartDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        let raw: Any
        if let double = try? container.decode(Double.self) {
            raw = double
        } else if let string = try? container.decode(String.self) {
            raw = string
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date value")
        }
        
        guard let (date, format) = DateParser.parse(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(raw)")
        }
        
        self.wrappedValue = date
        if self.encodeFormat == nil {
            self.encodeFormat = format
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let date = wrappedValue else {
            return try container.encodeNil()
        }

        let format = encodeFormat ?? .timestamp
        
        switch format {
        case .timestamp:
            try container.encode(date.timeIntervalSince1970)
        case .timestampMilliseconds:
            try container.encode(Int(date.timeIntervalSince1970 * 1000))
        case .iso8601:
            let formatter = ISO8601DateFormatter()
            try container.encode(formatter.string(from: date))
        case .formatted(let format):
            try container.encode(format.string(from: date))
        }
    }
}


extension SmartDate {
    /// 编码策略：控制 Date 的输出格式。每个 @SmartDate 字段独立指定。
    /// 解码时如果 encodeFormat 为 nil，会自动从输入格式推断。
    public enum DateStrategy {
        case timestamp                  // 秒时间戳
        case timestampMilliseconds      // 毫秒时间戳
        case iso8601                    // ISO8601 标准格式
        case formatted(DateFormatter)   // 自定义格式器
    }
}


// MARK: - DateParser 日期解析器

/// 内置日期解析器。先尝试时间戳，再按顺序尝试 8 种已知格式，最后 ISO8601 兜底。
///
/// **时间戳阈值**: `>1_000_000_000_000` 为毫秒，否则为秒。
/// 2001 年 9 月 9 日的秒时间戳才到 10 亿，而毫秒时间戳已是 1000 亿以上，
/// 用一千亿做分界线在可预见的未来都是安全的。
struct DateParser {
    private static let knownFormats: [String] = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
        "yyyy/MM/dd",
        "MM/dd/yyyy",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    ]

    // https://developer.apple.com/library/archive/qa/qa1480/_index.html
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func parse(_ raw: Any) -> (Date, SmartDate.DateStrategy)? {
        if let result = parseTimestamp(from: raw) {
            return result
        }

        if let string = raw as? String {
            // try knownFormats
            let formatter = DateFormatter()
            formatter.locale = locale
            for format in knownFormats {
                formatter.dateFormat = format
                if let date = formatter.date(from: string) {
                    return (date, .formatted(formatter))
                }
            }

            // 尝试 ISO8601 yyyy-MM-dd'T'HH:mm:ssZ
            let isoFormatter = ISO8601DateFormatter()
            if let date = isoFormatter.date(from: string) {
                return (date, .iso8601)
            }
        }

        return nil
    }
    
    private static func parseTimestamp(from raw: Any) -> (Date, SmartDate.DateStrategy)? {
        if let double = raw as? Double ?? Double(raw as? String ?? "") {
            if double > 1_000_000_000_000 {
                return (Date(timeIntervalSince1970: double / 1000), .timestampMilliseconds)
            } else {
                return (Date(timeIntervalSince1970: double), .timestamp)
            }
        }
        return nil
    }
}
