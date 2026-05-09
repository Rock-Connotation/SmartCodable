//
//  SmartCoding.swift
//  BTCodable
//
//  Created by Mccc on 2023/8/1.
//



/// SmartCodable 全局解码/编码配置命名空间
/// 提供静态配置项来控制 SmartCodable 的行为，类似于 JSONDecoder 的全局策略配置
/// 这些配置项在解码/编码过程中被读取，影响所有使用 SmartCodable 的类型
/// 支持的配置包括数字转换策略、null 值处理等
public struct SmartCodableOptions {
    /// 数字类型转换策略（默认：.strict）
    ///
    /// - 功能：控制将 JSON 数字（如浮点数）转换到目标类型（如整数）时如何处理精度损失
    /// - 作用时机：在解码过程中，当 JSON 值类型与目标属性类型不匹配时（如 JSON 中的 3.14 解码为 Int）
    /// - 示例：将 JSON 中的 3.14 解码为 Int 类型
    ///   - .strict:   返回 nil（不允许精度损失，解码失败）
    ///   - .truncate: 返回 3（直接截断小数部分）
    ///   - .rounded:  返回 3（四舍五入到最近整数）
    ///
    /// - 注意：此配置仅影响解码过程，不影响编码
    /// - 设计意图：提供灵活的容错策略，让开发者根据业务需求选择严格的类型匹配或宽容的自动转换
    public static var numberStrategy: NumberConversionStrategy = .strict


    /// 是否忽略 JSON `null` 值（默认：`true`）
    ///
    /// - 功能：控制 Any 类型属性包装器如何处理 JSON 中的 null 值
    /// - 作用对象：使用 Any 类型或 SmartAny 等属性包装器的属性
    ///
    /// - 行为差异：
    ///   - `true`（默认）：遇到 JSON 字段值为 `null` 时，属性包装器跳过赋值，保持属性的默认值或原有值
    ///     - 适用场景：希望 null 值不影响属性，使用默认值代替
    ///     - 示例：`@SmartAny var name: String = "default"`，JSON 中 `"name": null`，则 name 保持为 "default"
    ///   - `false`：遇到 JSON 字段值为 `null` 时，属性包装器将 NSNull() 或 nil 赋给目标 Any
    ///     - 适用场景：需要在运行时检测字段是否为 null，进行特殊处理
    ///     - 示例：`@SmartAny var data: Any`，JSON 中 `"data": null`，则 data 为 NSNull()，可通过类型判断检测到 null
    ///
    /// - 设计意图：让开发者根据业务需求选择是否在 Any 类型中保留 null 信息
    public static var ignoreNull: Bool = true
}


extension SmartCodableOptions {
    /// 数字类型转换策略枚举
    /// 定义了在解码过程中处理 JSON 数字到目标类型转换时精度损失的三种策略
    /// 此枚举与 SmartCodableOptions.numberStrategy 配合使用，影响所有数字类型的解码行为
    public enum NumberConversionStrategy {
        /// 严格模式：类型必须完全匹配，否则返回 nil（默认）
        ///
        /// - 行为：当 JSON 数字类型与目标类型不匹配时（如浮点数转整数），直接返回 nil，不进行任何转换
        /// - 适用场景：需要严格类型检查的场景，避免因类型不匹配导致的数据精度损失
        /// - 解码示例：Double(3.14) → Int? 返回 nil（不允许精度损失）
        /// - 设计意图：遵循类型安全原则，确保数据完整性
        case strict

        /// 截断模式：直接截断小数部分（如 3.99 → 3）
        ///
        /// - 行为：将浮点数的小数部分直接丢弃，只保留整数部分
        /// - 适用场景：业务上可以接受数据截断，且希望避免解码失败的宽容场景
        /// - 解码示例：Double(3.99) → Int 返回 3（截断小数部分）
        /// - 注意：3.99 → 3 可能导致数据显著偏差，需谨慎使用
        case truncate

        /// 四舍五入模式：四舍五入到最近整数（如 3.5 → 4, 3.4 → 3）
        ///
        /// - 行为：将浮点数四舍五入到最接近的整数（.5 向上取整）
        /// - 适用场景：需要相对精确的近似值转换，但可以接受微小精度损失
        /// - 解码示例：Double(3.6) → Int 返回 4（四舍五入）
        /// - 设计意图：提供比截断更合理的近似转换，减少数据偏差
        case rounded
    }
}
