//
//  Cachable.swift
//  SmartCodable
//
//  Created by Mccc on 2024/6/3.
//

import Foundation

/// JSON 提取器：解码 pipeline 最前端的看门人
/// 职责：归一化输入格式 + 按指定路径提取 JSON 子节点
/// 参见 Decoding-Pipeline.md §2
struct JSONExtractor {

    private init() { }

    /// 从各种输入格式提取 JSON 数据，支持路径导航
    /// - Parameters:
    ///   - input: 输入数据（Data/String/Dict/Array）
    ///   - designatedPath: 点分隔路径（如 "data.items.0"）
    ///   - modelType: 目标类型（用于日志记录）
    /// - Returns: 归一化后的 Foundation 对象，失败返回 nil
    static func extract(from input: Any?, by designatedPath: String?, on modelType: Any.Type) -> Any? {
        
        guard let input = input else {
            logNilValue(for: "\(type(of: input))", on: modelType)
            return nil
        }
        
        if let path = designatedPath, !path.isEmpty {
            let obj = toObject(input)
            if let inner = getInnerObject(inside: obj, by: path) {
                return inner
            } else {
                logDataExtractionFailure(forPath: designatedPath, type: Self.self)
                return nil
            }
        } else {
            return input
        }
    }

    /// 将各种输入格式统一转换为 Foundation 对象
    /// - Data: JSON 反序列化
    /// - String: UTF8 编码后按 JSON 反序列化
    /// - Dict/Array: 直接返回
    private static func toObject(_ value: Any?) -> Any? {

        switch value {
        case let data as Data:
            return data.toObject()
        case let json as String:
            return Data(json.utf8).toObject()
        case let dict as [String: Any]:
            return dict
        case let arr as [Any]:
            return arr
        default:
            return nil
        }
    }

    /// 按点分隔路径逐层提取嵌套字典值
    /// - 路径按 "." 拆分（如 "data.items.0"）
    /// - 每层必须是字典类型，否则返回 nil
    /// - 路径不存在或中间节点非字典时返回 nil
    private static func getInnerObject(inside object: Any?, by designatedPath: String?) -> Any? {

        var result: Any? = object
        var abort = false
        if let paths = designatedPath?.components(separatedBy: "."), paths.count > 0 {
            var next = object as? [String: Any]
            paths.forEach({ (seg) in
                if seg.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == "" || abort {
                    return
                }
                if let _next = next?[seg] {
                    result = _next
                    next = _next as? [String: Any]
                } else {
                    abort = true
                }
            })
        }
        return abort ? nil : result
    }
}


extension Data {
    /// 将 JSON Data 反序列化为 Foundation 对象
    /// 使用 .allowFragments 允许顶层是非容器类型（如纯数字/字符串）
    fileprivate func toObject() -> Any? {
        let jsonObject = try? JSONSerialization.jsonObject(with: self, options: .allowFragments)
        return jsonObject
    }
    
    
    /// 将Plist Data 转成 JSON Data
    func tranformToJSONData(type: Any.Type) -> Any? {
        
        guard let jsonObject = try? PropertyListSerialization.propertyList(from: self, options: [], format: nil) else {
            SmartSentinel.monitorAndPrint(debugDescription: "Failed to convert PropertyList Data to JSON Data.", in: type)
            return nil
        }
        
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            SmartSentinel.monitorAndPrint(debugDescription: "Failed to convert PropertyList Data to JSON Data.", in: type)
            return nil
        }
        
        return jsonObject
    }
}


extension Array {
    fileprivate func toData() -> Data? {
        guard JSONSerialization.isValidJSONObject(self) else { return nil }
        return try? JSONSerialization.data(withJSONObject: self)
    }
}


extension Dictionary where Key == String, Value == Any {
    
    /// 将字典序列化为 JSON Data，处理不兼容类型（如 Data 转 base64）
    func toData() -> Data? {
        let jsonCompatibleDict = self.toJSONCompatibleDict()
        guard JSONSerialization.isValidJSONObject(jsonCompatibleDict) else { return nil }
        return try? JSONSerialization.data(withJSONObject: jsonCompatibleDict)
    }

    /// 递归转换字典为 JSON 兼容格式
    private func toJSONCompatibleDict() -> [String: Any] {
        var jsonCompatibleDict: [String: Any] = [:]
        for (key, value) in self {
            jsonCompatibleDict[key] = convertToJSONCompatible(value: value)
        }
        return jsonCompatibleDict
    }
    
    /// 递归处理不兼容 JSON 的类型
    /// 递归处理不兼容 JSON 的类型
    /// - Data: 转为 base64 字符串
    /// - Dict/Array: 递归转换
    private func convertToJSONCompatible(value: Any) -> Any {
        if let data = value as? Data {
            return data.base64EncodedString()
        } else if let dict = value as? [String: Any] {
            return dict.toJSONCompatibleDict()
        } else if let array = value as? [Any] {
            return array.map { convertToJSONCompatible(value: $0) }
        } else {
            return value
        }
    }
}

/// 日志：记录 nil 输入
fileprivate func logNilValue(for valueType: String, on modelType: Any.Type) {
    SmartSentinel.monitorAndPrint(debugDescription: "Decoding \(modelType) failed because input \(valueType) is nil.", in: modelType)
}


/// 日志：记录路径提取失败
fileprivate func logDataExtractionFailure(forPath path: String?, type: Any.Type) {
    
    SmartSentinel.monitorAndPrint(debugDescription: "Decoding \(type) failed because it was unable to extract valid data from path '\(path ?? "nil")'.", in: type)
}
