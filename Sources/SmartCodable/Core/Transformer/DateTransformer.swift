//
//  DateTransformer.swift
//  SmartCodable
//
//  Created by Mccc on 2024/4/9.
//

import Foundation


/// 日期转换器：支持多种日期格式的编解码转换
/// - WHAT：将 JSON 中的日期值（字符串/数字）转换为 Swift Date 类型
/// - HOW：根据 DateStrategy 策略自动解析 ISO8601、时间戳、自定义格式
/// - WHY：处理不同 API 的日期格式差异，与 SmartDate 属性包装器配合使用
public struct SmartDateTransformer: ValueTransformable {

    public typealias JSON =  Any
    public typealias Object = Date


    private var strategy: SmartDate.DateStrategy


    public init(strategy: SmartDate.DateStrategy) {
        self.strategy = strategy
    }

    /// 从 JSON 值转换为 Date
    /// - WHAT：解析 JSON 中的日期值
    /// - HOW：委托 DateParser 自动识别日期格式（ISO8601/时间戳/字符串）
    /// - WHY：支持多种日期格式，无需手动判断类型
    public func transformFromJSON(_ value: Any) -> Date? {

        guard let (date, _) = DateParser.parse(value) else { return nil }
        return date
    }

    /// 将 Date 转换为 JSON 值
    /// - WHAT：按策略将 Date 序列化为 JSON 值
    /// - HOW：根据 strategy 选择输出格式（时间戳/ISO8601/自定义格式）
    /// - WHY：保持编码格式与解码策略一致，确保往返转换正确
    public func transformToJSON(_ value: Date) -> Any? {

        switch strategy {
        case .timestamp:
            return value.timeIntervalSince1970
        case .timestampMilliseconds:
            return value.timeIntervalSince1970 * 1000.0
        case .formatted(let formatter):
            return formatter.string(from: value)
        case .iso8601:
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: value)
        }
    }
}
