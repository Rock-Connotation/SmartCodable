//
//  SmartIgnored.swift
//  SmartCodable
//
//  Created by Mccc on 2024/4/30.
//

import Foundation

// MARK: - @SmartIgnored 属性包装器

/// 保留本地属性值，防止 JSON 覆盖。
///
/// **WHAT**: 标记某属性不参与 JSON 解析——解码时保留用户声明的初始值，
/// 编码时默认不输出（可通过 isEncodable 独立控制）。
///
/// **HOW (伪忽略机制)**: 不是真正跳过解析，而是"参与解码但主动失败"：
/// 1. 检测到 SmartSentinel 注入的 parsingMark → 主动抛错
/// 2. 外层容器的兼容路径捕获错误 → 回退到 DecodingCache 中的初始值
/// 3. 如果不存在 parsingMark（其他解析器调用）→ 从 cache 读取初始值
///
/// **vs CodingKeys 排除**:
/// - @SmartIgnored: 运行时处理，有抛错+回退开销，但支持 isEncodable 灵活控制
/// - CodingKeys 排除: 编译期处理，零开销，但编译期固定，编码不灵活
/// 大量属性不需要解析时优先用 CodingKeys 排除（性能更优）。
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Property-Wrappers.md`
@propertyWrapper
public struct SmartIgnored<T>: PropertyWrapperable {
    
    /// The underlying value being wrapped
    public var wrappedValue: T

    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
    public func wrappedValueDidFinishMapping() -> SmartIgnored<T>? {
        if var temp = wrappedValue as? SmartDecodable {
            temp.didFinishMapping()
            return SmartIgnored(wrappedValue: temp as! T)
        }
        return nil
    }
        
    /// Creates an instance from any value if possible
    public static func createInstance(with value: Any) -> SmartIgnored? {
        if let value = value as? T {
            return SmartIgnored(wrappedValue: value)
        }
        return nil
    }
    
    
    
    /// Determines whether this property should be included in encoding
    var isEncodable: Bool = false
    
    /// Initializes an SmartIgnored with a wrapped value and encoding control
    /// - Parameters:
    ///   - wrappedValue: The initial/default value
    ///   - isEncodable: Whether the property should be included in encoding (default: false)
    public init(wrappedValue: T, isEncodable: Bool = false) {
        self.wrappedValue = wrappedValue
        self.isEncodable = isEncodable
    }
}


extension SmartIgnored: Codable {
    /// 三步式伪忽略解码：
    /// 1. 非 SmartJSONDecoder → Provider 类型默认值
    /// 2. 检测到 parsingMark（SmartSentinel 标记）→ 主动抛错让容器走兼容路径
    /// 3. 其他解析器触发 → 从 DecodingCache 读取缓存的初始值
    public init(from decoder: Decoder) throws {
        guard let impl = decoder as? JSONDecoderImpl else {
            wrappedValue = try Patcher<T>.defaultForType()
            return
        }

        // SmartJSONDecoder 上下文：检测到 SmartSentinel 标记后主动抛错
        if let key = CodingUserInfoKey.parsingMark, let _ = impl.userInfo[key] {
            throw DecodingError.typeMismatch(SmartIgnored<T>.self, DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "\(Self.self) does not participate in the parsing, please ignore it.")
            )
        }

        // 其他三方解析器触发：从 cache 回退初始值
        wrappedValue = try impl.smartDecode(type: T.self)
    }

    public func encode(to encoder: Encoder) throws {

        guard isEncodable else { return }

        if let encodableValue = wrappedValue as? Encodable {
            try encodableValue.encode(to: encoder)
        } else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}


extension JSONDecoderImpl {
    fileprivate func smartDecode<T>(type: T.Type) throws -> T {
        try cache.initialValue(forKey: codingPath.last, codingPath: codingPath)
    }
}
