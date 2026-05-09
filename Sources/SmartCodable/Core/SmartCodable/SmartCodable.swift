//  ____                               _      ____               _           _       _          _
// / ___|   _ __ ___     __ _   _ __  | |_   / ___|   ___     __| |   __ _  | |__   | |   ___  | |
// \___ \  | '_ ` _ \   / _` | | '__| | __| | |      / _ \   / _` |  / _` | | '_ \  | |  / _ \ | |
//  ___) | | | | | | | | (_| | | |    | |_  | |___  | (_) | | (_| | | (_| | | |_) | | | |  __/ |_|
// |____/  |_| |_| |_|  \__,_| |_|     \__|  \____|  \___/   \__,_|  \__,_| |_.__/  |_|  \___| (_)
//


// SmartCodableX 是 SmartDecodable & SmartEncodable 的类型别名，对应原生 Codable = Decodable & Encodable
// 使用别名可以简化协议组合的声明，同时保持与 Codable 的语义对齐
// SmartCodable 沿用 Codable 协议设计，编译器仍会自动合成 init(from:) 和 encode(to:)
// 变化点在于 Decoder 实现和解码容器层的容错处理，而非模型代码层面
public typealias SmartCodableX = SmartDecodable & SmartEncodable

// 为泛型集合类型添加条件扩展：当元素类型满足 SmartCodableX 时，数组类型也满足 SmartCodableX
// 这使得 [T] 在 T 满足 SmartCodableX 时能够自动递归解码，无需额外实现
// 例如：[User] 在 User: SmartCodableX 时可直接解码 JSON 数组
// 用在泛型解析中，支持嵌套集合类型的自动 Codable 合成
extension Array: SmartCodableX where Element: SmartCodableX { }
