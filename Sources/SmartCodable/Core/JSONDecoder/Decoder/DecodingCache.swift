//
//  DecodingCache.swift
//  SmartCodable
//
//  Created by Mccc on 2024/3/5.
//

import Foundation


/// 解码缓存 - 为解码操作提供默认值和值转换器
/// 核心优化：使用DecodingSnapshot栈管理嵌套解码状态，延迟初始化避免不必要的Mirror反射
class DecodingCache: Cachable {

    typealias SomeSnapshot = DecodingSnapshot

    /// 解码快照栈（支持嵌套解码，如数组中的对象）
    var snapshots: [DecodingSnapshot] = []

    /// 为SmartDecodable类型创建并存储初始值快照（解码开始时调用）
    /// 缓存条件：
    /// 1. 类型直接是SmartDecodable
    /// 2. 类型是属性包装器，且wrappedValue是SmartDecodable
    /// 3. 其他类型不缓存（性能优化）
    func cacheSnapshot<T>(for type: T.Type, codingPath: [CodingKey]) {



        let smartType: SmartDecodable.Type?

        // 缓存条件判断
        // - 直接实现SmartDecodable：直接缓存
        // - 属性包装器场景：缓存其wrappedValue类型（用于@SmartAny等）
        // - 其他类型：跳过缓存
        if let objectType = type as? SmartDecodable.Type {
            smartType = objectType
        } else if let wrapperType = type as? any PropertyWrapperable.Type {
            smartType = wrapperType.wrappedSmartDecodableType
        } else {
            return
        }

        guard let object = smartType else { return }

        let snapshot = DecodingSnapshot()
        snapshot.codingPath = codingPath
        // 延迟初始化优化：仅在首次访问时通过Mirror反射生成初始值
        snapshot.objectType = object
        snapshots.append(snapshot)
    }

    /// 移除最近的快照（解码完成后调用，保持栈平衡）
    func removeSnapshot<T>(for type: T.Type) {
        guard T.self is SmartDecodable.Type else { return }
        if !snapshots.isEmpty {
            snapshots.removeLast()
        }
    }
}

// MARK: - 获取属性初始值
extension DecodingCache {
    /// 查找指定解码路径下容器中某个字段的初始值
    /// - 根据codingPath查找匹配的快照
    /// - 延迟初始化：仅在首次访问时通过Mirror反射生成初始值
    /// - 支持属性包装器场景（底层存储名是"_" + 属性名）
    func initialValueIfPresent<T>(forKey key: CodingKey?, codingPath: [CodingKey]) -> T? {
                
        guard let key = key else { return nil }

        // 查找匹配当前路径的快照
        guard let snapshot = findSnapShot(with: codingPath) else { return nil }

        // 延迟初始化优化：仅在首次访问时通过Mirror反射生成初始值
        if snapshot.initialValues.isEmpty {
            populateInitialValues(snapshot: snapshot)
        }

        guard let cacheValue = snapshot.initialValues[key.stringValue] else {
            // 处理属性包装器场景（底层存储名是"_" + 属性名）
            return handlePropertyWrapperCases(for: key, snapshot: snapshot)
        }

        if let value = cacheValue as? T {
            return value
        } else if let caseValue = cacheValue as? any SmartCaseDefaultable {
            return caseValue.rawValue as? T
        }

        return nil
    }

    func initialValue<T>(forKey key: CodingKey?, codingPath: [CodingKey]) throws -> T {
        guard let value: T = initialValueIfPresent(forKey: key, codingPath: codingPath) else {
            return try Patcher<T>.defaultForType()
        }
        return value
    }
}


// MARK: - 获取属性对应的值转换器
extension DecodingCache {

    /// 根据属性key和容器路径查找值转换器（SmartValueTransformer）
    /// - 依赖快照中缓存的transformers列表（来自mappingForValue()）
    /// - 容器路径匹配（codingPath）
    /// - 匹配逻辑：基于key.stringValue查找
    func valueTransformer(for key: CodingKey?, in containerPath: [CodingKey]) -> SmartValueTransformer? {
        guard let lastKey = key else { return nil }

        guard let snapshot = findSnapShot(with: containerPath) else { return nil }

        // 转换器仅初始化一次（性能优化）
        if snapshot.transformers?.isEmpty ?? true {
            return nil
        }

        let transformer = snapshot.transformers?.first(where: {
            $0.location.stringValue == lastKey.stringValue
        })
        return transformer
    }
}

extension DecodingCache {


    /// 处理属性包装器场景（底层存储名是"_" + 属性名）
    private func handlePropertyWrapperCases<T>(for key: CodingKey, snapshot: DecodingSnapshot) -> T? {
        if let cached = snapshot.initialValues["_" + key.stringValue] {
            return extractWrappedValue(from: cached)
        }

        return snapshots.reversed().lazy.compactMap {
            $0.initialValues["_" + key.stringValue]
        }.first.flatMap(extractWrappedValue)
    }

    /// 从属性包装器类型中提取wrappedValue
    private func extractWrappedValue<T>(from value: Any) -> T? {
        if let wrapper = value as? SmartIgnored<T> {
            return wrapper.wrappedValue
        } else if let wrapper = value as? SmartAny<T> {
            return wrapper.wrappedValue
        } else if let value = value as? T {
            return value
        }
        return nil
    }

    /// 通过Mirror反射捕获初始值（延迟初始化）
    private func populateInitialValues(snapshot: DecodingSnapshot) {
        guard let type = snapshot.objectType else { return }

        // 递归捕获类型及其父类的初始值
        func captureInitialValues(from mirror: Mirror) {
            mirror.children.forEach { child in
                if let key = child.label {
                    snapshot.initialValues[key] = child.value
                }
            }
            if let superclassMirror = mirror.superclassMirror {
                captureInitialValues(from: superclassMirror)
            }
        }

        let mirror = Mirror(reflecting: type.init())
        captureInitialValues(from: mirror)
    }
}



/// 解码快照 - 记录单个模型的解码状态
class DecodingSnapshot: Snapshot {

    typealias ObjectType = SmartDecodable.Type

    var objectType: (any SmartDecodable.Type)?

    var codingPath: [any CodingKey] = []

    lazy var transformers: [SmartValueTransformer]? = {
        objectType?.mappingForValue()
    }()

    /// 属性初始值字典（延迟初始化）
    var initialValues: [String : Any] = [:]
}
