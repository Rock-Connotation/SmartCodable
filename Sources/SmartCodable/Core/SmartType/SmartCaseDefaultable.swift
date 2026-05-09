//
//  CaseDefaultable.swift
//  BTCodable
//
//  Created by Mccc on 2023/8/1.
//

// MARK: - SmartCaseDefaultable 枚举默认值

/// 为 RawRepresentable 枚举提供 SmartCodable 解码支持。
///
/// **WHAT**: 遵循此协议的枚举自动获得 init(from:) 实现：先 decode RawValue，
/// 再通过 init(rawValue:) 构造枚举值。SmartCaseDefaultable 适用于简单枚举
/// （RawRepresentable + CaseIterable），SmartAssociatedEnumerable 适用于
/// 带关联值的复杂枚举。
///
/// **WHY**: 原生 Codable 对枚举的支持有两种局限：
/// 1. 简单枚举（RawRepresentable）虽然 Codable 自动合成，但遇到未知 rawValue 直接抛错，
///    SmartCodable 无法介入提供默认值
/// 2. 带关联值的枚举 Codable 完全不支持自动合成，必须手写 init(from:)
/// 这两个协议让枚举纳入 SmartCodable 的韧性解析体系，配合 resolveStrategy 提供默认值。
///
/// **HOW**: SmartCaseDefaultable 的 init(from:) 从 singleValueContainer 解码 rawValue，
/// 通过 init(rawValue:) 构造；失败时抛 dataCorrupted 错误。
/// SmartAssociatedEnumerable 依赖 valueTransformer 查找自定义转换器来解析关联值。
///
/// - SeeAlso: `Document/SmartCodable-Learning/01-Codable-Foundations/Type-Conversion.md`
import Foundation

public protocol SmartCaseDefaultable: RawRepresentable, Codable, CaseIterable { }
public extension SmartCaseDefaultable where Self: Decodable, Self.RawValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decoded = try container.decode(RawValue.self)
        if let v = Self.init(rawValue: decoded) {
            self = v
        } else {
            let des = "Cannot initialize \(Self.self) from invalid \(RawValue.self) value `\(decoded)`"
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: des))
        }
    }
}



/// 带关联值的枚举的 Codable 支持协议。
///
/// **WHAT**: 适用于有 associated value 的枚举。要求提供 defaultCase 用于解码失败时的兜底值，
/// 可选实现 encodeValue() 用于序列化。解码不走 RawRepresentable 路径，而是依赖
/// valueTransformer 查找自定义的 JSON → 枚举转换逻辑。
///
/// **WHY**: Swift 对带关联值的枚举完全不提供 Codable 自动合成，必须手写全部逻辑。
/// 此协议将自定义转换器（Transformer）与枚举绑定，让枚举也纳入 SmartCodable 的
/// 统一转换器体系，并在解码失败时回退到 defaultCase 而非抛错。
public protocol SmartAssociatedEnumerable: Codable {
    static var defaultCase: Self { get }
    func encodeValue() -> Encodable?
}
extension SmartAssociatedEnumerable {
    public func encodeValue() -> Encodable? { return nil }
}

public extension SmartAssociatedEnumerable {
    init(from decoder: Decoder) throws {
        
        guard let _decoder = decoder as? JSONDecoderImpl else {
            let des = "Cannot initiali"
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: des))
        }
        
        guard let tranformer = _decoder.cache.valueTransformer(for: _decoder.codingPath.last, in: _decoder.codingPath.dropLast()),
           let decoded = tranformer.transformFromJSON(_decoder.json) as? Self else {
            throw DecodingError.valueNotFound(Self.self, DecodingError.Context.init(codingPath: _decoder.codingPath, debugDescription: "No custom parsing policy is implemented for associated value enumerations"))
        }
        self = decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = encodeValue() {
            try container.encode(value)
        }
    }
}
