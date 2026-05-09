//
//  SmartDataTransformer.swift
//  SmartCodable
//
//  Created by Mccc on 2024/4/29.
//

import Foundation
/// Data 转换器：处理 base64 编解码
/// - WHAT：将 JSON 中的 base64 字符串转换为 Swift Data 类型
/// - HOW：解码时使用 Data(base64Encoded:)，编码时使用 base64EncodedString()
/// - WHY：支持二进制数据（图片、文件）在 JSON 中的传输
public struct SmartDataTransformer: ValueTransformable {

    public typealias JSON = String
    public typealias Object = Data

    public init() {}

    /// 从 JSON 字符串转换为 Data
    /// - WHAT：解码 base64 字符串为二进制数据
    /// - HOW：将值转换为字符串，调用 Data(base64Encoded:) 解码
    /// - WHY：处理 JSON 中存储的二进制数据
    public func transformFromJSON(_ value: Any) -> Data? {
        guard let string = value as? String else {
            return nil
        }
        return Data(base64Encoded: string)
    }

    /// 将 Data 转换为 JSON 字符串
    /// - WHAT：编码二进制数据为 base64 字符串
    /// - HOW：调用 base64EncodedString() 方法
    /// - WHY：将 Data 序列化为 JSON 可接受的字符串格式
    public func transformToJSON(_ value: Data) -> String? {
        return value.base64EncodedString()
    }
}
