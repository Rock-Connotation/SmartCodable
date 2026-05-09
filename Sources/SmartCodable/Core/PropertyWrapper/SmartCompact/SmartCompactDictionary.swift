//
//  SmartLossyDictionary.swift
//  SmartCodable
//
//  Created by qixin on 2026/1/22.
//

import Foundation


extension SmartCompact {
    /// 容错字典包装器：遍历 keyedContainer，跳过无法解析的键值对。
    ///
    /// **Key 约束**: `LosslessStringConvertible`——JSON 字典 key 始终是字符串，
    /// 需要能从中构造（如 `Int("123")` 成功，自定义结构体通常失败）。
    /// **Value 为 Any 时**：先尝试 SmartAnyImpl.peel，再尝试 Value 本身的 Decodable 解码。
    ///
    /// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Property-Wrappers.md`
    @propertyWrapper
    public struct Dictionary<Key: Hashable & LosslessStringConvertible, Value> {
        
        public var wrappedValue: [Key: Value]
        
        public init(wrappedValue: [Key: Value]) {
            self.wrappedValue = wrappedValue
        }
    }
}


extension SmartCompact.Dictionary: Codable {

    /// 容错字典解码：遍历 allKeys，逐个解析键值对。
    /// 1. Value 是具体 Decodable 类型 → container.decodeIfPresent 直接解码
    /// 2. Value 是 Any 类型 → 先 SmartAnyImpl.unwrap + peel，再尝试 Decodable.init(from:)
    /// 无法解析的键值对被静默跳过。
    public init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: _JSONKey.self)
        var result: [Key: Value] = [:]


        for key in container.allKeys {

            guard let typedKey = Key(key.stringValue) else { continue }

            // Value 是具体 Decodable 类型 → 直接解析
            if let _type = Value.self as? Decodable.Type {
                if let decodedValue = try? container.decodeIfPresent(_type, forKey: key) as? Value {
                    result[typedKey] = decodedValue
                }
            }
            // Value 是 Any 类型 → SmartAnyImpl + Decodable 回退
            else if let decoderImpl = try? container.superDecoder(forKey: key) as? JSONDecoderImpl {
                // 优先 SmartAnyImpl.peel（覆盖最常见场景）
                if let decoded = try? decoderImpl.unwrap(as: SmartAnyImpl.self),
                   let peeled = decoded.peel as? Value {
                    result[typedKey] = peeled
                    continue
                }

                // 回退 Decodable.init(from:)（包含 SmartCodableX）
                if let _type = Value.self as? Decodable.Type,
                   let decoded = try? _type.init(from: decoderImpl) as? Value {
                    result[typedKey] = decoded
                    continue
                }
            }
        }

        self.wrappedValue = result
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: _JSONKey.self)
        for (k, v) in wrappedValue {
            if let key = _JSONKey(stringValue: k.description),
               let _v = v as? Encodable {
                try container.encode(_v, forKey: key)
            }
        }
    }
}
