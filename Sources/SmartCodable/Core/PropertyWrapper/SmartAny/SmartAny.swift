//
//  SmartAny.swift
//  SmartCodable
//
//  Created by Mccc on 2024/6/13.
//

// MARK: - @SmartAny 属性包装器

/// 支持 `Any`、`[Any]`、`[String: Any]` 等动态类型的 Codable 属性包装器。
///
/// **WHAT**: 解决原生 Codable 不支持 `Any` 类型的问题。通过内部 SmartAnyImpl
/// 枚举将 JSON 值归一化为 5 种情况（number/string/dict/array/null），实现
/// 任意 JSON 结构的解析和编码。
///
/// **HOW (解码)**:
/// 1. `unwrap(as: SmartAnyImpl.self)` → 走 `unwrapSmartAny()` 将 JSON 转为 SmartAnyImpl
/// 2. `peel` 将 SmartAnyImpl 展开为原生 Swift 类型（[String: Any]、[Any] 等）
/// 3. 检查 peel 结果能否 as? T，通过则赋值
/// 4. 失败则尝试 `T.init(from: decoder)` —— 兼容 T 本身是 Decodable 的情况
///
/// **HOW (编码)**:
/// 1. [String: Any] → dict.cover 转为 [String: SmartAnyImpl]
/// 2. [Any] → arr.cover 转为 [SmartAnyImpl]
/// 3. SmartCodableX 模型 → 直接 encode
/// 4. 其他类型 → SmartAnyImpl(from:) 转换后 encode
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Property-Wrappers.md`
@propertyWrapper
public struct SmartAny<T>: PropertyWrapperable {
    
    public var wrappedValue: T

    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
    
    public func wrappedValueDidFinishMapping() -> SmartAny<T>? {
        if var temp = wrappedValue as? SmartDecodable {
            temp.didFinishMapping()
            return SmartAny(wrappedValue: temp as! T)
        }
        return nil
    }
    
    public static func createInstance(with value: Any) -> SmartAny<T>? {
        if let value = value as? T {
            return SmartAny(wrappedValue: value)
        }
        return nil
    }

    
}


extension SmartAny: Codable {
    /// 解码：JSON → SmartAnyImpl → peel → as? T
    public init(from decoder: Decoder) throws {
        guard let decoder = decoder as? JSONDecoderImpl else {
            throw DecodingError.typeMismatch(SmartAnyImpl.self, DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "Expected \(Self.self) value，but an exception occurred！Please report this issue（请上报该问题）")
            )
        }

        // null + ignoreNull 时抛错，让外层容器走兼容路径（回退默认值）
        if decoder.json == .null && SmartCodableOptions.ignoreNull {
            throw DecodingError.typeMismatch(Self.self, DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "Expected \(Self.self) value，but an exception occurred！")
            )
        }

        // 主路径：JSON → SmartAnyImpl → peel → as? T
        if let decoded = try? decoder.unwrap(as: SmartAnyImpl.self), let peel = decoded.peel as? T {
            self = .init(wrappedValue: peel)
        } else {

            // 回退路径：T 本身是 Decodable（如 T 是某个具体 Codable 类型）
            if let _type = T.self as? Decodable.Type {
                if let decoded = try _type.init(from: decoder) as? T {
                    self = .init(wrappedValue: decoded)
                    return
                }
            }

            // 容器兼容路径会捕获此错误并回退到默认值
            throw DecodingError.typeMismatch(Self.self, DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "Expected \(Self.self) value，but an exception occurred！")
            )
        }
    }
    
    /// 编码：根据 wrappedValue 的类型走不同路径
    public func encode(to encoder: Encoder) throws {

        var container = encoder.singleValueContainer()

        // [String: Any] → dict.cover → [String: SmartAnyImpl]
        if let dict = wrappedValue as? [String: Any] {
            let value = dict.cover
            try container.encode(value)
        // [Any] → arr.cover → [SmartAnyImpl]
        } else if let arr = wrappedValue as? [Any] {
            let value = arr.cover
            try container.encode(value)
        // SmartCodableX 模型 → 直接 encode
        } else if let model = wrappedValue as? SmartCodableX {
            try container.encode(model)
        // 其他类型 → SmartAnyImpl(from:) 单值转换
        } else {
            let value = SmartAnyImpl(from: wrappedValue)
            try container.encode(value)
        }
    }
}
