//
//  Cachable.swift
//  SmartCodable
//
//  Created by Mccc on 2024/6/3.
//

import Foundation

// MARK: - Cachable 缓存协议

/// 解码/编码过程中维护模型快照栈的缓存协议。
///
/// **WHAT**: 定义 snapshots 数组（解码栈）和 cacheSnapshot / removeSnapshot 操作。
/// 每个模型进入解码时 push 快照，退出时 pop，形成与 codingPath 对应的快照栈。
///
/// **WHY**: 解码过程中需要跨容器共享状态：
/// - 属性包装器（SmartAny、SmartHexColor 等）需要从快照中取回 encode 时缓存的初始值
/// - 延迟初始化的属性需要知道自己在哪一层模型中被解码（通过 findSnapShot 匹配 codingPath）
/// - transformers 按模型实例存储，解码时需要从快照中查找当前模型注册的转换器
/// 使用数组而非单值是因为嵌套解码（模型 A 包含模型 B）会形成多层快照，
/// findSnapShot 从栈顶向下查找，自动匹配最近的嵌套层级。
///
/// **HOW**: JSONDecoderImpl / JSONEncoderImpl 遵循此协议。
/// cacheSnapshot 在 decode 开始前调用，removeSnapshot 在 decode 结束后调用。
/// findSnapShot 用 last(where:) 从栈顶向下匹配 codingPath。
///
/// - SeeAlso: `Document/SmartCodable-Learning/02-SmartCodable-Core/Decoding-Pipeline.md`
protocol Cachable {
            
    associatedtype SomeSnapshot: Snapshot

    /// Array of snapshots representing the current parsing stack
    /// - Note: Using an array prevents confusion with multi-level nested models
    var snapshots: [SomeSnapshot] { set get }

    
    /// 为指定类型在给定解码路径上创建快照，push 到 snapshots 栈顶。
    /// 后续通过 findSnapShot 按 codingPath 精确匹配查找。
    func cacheSnapshot<T>(for type: T.Type, codingPath: [CodingKey])

    /// 移除指定类型的快照（pop），解码完成时调用。
    mutating func removeSnapshot<T>(for type: T.Type)
}


extension Cachable {
    
    /// 根据解码路径查找对应的快照容器。
    ///
    /// 该方法用于在内部缓存的快照列表中，查找与传入 `codingPath` 精确匹配的 `DecodingSnapshot`。
    /// 快照用于缓存某一解码路径下的初始值或上下文信息，便于后续访问或懒加载。
    ///
    /// - Parameter codingPath: 当前字段或容器所在的完整解码路径。
    /// - Returns: 匹配路径的快照对象，若不存在则返回 `nil`。
    func findSnapShot(with codingPath: [CodingKey]) -> SomeSnapshot? {
        return snapshots.last { codingPathEquals($0.codingPath, codingPath) }
    }
    
    private func codingPathEquals(_ lhs: [CodingKey], _ rhs: [CodingKey]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs, rhs) {
            if l.stringValue != r.stringValue || l.intValue != r.intValue {
                return false
            }
        }
        return true
    }
}


/// 编解码过程中单个模型的快照，记录类型、路径、转换器等上下文信息。
/// JSONDecoderImpl.DecodingSnapshot 和 JSONEncoderImpl.EncodingSnapshot 均遵循此协议。
protocol Snapshot {
    
    associatedtype ObjectType
    
    /// The current type being encoded/decoded
    var objectType: ObjectType? { set get }

    var codingPath: [CodingKey] { get set }
    
    /// String representation of the object type
    var objectTypeName: String? { get }
    
    /// Records the custom transformer for properties
    var transformers: [SmartValueTransformer]? { set get }
}

extension Snapshot {
    var objectTypeName: String? {
        if let t = objectType {
            return String(describing: t)
        }
        return nil
    }
}
