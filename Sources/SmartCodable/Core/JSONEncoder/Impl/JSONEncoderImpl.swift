
import Foundation

/// Encoder 协议的具体实现
/// WHAT：实现 Foundation.Encoder 协议，管理编码状态和存储
/// HOW：持有 storage 栈结构、编码选项、编码路径，创建各类编码容器
/// WHY：提供与 Foundation 兼容的编码接口，同时支持 SmartCodable 扩展策略
/// 学习文档：编码器实现章节
class JSONEncoderImpl {
    /// 编码选项：包含日期、数据、浮点数、键名等策略
    let options: SmartJSONEncoder._Options
    /// 编码路径：记录当前编码位置的 CodingKey 栈
    let codingPath: [CodingKey]
    /// 用户信息：编码器自定义数据透传
    var userInfo: [CodingUserInfoKey: Any] {
        options.userInfo
    }

    /// 编码缓存：记录 keyed 容器各属性的初始值（用于默认值处理）
    /// WHAT：存储编码前的原始值，用于检测哪些属性被实际编码
    /// HOW：在创建 keyed 容器时初始化，编码过程中更新
    /// WHY：支持属性默认值和可选值处理，避免未编码属性丢失
    /// 注意：Unkeyed 容器不支持缓存
    var cache: EncodingCache

    /// 编码结果存储：单值、数组、对象三种可能类型
    var singleValue: JSONValue?
    var array: JSONFuture.RefArray?
    var object: JSONFuture.RefObject?

    /// 编码结果计算属性
    /// WHAT：根据当前存储类型返回对应的 JSONValue
    /// HOW：按优先级检查 object → array → singleValue，返回第一个非空值
    /// WHY：统一接口获取编码结果，支持延迟求值（通过 JSONFuture）
    var value: JSONValue? {
        if let object = self.object {
            return .object(object.values)
        }
        if let array = self.array {
            return .array(array.values)
        }
        return self.singleValue
    }

    /// 初始化编码器实现
    /// WHAT：创建编码器实例，配置选项和路径
    /// HOW：保存选项、路径，创建或共享编码缓存
    /// WHY：支持嵌套编码时共享缓存，保证状态一致性
    /// 学习文档：编码器初始化章节
    init(options: SmartJSONEncoder._Options, codingPath: [CodingKey], cache: EncodingCache? = nil) {
        self.options = options
        self.codingPath = codingPath
        self.cache = cache ?? EncodingCache()
    }
}

extension JSONEncoderImpl: Encoder {
    /// 创建键值编码容器
    /// WHAT：返回用于编码键值对集合的容器
    /// HOW：1. 如果已存在 object 则复用 2. 否则创建新的 RefObject 3. 包装为 KeyedEncodingContainer
    /// WHY：支持嵌套对象编码，确保每个键值编码位置正确
    /// 学习文档：编码容器章节
    func container<Key>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        if let _ = object {
            let container = JSONKeyedEncodingContainer<Key>(impl: self, codingPath: codingPath)
            return KeyedEncodingContainer(container)
        }

        guard self.singleValue == nil, self.array == nil else {
            preconditionFailure()
        }

        self.object = JSONFuture.RefObject()
        let container = JSONKeyedEncodingContainer<Key>(impl: self, codingPath: codingPath)
        return KeyedEncodingContainer(container)
    }

    /// 创建无键数组编码容器
    /// WHAT：返回用于编码数组元素的容器
    /// HOW：1. 如果已存在 array 则复用 2. 否则创建新的 RefArray 3. 包装为 UnkeyedEncodingContainer
    /// WHY：支持嵌套数组编码，保证元素顺序
    /// 学习文档：编码容器章节
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        if let _ = array {
            return JSONUnkeyedEncodingContainer(impl: self, codingPath: self.codingPath)
        }

        guard self.singleValue == nil, self.object == nil else {
            preconditionFailure()
        }

        self.array = JSONFuture.RefArray()
        return JSONUnkeyedEncodingContainer(impl: self, codingPath: self.codingPath)
    }

    /// 创建单值编码容器
    /// WHAT：返回用于编码单个值的容器
    /// HOW：创建 JSONSingleValueEncodingContainer 包装当前编码器
    /// WHY：确保单值编码不会与数组/对象编码冲突
    /// 学习文档：编码容器章节
    func singleValueContainer() -> SingleValueEncodingContainer {
        guard self.object == nil, self.array == nil else {
            preconditionFailure()
        }

        return JSONSingleValueEncodingContainer(impl: self, codingPath: self.codingPath)
    }
}

// 私有协议：为编码容器提供便捷方法
// WHAT：定义 _SpecialTreatmentEncoder 协议，允许编码容器直接调用编码器内部方法
// HOW：通过协议约束暴露必要的内部方法
// WHY：避免编码容器与编码器实现强耦合，保持接口清晰
// 学习文档：编码容器协议章节
extension JSONEncoderImpl: _SpecialTreatmentEncoder {
    var impl: JSONEncoderImpl {
        return self
    }

    /// 无类型转义方法：直接编码 Encodable 值为 JSONValue
    /// WHAT：处理特殊类型（Date/Data/URL/Decimal）和字典的快捷编码
    /// HOW：1. 检查类型，特殊类型使用专门的 wrap 方法 2. 字典调用 wrapObject 3. 其他类型调用 encode(to:)
    /// WHY：为编码容器提供统一的值编码入口，简化特殊类型处理逻辑
    /// 注意：此方法需要访问私有协议，仅限内部使用
    func wrapUntyped(_ encodable: Encodable) throws -> JSONValue {
        switch encodable {
        case let date as Date:
            return try self.wrapDate(date, for: nil)
        case let data as Data:
            return try self.wrapData(data, for: nil)
        case let url as URL:
            return .string(url.absoluteString)
        case let decimal as Decimal:
            return .number(decimal.description)
        case let object as [String: Encodable]: // this emits a warning, but it works perfectly
            return try self.wrapObject(object, for: nil)
        default:
            try encodable.encode(to: self)
            return self.value ?? .object([:])
        }
    }
}

