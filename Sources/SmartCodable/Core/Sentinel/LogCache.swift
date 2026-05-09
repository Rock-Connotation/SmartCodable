//
//  LogCache.swift
//  SmartCodable
//
//  Created by Mccc on 2024/4/23.
//

import Foundation

// MARK: - LogCache 日志缓存

/// 按 parsingMark 聚合一次解析的所有日志，在解析结束时统一格式化输出。
///
/// **WHAT**: 提供 save / formatLogs / clearCache 三个核心操作。
/// 底层使用 SafeDictionary<String, LogContainer>，key 为 `parsingMark + codingPath`。
///
/// **HOW (formatLogs 管线)**:
/// 1. filterLogItem — 去重（unkeyed 容器的 Index X 日志去重）
/// 2. alignTypeNamesInAllSnapshots — 字段名对齐到最大长度
/// 3. sortKeys — 按 key 字母序排列保证输出一致
/// 4. 遍历 → LogContainer.formatMessage → 拼接
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Diagnostics.md`
struct LogCache {
    
    private var snapshotDict = SafeDictionary<String, LogContainer>()
    
    /// 保存解码错误：DecodingError → LogItem → cacheLog
    mutating func save(error: DecodingError, className: String, parsingMark: String) {
        let log = LogItem.make(with: error)
        cacheLog(log, className: className, parsingMark: parsingMark)
    }

    /// 按 parsingMark 前缀清理缓存，解析完成后调用，防止内存泄漏
    mutating func clearCache(parsingMark: String) {
        snapshotDict.removeValue { $0.hasPrefix(parsingMark) }
    }

    /// 格式化输出：去重 → 对齐字段名 → 排序 → 拼接。返回 nil 表示无日志。
    mutating func formatLogs(parsingMark: String) -> String? {
        
        filterLogItem()
        
        alignTypeNamesInAllSnapshots(parsingMark: parsingMark)
        
        let keyOrder = sortKeys(snapshotDict.getAllKeys(), parsingMark: parsingMark)
        
        var lastPath: String = ""
        let arr = keyOrder.compactMap {
            let container = snapshotDict.getValue(forKey: $0)
            let message = container?.formatMessage(previousPath: lastPath)
            lastPath = container?.path ?? ""
            return message
        }
        
        if arr.isEmpty { return nil }
        return arr.joined()
    }
}

extension LogCache {
    
    /// 按 parsingMark 前缀筛选 + 字母序排序，保证输出一致性
    func sortKeys(_ array: [String], parsingMark: String) -> [String] {
        //  获取当前解析的keys
        let filterArray = array.filter {
            $0.starts(with: parsingMark)
        }
        guard !filterArray.isEmpty else { return [] }
        
        let sortedArray = filterArray.sorted()
        return sortedArray
    }
    
    /// 去重 unkeyed 容器（Index X）中的重复日志
    mutating func filterLogItem() {
        let pattern = "Index \\d+"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        var matchedKeys = snapshotDict.getAllKeys().filter { key in
            let range = NSRange(key.startIndex..<key.endIndex, in: key)
            return regex.firstMatch(in: key, options: [], range: range) != nil
        }
        
        matchedKeys = matchedKeys.sorted(by: < )
        
        var allLogs: [LogItem] = []
        
        let tempDict = snapshotDict
        for key in matchedKeys {
            var lessLogs: [LogItem] = []
            if var snap = snapshotDict.getValue(forKey: key) {
                let logs = snap.logs
                for log in logs {
                    if !allLogs.contains(where: { $0 == log }) {
                        lessLogs.append(log)
                        allLogs.append(log)
                    }
                }
                
                if lessLogs.isEmpty {
                    tempDict.removeValue(forKey: key)
                } else {
                    snap.logs = lessLogs
                    tempDict.setValue(snap, forKey: key)
                }
            }
        }
        snapshotDict = tempDict
    }
    
    /// 缓存单条日志。同 key 合并 logs，新 key 创建 LogContainer。
    private mutating func cacheLog(_ log: LogItem?, className: String, parsingMark: String) {
        
        guard let log = log else { return }
        
        let path = log.codingPath
        let key = createKey(path: path, parsingMark: parsingMark)
        
        // 如果存在相同的typeName和path，则合并logs
        if var existingSnapshot = snapshotDict.getValue(forKey: key) {
            if !existingSnapshot.logs.contains(where: { $0 == log }) {
                existingSnapshot.logs.append(log)
                snapshotDict.setValue(existingSnapshot, forKey: key)
            }
        } else {
            // 创建新的snapshot并添加到字典中
            let newSnapshot = LogContainer(typeName: className, codingPath: path, logs: [log], parsingMark: parsingMark)
            snapshotDict.setValue(newSnapshot, forKey: key)
        }
    }
    
    /// key = parsingMark + codingPath 各段用 "-" 连接，保证同路径日志归入同一容器
    private func createKey(path: [CodingKey], parsingMark: String) -> String {
        let arr = path.map { $0.stringValue }
        return parsingMark + "\(arr.joined(separator: "-"))"
    }
    
    /// 字段名对齐到每个容器内最大长度，保证 `: ` 冒号对齐
    private mutating func alignTypeNamesInAllSnapshots(parsingMark: String) {
        snapshotDict.updateEach { key, snapshot in
            let maxLength = snapshot.logs.max(by: { $0.fieldName.count < $1.fieldName.count })?.fieldName.count ?? 0
            snapshot.logs = snapshot.logs.map { log in
                var modifiedLog = log
                modifiedLog.fieldName = modifiedLog.fieldName.padding(toLength: maxLength, withPad: " ", startingAt: 0)
                return modifiedLog
            }
        }
    }
}




