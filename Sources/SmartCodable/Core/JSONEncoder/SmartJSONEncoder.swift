

import Foundation

//===----------------------------------------------------------------------===//
// JSON Encoder
//===----------------------------------------------------------------------===//

/// SmartCodable JSON 编码器入口
/// WHAT：继承自 Foundation.JSONEncoder，提供扩展的编码策略
/// HOW：通过 smartKeyEncodingStrategy/smartDataEncodingStrategy 自定义编码行为，内部使用 JSONEncoderImpl 实现编码逻辑
/// WHY：与 SmartJSONDecoder 对称设计，提供一致的编码/解码体验
/// 学习文档：编码器架构章节
open class SmartJSONEncoder: JSONEncoder, @unchecked Sendable {

    /// Key 编码策略：控制如何将 CodingKeys 转换为 JSON 键名
    open var smartKeyEncodingStrategy: SmartKeyEncodingStrategy = .useDefaultKeys
    /// Data 编码策略：控制如何将 Data 编码为 JSON 值
    open var smartDataEncodingStrategy: SmartDataEncodingStrategy = .base64

    /// 编码选项封装
    /// WHAT：统一封装所有编码策略和用户信息
    /// HOW：在编码器创建时构造，沿编码树向下传递
    /// WHY：避免在每个编码点重复传递多个参数，简化编码器 API
    /// 学习文档：编码器选项传递章节
    struct _Options {
        let dateEncodingStrategy: DateEncodingStrategy
        let dataEncodingStrategy: SmartDataEncodingStrategy
        let nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy
        let keyEncodingStrategy: SmartKeyEncodingStrategy
        let userInfo: [CodingUserInfoKey: Any]
    }

    /// 编码选项计算属性
    /// WHAT：从当前编码器实例构造 _Options 对象
    /// HOW：组合 Foundation.JSONEncoder 的默认策略和 SmartCodable 的扩展策略
    /// WHY：为子编码器提供一致的配置入口点
    fileprivate var options: _Options {
        return _Options(dateEncodingStrategy: dateEncodingStrategy,
                        dataEncodingStrategy: smartDataEncodingStrategy,
                        nonConformingFloatEncodingStrategy: nonConformingFloatEncodingStrategy,
                        keyEncodingStrategy: smartKeyEncodingStrategy,
                        userInfo: userInfo)
    }


    // MARK: - Encoding Values

    /// 编码入口方法：将 Encodable 值编码为 JSON Data
    /// WHAT：执行完整编码流程：值 → JSONValue → Foundation 对象 → JSON Data
    /// HOW：1. 使用 encodeAsJSONValue 编码为 JSONValue 树 2. 转换为 Foundation 对象 3. 通过 JSONSerialization 序列化为 Data
    /// WHY：提供与 Foundation.JSONEncoder 兼容的 API，同时支持 SmartCodable 扩展策略
    /// 学习文档：编码流程章节
    open override func encode<T: Encodable>(_ value: T) throws -> Data {
        let jsonValue: JSONValue = try encodeAsJSONValue(value)
        let jsonObject = jsonValue.toFoundation()
        
        do {
            return try JSONSerialization.data(withJSONObject: jsonObject, options: self.outputFormatting.jsonSerializationOptions)
        } catch {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Unable to encode the given top-level value to JSON.", underlyingError: error))
        }
    }
    
    /// 输出格式转换：将 JSONEncoder.OutputFormatting 映射为 JSONSerialization.WritingOptions
    /// WHAT：处理格式化选项的兼容性转换
    /// HOW：逐个检查并映射格式化标志（prettyPrinted、sortedKeys）
    /// WHY：JSONEncoder 和 JSONSerialization 使用不同的枚举类型，需要桥接
    func mapOutputFormatting(_ formatting: JSONEncoder.OutputFormatting) -> JSONSerialization.WritingOptions {
        var options = JSONSerialization.WritingOptions()
        
        if formatting.contains(.prettyPrinted) {
            options.insert(.prettyPrinted)
        }
        if formatting.contains(.sortedKeys) {
            if #available(iOS 11.0, macOS 10.13, *) {
                options.insert(.sortedKeys)
            }
        }
        
        return options
    }

    /// 编码为 JSONValue 树（中间表示）
    /// WHAT：将 Encodable 值编码为内存中的 JSONValue 树结构
    /// HOW：创建 JSONEncoderImpl 实例，调用 wrapEncodable 执行编码
    /// WHY：JSONValue 是与 Foundation 解耦的中间表示，便于测试和转换
    /// 学习文档：中间表示章节
    func encodeAsJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoderImpl(options: self.options, codingPath: [])
        guard let topLevel = try encoder.wrapEncodable(value, for: nil) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Top-level \(T.self) did not encode any values."))
        }

        return topLevel
    }
}

//===----------------------------------------------------------------------===//
// Error Utilities
//===----------------------------------------------------------------------===//

extension EncodingError {
    /// 创建浮点数非法值错误
    /// WHAT：生成描述非法浮点数（infinity、-infinity、nan）的编码错误
    /// HOW：根据浮点数类型和值生成友好的错误描述
    /// WHY：JSON 标准不支持非标准浮点数，需要明确的错误提示引导用户使用转换策略
    fileprivate static func _invalidFloatingPointValue<T: FloatingPoint>(_ value: T, at codingPath: [CodingKey]) -> EncodingError {
        let valueDescription: String
        if value == T.infinity {
            valueDescription = "\(T.self).infinity"
        } else if value == -T.infinity {
            valueDescription = "-\(T.self).infinity"
        } else {
            valueDescription = "\(T.self).nan"
        }

        let debugDescription = "Unable to encode \(valueDescription) directly in JSON. Use SmartJSONEncoder.NonConformingFloatEncodingStrategy.convertToString to specify how the value should be encoded."
        return .invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: debugDescription))
    }
}

extension CodingUserInfoKey {
    /// 用户信息键：控制是否使用映射后的键名
    /// WHAT：在编码器选项中传递，决定是否应用键名映射策略
    /// HOW：编码器检查此键的值来选择键名处理逻辑
    /// WHY：允许运行时动态切换键名映射行为，无需修改编码器实例
    static let useMappedKeys = CodingUserInfoKey.init(rawValue: "Stamrt.useMappedKeys")
}

extension JSONEncoder.OutputFormatting {
    /// 将 JSONEncoder.OutputFormatting 转换为 JSONSerialization.WritingOptions
    /// WHAT：桥接两种格式化枚举类型
    /// HOW：逐个检查格式化选项并插入对应的 JSONSerialization 选项
    /// WHY：复用 Foundation 的序列化功能，同时保持 API 一致性
    var jsonSerializationOptions: JSONSerialization.WritingOptions {
        var options: JSONSerialization.WritingOptions = []
        if contains(.prettyPrinted) {
            options.insert(.prettyPrinted)
        }
        if self.contains(.sortedKeys) {
            if #available(iOS 11.0, macOS 10.13, *) {
                options.insert(.sortedKeys)
            }
        }
        return options
    }
}
