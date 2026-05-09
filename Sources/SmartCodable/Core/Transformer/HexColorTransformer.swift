//
//  HexColorTransformer.swift
//  SmartCodable
//
//  Created by Mccc on 2025/7/23.
//

import Foundation
import Foundation

/// 十六进制颜色转换器：支持 "#RRGGBB" / "#RRGGBBAA" 格式
/// - WHAT：将 JSON 中的十六进制颜色字符串转换为 ColorObject
/// - HOW：通过 SmartHexColor 工具类解析/生成十六进制字符串
/// - WHY：与 SmartHexColor 属性包装器配合使用，简化颜色值处理
public struct SmartHexColorTransformer: ValueTransformable {

    public typealias Object = ColorObject
    public typealias JSON = String

    let colorFormat : SmartHexColor.HexFormat
    public init(colorFormat: SmartHexColor.HexFormat) {
        self.colorFormat = colorFormat
    }
    /// 从 JSON 字符串转换为 ColorObject
    /// - WHAT：解析十六进制颜色字符串
    /// - HOW：委托 SmartHexColor.toColor() 根据格式解析
    /// - WHY：支持 RGB 和 RGBA 两种格式，满足不同需求
    public func transformFromJSON(_ value: Any) -> ColorObject? {
        if let colorStr = value as? String {
            return SmartHexColor.toColor(from: colorStr, format: colorFormat)
        }
        return nil
    }

    /// 将 ColorObject 转换为 JSON 字符串
    /// - WHAT：序列化颜色为十六进制字符串
    /// - HOW：委托 SmartHexColor.toHexString() 根据格式生成
    /// - WHY：保持编码格式与解码格式一致
    public func transformToJSON(_ value: ColorObject) -> String? {
        SmartHexColor.toHexString(from: value, format: colorFormat)
    }
}
