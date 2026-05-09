//
//  KeysMapper.swift
//  SmartCodable
//
//  Created by Mccc on 2024/5/27.
//

import Foundation

/// JSON键映射器 - 解码时将JSON字段名映射到模型属性名
/// 核心逻辑：调用模型的mappingForKey()获取映射规则，然后批量重命名字典键
struct KeysMapper {

    /// 解码阶段：根据模型的键映射规则转换JSON值
    /// - 字符串：解析为JSON对象后应用映射（处理JSON字符串场景）
    /// - 字典：直接调用mapDictionary重命名键
    /// - 非SmartDecodable类型：跳过映射（性能优化，避免无效计算）
    static func convertFrom(_ jsonValue: JSONValue, type: Any.Type) -> JSONValue? {

        // 类型不是SmartDecodable，无需键重命名
        guard let type = type as? SmartDecodable.Type else { return jsonValue }
        
        switch jsonValue {
        case .string(let stringValue):
            // 字符串可能包含JSON，先解析再映射（处理JSON字符串场景）
            if let value = parseJSON(from: stringValue, as: type) {
                return JSONValue.make(value)
            }

        case .object(let dictValue):
            // 字典：直接应用映射规则重命名键
            if let dict = mapDictionary(dict: dictValue, using: type) as? [String: JSONValue] {
                return JSONValue.object(dict)
            }
            
        default:
            break
        }
        return nil
    }
    
    /// 解析JSON字符串并应用键映射（用于字符串类型字段）
    private static func parseJSON(from string: String, as type: SmartDecodable.Type) -> Any? {
        guard let jsonObject = string.toJSONObject() else { return string }
        if let dict = jsonObject as? [String: Any] {
            // 字典类型：应用键映射
            return mapDictionary(dict: dict, using: type)
        } else {
            // 数组/其他类型：直接返回
            return jsonObject
        }
    }

    /// 应用键映射规则到字典（核心映射逻辑）
    /// 1. 干扰字段移除：旧键≠新键时，删除新键防止旧数据污染
    /// 2. 优先字段机制：mapping.from数组中第一个非空值命中后break（避免覆盖）
    /// 3. 跨层级路径支持：通过keyPath访问嵌套值（如"user.contact.email"）
    private static func mapDictionary(dict: [String: Any], using type: SmartDecodable.Type) -> [String: Any]? {

        guard let mappings = type.mappingForKey(), !mappings.isEmpty else { return nil }
        
        var newDict = dict
        mappings.forEach { mapping in
            let newKey = mapping.to.stringValue

            // 干扰字段移除：如果旧键数组不包含新键名，说明新键可能被旧数据污染，先删除
            // 场景：CodingKeys.name <--- ["newName"]（旧键不存在，新键会被旧数据覆盖）
            if !(mapping.from.contains(newKey)) {
                newDict.removeValue(forKey: newKey)
            }

            // 优先字段机制：from数组中第一个非空值命中后break（避免覆盖）
            for oldKey in mapping.from {
                // 当前层级直接命中
                if let value = dict[oldKey] as? JSONValue, value != .null {
                    newDict[newKey] = value
                    break
                }

                // 跨层级路径处理（通过keyPath访问嵌套值，如"user.contact.email"）
                if let pathValue = dict.getValue(forKeyPath: oldKey) {
                    newDict.updateValue(pathValue, forKey: newKey)
                    break
                }
            }
        }
        return newDict
    }
}



extension Dictionary {

    /// 根据点分隔路径从字典中提取嵌套值（支持跨层级键映射）
    /// 示例：dict.getValue(forKeyPath: "inDict.name") → dict["inDict"]["name"]
    /// 返回nil：路径不存在、中间层不是字典、键不存在
    fileprivate func getValue(forKeyPath keyPath: String) -> Any? {
        guard keyPath.contains(".") else { return nil }
        let keys = keyPath.components(separatedBy: ".")
        var currentAny: Any = self
        for key in keys {
            if let currentDict = currentAny as? [String: Any] {
                if let value = currentDict[key] {
                    currentAny = value
                } else {
                    return nil
                }
            } else if case JSONValue.object(let object) = currentAny, let temp = object[key] {
                currentAny = temp
            } else {
                return nil
            }
        }
        return currentAny
    }
}



extension String {
    /// 将JSON字符串转换为Any类型（用于处理JSON字符串字段）
    func toJSONObject() -> Any? {
        return data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }
}
