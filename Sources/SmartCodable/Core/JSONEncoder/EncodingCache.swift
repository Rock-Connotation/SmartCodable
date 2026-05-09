//
//  EncodingCache.swift
//  SmartCodable
//
//  Created by Mccc on 2024/6/3.
//

import Foundation


/// 编码缓存：缓存编码过程中的类型信息和转换器，避免重复查找
/// 与 DecodingCache 对称，提供编码端的类型转换支持
/// 学习文档：编码器架构 - 编码缓存机制
class EncodingCache: Cachable {
    typealias SomeSnapshot = EncodingSnapshot

    /// 快照栈，用于嵌套编码场景（如嵌套模型）
    /// 后进先出，匹配编码器的调用栈
    var snapshots: [EncodingSnapshot] = []
    
    /// 为 SmartEncodable 类型创建编码快照
    /// 快照包含：类型信息、编码路径、值转换器
    /// 支持嵌套编码时查找正确的转换器
    /// 学习文档：编码器架构 - 类型快照管理
    func cacheSnapshot<T>(for type: T.Type, codingPath: [CodingKey]) {
        if let object = type as? SmartEncodable.Type {
            
            var snapshot = EncodingSnapshot()
            snapshot.objectType = object
            snapshot.codingPath = codingPath
            snapshot.transformers = object.mappingForValue()
            snapshots.append(snapshot)
        }
    }
    
    /// 移除最新快照（栈式管理）
    /// 嵌套编码完成后弹出对应快照，避免污染上层编码上下文
    /// 与 cacheSnapshot 配对使用，保证快照栈正确性
    /// 学习文档：编码器架构 - 快照生命周期
    func removeSnapshot<T>(for type: T.Type) {
        if let _ = T.self as? SmartEncodable.Type {
            if snapshots.count > 0 {
                snapshots.removeLast()
            }
        }
    }
}


extension EncodingCache {
    /// 查找指定键对应的值转换器
    /// 支持直接匹配和键名映射匹配（mappingForKey）
    /// 优化：提前解析键名映射到 Set，避免每次遍历重新计算
    /// 学习文档：值转换器 - 转换器查找机制
    func valueTransformer(for key: CodingKey?, in containerPath: [CodingKey]) -> SmartValueTransformer? {
        guard let lastKey = key else { return nil }
        
        guard let snapshot = findSnapShot(with: containerPath) else { return nil }
        
        guard let transformers = snapshot.transformers, !transformers.isEmpty else { return nil }
        
        
        // 提前解析 key 映射（避免每次遍历 transformer 都重新计算）
        let keyMappings: Set<String> = {
            guard let mappings = snapshot.objectType?.mappingForKey() else { return [] }
            return Set(mappings.flatMap { $0.from })
        }()
        
        let transformer = transformers.first(where: { transformer in
            transformer.location.stringValue == lastKey.stringValue
            || keyMappings.contains(lastKey.stringValue)
        })

        return transformer
    }
}


extension EncodingCache {

    /// 使用转换器将值转换为 JSON
    /// 支持直接匹配和键名映射匹配
    /// 转换失败返回 nil，让编码器使用默认 Codable 逻辑
    /// 学习文档：值转换器 - 编码端转换流程
    func tranform(from value: Any, with key: CodingKey?, codingPath: [CodingKey]) -> JSONValue? {
        
        guard let top = findSnapShot(with: codingPath), let key = key else { return nil }
        
        // 查找对应的值转换器（支持键名映射）
        let wantKey = key.stringValue
        let targetTran = top.transformers?.first(where: { transformer in
            if wantKey == transformer.location.stringValue {
                return true
            } else {
                if let keyTransformers = top.objectType?.mappingForKey() {
                    for keyTransformer in keyTransformers {
                        if keyTransformer.from.contains(wantKey) {
                            return true
                        }
                    }
                }
                return false
            }
        })
        
        if let tran = targetTran, let decoded = transform(decodedValue: value, performer: tran.performer) {
            return JSONValue.make(decoded)
        }
        
        return nil
    }
    
    /// 执行实际的值转换
    /// 区分属性包装器（@SmartAny 等）和普通值的转换逻辑
    /// 调用转换器的 transformToJSON 方法
    /// 学习文档：属性包装器 - 包装器值提取
    private func transform<Performer: ValueTransformable>(decodedValue: Any, performer: Performer) -> Any? {
        // 首先检查是否是属性包装器（需要提取 wrappedValue）
        if let propertyWrapper = decodedValue as? any PropertyWrapperable {
            let wrappedValue = propertyWrapper.wrappedValue
            guard let value = wrappedValue as? Performer.Object else {
                return nil
            }
            return performer.transformToJSON(value)
        } else {
            guard let value = decodedValue as? Performer.Object else { return nil }
            return performer.transformToJSON(value)
        }
    }
}




/// 编码快照：记录单个模型的编码状态
/// 与 DecodingSnapshot 对称，提供编码端的类型上下文
/// 学习文档：编码器架构 - 快照结构
struct EncodingSnapshot: Snapshot {
    /// 模型类型（用于调用 mappingForValue 和 mappingForKey）
    var objectType: (any SmartEncodable.Type)?

    typealias ObjectType = SmartEncodable.Type

    /// 编码路径（用于嵌套编码时查找正确的快照）
    var codingPath: [any CodingKey] = []

    /// 值转换器列表（从 mappingForValue 获取）
    var transformers: [SmartValueTransformer]?
}


