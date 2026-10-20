import CryptoKit
import Foundation

public enum SidecarError: LocalizedError {
  case malformed, conflict, ambiguous
  public var errorDescription: String? {
    switch self {
    case .malformed: "XMP could not be safely read. The existing sidecar was left untouched."
    case .conflict:
      "XMP changed externally. Your decisions are saved locally; resolve the conflict before syncing."
    case .ambiguous: "Multiple files share this RAW sidecar name. Decisions are saved locally."
    }
  }
}

public enum XMPSidecar {
  private static let xmp = "http://ns.adobe.com/xap/1.0/"
  private static let dm = "http://ns.adobe.com/xmp/1.0/DynamicMedia/"
  static let rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  public static func url(for image: URL) -> URL {
    PhotoFormats.isRaw(image)
      ? image.deletingPathExtension().appendingPathExtension("xmp")
      : image.appendingPathExtension("xmp")
  }
  public static func digest(_ data: Data?) -> String {
    data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "absent"
  }
  static func document(_ data: Data) throws -> XMLDocument {
    guard data.count <= 16 * 1024 * 1024,
      let text = String(data: data, encoding: .utf8),
      !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY"),
      let document = try? XMLDocument(data: data, options: [.nodePreserveAll]),
      document.rootElement() != nil
    else { throw SidecarError.malformed }
    return document
  }
  /// XMP is an XML fragment/packet, not a standalone XML document. In
  /// particular, older ImageIO XMP readers reject Foundation's standalone
  /// declaration. Preserve the existing packet instructions and tree.
  static func serializedPacket(_ document: XMLDocument) -> Data {
    document.characterEncoding = "UTF-8"
    var text = String(decoding: document.xmlData(options: [.nodePreserveAll]), as: UTF8.self)
    if text.hasPrefix("<?xml "), let end = text.range(of: "?>") {
      text.removeSubrange(text.startIndex..<end.upperBound)
    }
    return Data(text.utf8)
  }
  // Traverse explicitly: namespace prefixes are arbitrary in real sidecars.
  static func walk(_ node: XMLNode) -> [XMLElement] {
    var result: [XMLElement] = []
    if let element = node as? XMLElement { result.append(element) }
    for child in node.children ?? [] { result += walk(child) }
    return result
  }
  public static func read(_ data: Data) throws -> CullingDecision {
    let doc = try document(data)
    func value(_ uri: String, _ name: String) -> String? {
      for element in walk(doc) {
        for attr in element.attributes ?? [] where attr.localName == name && attr.uri == uri {
          return attr.stringValue
        }
        if element.localName == name && element.uri == uri { return element.stringValue }
      }
      return nil
    }
    let rating = Int(value(xmp, "Rating") ?? "0") ?? 0
    let pick = value(dm, "pick").flatMap(Int.init).flatMap(PhotoFlag.init(rawValue:))
    let good = value(dm, "good")?.lowercased()
    return CullingDecision(
      rating: rating,
      flag: pick
        ?? (rating == -1
          ? .reject : good == "true" ? .pick : good == "false" ? .reject : .unflagged))
  }
  public static func merging(
    _ decision: CullingDecision, into data: Data?, fields owned: SourceDecisionFields = .all
  ) throws -> Data {
    let initial = Data(
      "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"\(rdf)\"><rdf:Description rdf:about=\"\"/></rdf:RDF></x:xmpmeta>"
        .utf8)
    let doc = try document(data ?? initial)
    let descriptions = walk(doc).filter {
      $0.localName == "Description" && $0.uri == rdf && $0.parent?.localName == "RDF"
        && $0.parent?.uri == rdf
    }
    guard let target = descriptions.first, descriptions.count == 1 else {
      throw SidecarError.malformed
    }
    let fields: [(String, String, String, String?)] = [
      (xmp, "xmp", "Rating", String(decision.rating)),
      (dm, "xmpDM", "pick", String(decision.flag.rawValue)),
      (
        dm, "xmpDM", "good",
        decision.flag == .unflagged ? nil : decision.flag == .pick ? "true" : "false"
      ),
    ]
    for (uri, prefix, name, value) in fields {
      guard name == "Rating" ? owned.contains(.rating) : owned.contains(.flag) else { continue }
      // Reject conflicting prefix bindings instead of damaging unrelated properties.
      if let binding = target.resolveNamespace(forName: "\(prefix):\(name)"),
        binding.stringValue != uri
      {
        throw SidecarError.malformed
      }
      for attr in target.attributes ?? [] where attr.uri == uri && attr.localName == name {
        if let attrName = attr.name { target.removeAttribute(forName: attrName) }
      }
      for item in target.children?.compactMap({ $0 as? XMLElement }) ?? []
      where item.uri == uri && item.localName == name { item.detach() }
      if let value {
        if target.resolveNamespace(forName: "\(prefix):\(name)") == nil {
          target.addNamespace(XMLNode.namespace(withName: prefix, stringValue: uri) as! XMLNode)
        }
        target.addAttribute(
          XMLNode.attribute(withName: "\(prefix):\(name)", uri: uri, stringValue: value) as! XMLNode
        )
      }
    }
    return serializedPacket(doc)
  }
}
