//
//  SmartDecodingError.swift
//  SmartCodable
//
//  Created by Mccc on 2024/2/27.
//

import Foundation



extension DecodingError {
    /// 便捷方法：构造键未找到错误（用于KeyedContainer）
    static func _keyNotFound(key: CodingKey, codingPath: [CodingKey]) -> DecodingError {
        DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "No value associated with key \(key)."))
    }

    /// 便捷方法：构造值未找到错误（用于null值）
    static func _valueNotFound(key: CodingKey, expectation: Any.Type, codingPath: [CodingKey]) -> DecodingError {
        DecodingError.valueNotFound(expectation, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode '\(expectation)' but found 'null' instead."))
    }

    /// 便捷方法：构造类型不匹配错误
    static func _typeMismatch(at path: [CodingKey], expectation: Any.Type, desc: String) -> DecodingError {
        let description = "Expected to decode '\(expectation)' but found \(desc) instead."
        return .typeMismatch(expectation, Context(codingPath: path, debugDescription: description))
    }


    /// 获取值的类型描述（用于错误消息）
    private static func _typeDescription(of value: Any?) -> String {
        if value is NSNull {
            return "a null value"
        } else if value is NSNumber /* FIXME: If swift-corelibs-foundation isn't updated to use NSNumber, this check will be necessary: || value is Int || value is Double */ {
            return "a number"
        } else if value is String {
            return "a string/data"
        } else if value is [Any] {
            return "an array"
        } else if value is [String : Any] {
            return "a dictionary"
        } else {
            return "\(type(of: value))"
        }
    }
}
