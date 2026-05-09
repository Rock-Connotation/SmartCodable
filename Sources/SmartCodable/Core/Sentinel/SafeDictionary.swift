//
//  SafeDictionary.swift
//  SmartCodable
//
//  Created by Mccc on 2024/6/5.
//

import Foundation

// MARK: - SafeDictionary 线程安全字典

/// 基于 NSLock 的线程安全字典，作为 LogCache 的底层存储。
///
/// **WHAT**: 对原生 Dictionary 包装 NSLock，提供线程安全的 CRUD + updateEach 批量更新。
/// 泛型 Key: Hashable，Value 无额外约束。
///
/// **WHY**: LogCache 在解码过程中被多个容器并发写入（同一 parsingMark 下不同 codingPath
/// 各自独立创建 LogContainer），需要保证字典操作不出现 data race。选择 NSLock 而非
/// DispatchQueue 串行队列是因为：
/// - NSLock 对于简单 get/set 操作开销更低，无需上下文切换
/// - 所有操作都是 O(1) 的字典读写，不会长时间持锁
/// - defer { lock.unlock() } 保证异常路径也能释放锁
///
/// **HOW**: 每个公开方法都是 lock → 操作 → defer unlock 三段式。
/// updateEach 先把字典拷出，在锁外执行 body 闭包，构建新字典后整体替换 ——
/// 这样 body 内的耗时操作不会阻塞其他线程。
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Diagnostics.md`
class SafeDictionary<Key: Hashable, Value> {
    
    private var dictionary: [Key: Value] = [:]
    
    private let lock = NSLock()
    
    func getValue(forKey key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return dictionary[key]
    }
    
    func setValue(_ value: Value, forKey key: Key) {
        lock.lock()
        defer { lock.unlock() }
        dictionary[key] = value
    }
    
    func removeValue(forKey key: Key) {
        lock.lock()
        defer { lock.unlock() }
        dictionary.removeValue(forKey: key)
    }
    
    /// 新增：按条件批量移除键值对
    func removeValue(where shouldRemove: (Key) -> Bool) {
        lock.lock()
        defer { lock.unlock() }
        dictionary = dictionary.filter { !shouldRemove($0.key) }
    }
    
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        dictionary.removeAll()
    }
    
    func getAllValues() -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        return Array(dictionary.values)
    }
    
    func getAllKeys() -> [Key] {
        lock.lock()
        defer { lock.unlock() }
        return Array(dictionary.keys)
    }
    
    func updateEach(_ body: (Key, inout Value) throws -> Void) rethrows {
        lock.lock()
        defer { lock.unlock() }
        var updatedDictionary: [Key: Value] = [:]
        for (key, var value) in dictionary {
            try body(key, &value)
            updatedDictionary[key] = value
        }
        dictionary = updatedDictionary
    }
}
