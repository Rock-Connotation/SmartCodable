//
//  SmartCompact.swift
//  SmartCodable
//
//  Created by Mccc on 2026/1/21.
//



// MARK: - DummyDecodable 游标推进器

/// 空 Decodable 模型，任何 JSON 值都能成功解码。
/// 作用：在 SmartCompact.Array 解码失败时强制推进 unkeyedContainer 的 currentIndex，
/// 避免游标卡在原位导致无限循环。
private struct DummyDecodable: Decodable { }

// MARK: - SmartCompact.Array

extension SmartCompact {
    /// 容错数组包装器：遍历 unkeyedContainer，跳过无法解析的元素。
    ///
    /// **WHY**: 不走 PropertyWrapperable 通道，原因有三：
    /// 1. 解码逻辑完全不同（游标循环 vs 取值包装）
    /// 2. 集合元素是具体类型，不需要 didFinishMapping 穿透
    /// 3. 编码需要重新处理集合序列化
    /// 行为简单比形式统一更重要。
    ///
    /// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Property-Wrappers.md`
    @propertyWrapper
    public struct Array<T> {
        
        public var wrappedValue: [T]
        
        public init(wrappedValue: [T]) {
            self.wrappedValue = wrappedValue
        }
    }
}

extension SmartCompact.Array: Codable {
    /// 容错数组解码：遍历 unkeyedContainer，逐个尝试解码元素。
    /// SmartCodableX 模型走 container.decode(type)，普通类型走 SmartAnyImpl.peel。
    /// 解码失败时 DummyDecodable 推进游标，防止无限循环。
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [T] = []

        // 生成 decode 闭包：根据元素类型走不同路径
        let decodeValue: () -> Any? = {
            if T.self is SmartCodableX.Type,
               let type = T.self as? Decodable.Type {
                return try? container.decode(type)
            } else {
                return try? container.decode(SmartAnyImpl.self).peel
            }
        }

        // 游标循环
        while !container.isAtEnd {
            let startIndex = container.currentIndex
            defer {
                // 游标未推进 → DummyDecodable 强制推进
                if container.currentIndex == startIndex {
                    _ = try? container.decode(DummyDecodable.self)
                }
            }

            if let value = decodeValue(), let v = value as? T {
                result.append(v)
            }
        }

        self.wrappedValue = result
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for value in wrappedValue {
            try container.encode(SmartAnyImpl(from: value))
        }
    }
}
