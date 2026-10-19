import Foundation

public enum MetadataField: String, CaseIterable, Codable, Sendable, Identifiable {
  case creator = "Creator"
  case copyright = "Copyright notice"
  case rights = "Usage rights"
  case website = "Copyright URL"
  case title = "Title"
  case caption = "Caption"
  case credit = "Credit"
  case job = "Job identifier"
  case createdCity = "Location created: city"
  case createdCountry = "Location created: country"
  case createdPlace = "Location created: place"
  case shownCity = "Location shown: city"
  case shownCountry = "Location shown: country"
  case shownPlace = "Location shown: place"
  public var id: String { rawValue }
}
public struct DescriptiveMetadata: Codable, Equatable, Sendable {
  public var fields: [MetadataField: String] = [:]
  public var keywords: [String] = []
  public var hierarchy: [String] = []
  public var keywordsPresent = false
  public var hierarchyPresent = false
  public init() {}
}
public enum KeywordAction: String, CaseIterable, Codable, Sendable {
  case leave = "Leave unchanged"
  case append = "Append"
  case replace = "Replace"
  case remove = "Remove"
  case clear = "Clear"
}
public struct MetadataPatch: Codable, Sendable {
  /// Missing fields are untouched. An explicit empty string clears that field.
  public var fields: [MetadataField: String] = [:]
  public var keywordAction: KeywordAction = .leave
  public var keywordText = ""
  public init() {}
  public func applying(to source: DescriptiveMetadata) throws -> DescriptiveMetadata {
    var result = source
    for (key, value) in fields { result.fields[key] = value }
    let tokens = keywordText.components(separatedBy: CharacterSet(charactersIn: ",\n"))
      .map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
      }.filter { !$0.isEmpty }
    guard
      !tokens.contains(where: {
        $0.contains("|")
          && $0.components(separatedBy: "|").contains(where: {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
          })
      })
    else {
      throw MediaOperationError.invalid(
        "A keyword hierarchy must have nonempty levels separated by |.")
    }
    let hierarchy = tokens.filter { $0.contains("|") }.map {
      $0.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.joined(
        separator: "|")
    }
    let flat = tokens.map {
      $0.components(separatedBy: "|").last!.trimmingCharacters(in: .whitespaces)
    }
    if keywordAction != .leave {
      result.keywordsPresent = true
      result.hierarchyPresent = true
    }
    switch keywordAction {
    case .leave: break
    case .append:
      result.keywords = Self.unique(source.keywords + flat)
      result.hierarchy = Self.unique(source.hierarchy + hierarchy)
    case .replace:
      result.keywords = Self.unique(flat)
      result.hierarchy = Self.unique(hierarchy)
    case .remove:
      let paths = Set(hierarchy.map { $0.lowercased() })
      let flatOnly = Set(tokens.filter { !$0.contains("|") }.map { $0.lowercased() })
      result.hierarchy.removeAll {
        paths.contains($0.lowercased())
          || flatOnly.contains(($0.components(separatedBy: "|").last ?? "").lowercased())
      }
      let retainedLeaves = Set(
        result.hierarchy.compactMap { $0.components(separatedBy: "|").last?.lowercased() })
      result.keywords.removeAll { value in
        flat.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame })
          && !retainedLeaves.contains(value.lowercased())
      }
    case .clear:
      result.keywords = []
      result.hierarchy = []
    }
    return result
  }
  private static func unique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0.lowercased()).inserted }
  }
}

extension XMPSidecar {
  private static let dc = "http://purl.org/dc/elements/1.1/"
  private static let rightsURI = "http://ns.adobe.com/xap/1.0/rights/"
  private static let photoshop = "http://ns.adobe.com/photoshop/1.0/"
  private static let iptc = "http://iptc.org/std/Iptc4xmpExt/2008-02-29/"
  private static let lr = "http://ns.adobe.com/lightroom/1.0/"
  private static func mapping(_ field: MetadataField) -> (String, String, String) {
    switch field {
    case .creator: (dc, "dc", "creator")
    case .copyright: (dc, "dc", "rights")
    case .rights: (rightsURI, "xmpRights", "UsageTerms")
    case .website: (rightsURI, "xmpRights", "WebStatement")
    case .title: (dc, "dc", "title")
    case .caption: (dc, "dc", "description")
    case .credit: (photoshop, "photoshop", "Credit")
    case .job: (photoshop, "photoshop", "TransmissionReference")
    case .createdCity, .shownCity: (iptc, "Iptc4xmpExt", "City")
    case .createdCountry, .shownCountry: (iptc, "Iptc4xmpExt", "CountryName")
    case .createdPlace, .shownPlace: (iptc, "Iptc4xmpExt", "Sublocation")
    }
  }
  private static func locationKind(_ field: MetadataField) -> String? {
    switch field {
    case .createdCity, .createdCountry, .createdPlace: "LocationCreated"
    case .shownCity, .shownCountry, .shownPlace: "LocationShown"
    default: nil
    }
  }
  private static func attributeValue(_ parent: XMLElement, uri: String, local: String) -> String? {
    parent.attributes?.first { $0.uri == uri && $0.localName == local }?.stringValue
  }
  private static func child(_ parent: XMLNode, uri: String, local: String) -> XMLElement? {
    parent.children?.compactMap { $0 as? XMLElement }.first {
      $0.uri == uri && $0.localName == local
    }
  }
  private static func values(_ parent: XMLElement, uri: String, local: String) -> [String] {
    if let attribute = attributeValue(parent, uri: uri, local: local) { return [attribute] }
    guard let field = child(parent, uri: uri, local: local) else { return [] }
    if let alt = child(field, uri: rdf, local: "Alt"),
      let defaultItem = alt.children?.compactMap({ $0 as? XMLElement }).first(where: {
        $0.attribute(forName: "xml:lang")?.stringValue == "x-default"
      }),
      let text = defaultItem.stringValue
    {
      return [text]
    }
    let items = walk(field).filter { $0.uri == rdf && $0.localName == "li" }
    if !items.isEmpty { return items.compactMap(\.stringValue) }
    if child(field, uri: rdf, local: "Bag") != nil || child(field, uri: rdf, local: "Seq") != nil {
      return []
    }
    return field.stringValue.map { [$0] } ?? []
  }
  private static func description(_ data: Data?) throws -> (XMLDocument, XMLElement) {
    let initial = Data(
      "<x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='\(rdf)'><rdf:Description rdf:about=''/></rdf:RDF></x:xmpmeta>"
        .utf8)
    let doc = try document(data ?? initial)
    let descriptions = walk(doc).filter {
      $0.uri == rdf && $0.localName == "Description" && $0.parent?.localName == "RDF"
    }
    guard descriptions.count == 1, let target = descriptions.first else {
      throw SidecarError.ambiguous
    }
    return (doc, target)
  }
  private static func location(_ target: XMLElement, kind: String, create: Bool) throws
    -> XMLElement?
  {
    if let property = child(target, uri: iptc, local: kind) {
      if let bag = child(property, uri: rdf, local: "Bag") {
        let items =
          bag.children?.compactMap { $0 as? XMLElement }.filter { $0.localName == "li" } ?? []
        guard items.count == 1 else { throw SidecarError.ambiguous }
        return items[0]
      }
      return child(property, uri: rdf, local: "Description") ?? property
    }
    guard create else { return nil }
    try bind(target, uri: iptc, prefix: "Iptc4xmpExt")
    let property = XMLElement(name: "Iptc4xmpExt:\(kind)", uri: iptc)
    let resource = XMLElement(name: "rdf:Description", uri: rdf)
    property.addChild(resource)
    target.addChild(property)
    return resource
  }
  private static func bind(_ target: XMLElement, uri: String, prefix: String) throws {
    if let binding = target.resolveNamespace(forName: "\(prefix):field"), binding.stringValue != uri
    {
      throw SidecarError.ambiguous
    }
    target.addNamespace(XMLNode.namespace(withName: prefix, stringValue: uri) as! XMLNode)
  }
  public static func descriptive(_ data: Data?) throws -> DescriptiveMetadata {
    let (_, target) = try description(data)
    var result = DescriptiveMetadata()
    for field in MetadataField.allCases {
      let (uri, _, local) = mapping(field)
      let parent: XMLElement?
      if let kind = locationKind(field) {
        parent = try? location(target, kind: kind, create: false)
      } else {
        parent = target
      }
      if let parent, let value = values(parent, uri: uri, local: local).first {
        result.fields[field] = value
      }
    }
    result.keywordsPresent =
      child(target, uri: dc, local: "subject") != nil
      || attributeValue(target, uri: dc, local: "subject") != nil
    result.hierarchyPresent =
      child(target, uri: lr, local: "hierarchicalSubject") != nil
      || attributeValue(target, uri: lr, local: "hierarchicalSubject") != nil
    result.keywords = values(target, uri: dc, local: "subject")
    result.hierarchy = values(target, uri: lr, local: "hierarchicalSubject")
    return result
  }
  public static func combinedDescriptive(sidecar: Data?, embedded: Data?) throws
    -> DescriptiveMetadata
  {
    var result = try descriptive(embedded)
    let overlay = try descriptive(sidecar)
    result.fields.merge(overlay.fields) { _, new in new }
    if overlay.keywordsPresent {
      result.keywords = overlay.keywords
      result.keywordsPresent = true
    }
    if overlay.hierarchyPresent {
      result.hierarchy = overlay.hierarchy
      result.hierarchyPresent = true
    }
    return result
  }

  public static func mergingMetadata(
    _ value: DescriptiveMetadata, fields: Set<MetadataField>, keywords: Bool, into data: Data?
  ) throws -> Data {
    let (doc, target) = try description(data)
    for field in fields {
      let (uri, prefix, local) = mapping(field)
      let parent: XMLElement
      if let kind = locationKind(field) {
        parent = try location(target, kind: kind, create: true)!
      } else {
        parent = target
      }
      let text = value.fields[field] ?? ""
      // Preserve alternate languages in dc:Alt while changing only x-default.
      if [.title, .caption, .copyright, .rights].contains(field) {
        try bind(target, uri: uri, prefix: prefix)
        let property =
          child(parent, uri: uri, local: local) ?? XMLElement(name: "\(prefix):\(local)", uri: uri)
        if property.parent == nil { parent.addChild(property) }
        if let existing = child(property, uri: rdf, local: "Alt") {
          let defaults =
            existing.children?.compactMap { $0 as? XMLElement }.filter {
              $0.attribute(forName: "xml:lang")?.stringValue == "x-default"
            } ?? []
          for item in defaults { item.detach() }
          existing.addChild(languageItem(text))
        } else {
          property.setChildren(nil)
          let alt = XMLElement(name: "rdf:Alt", uri: rdf)
          alt.addChild(languageItem(text))
          property.addChild(alt)
        }
        if let name = parent.attributes?.first(where: { $0.uri == uri && $0.localName == local })?
          .name
        {
          parent.removeAttribute(forName: name)
        }
      } else {
        try replace(
          parent, target: target, uri: uri, prefix: prefix, local: local,
          values: text.isEmpty ? [] : [text], container: field == .creator ? "Seq" : nil)
      }
    }
    if keywords {
      try replace(
        target, target: target, uri: dc, prefix: "dc", local: "subject", values: value.keywords,
        container: "Bag", preserveEmpty: true)
      try replace(
        target, target: target, uri: lr, prefix: "lr", local: "hierarchicalSubject",
        values: value.hierarchy, container: "Bag", preserveEmpty: true)
    }
    return doc.xmlData(options: [.nodePreserveAll])
  }
  private static func languageItem(_ text: String) -> XMLElement {
    let item = XMLElement(name: "rdf:li", uri: rdf)
    item.addAttribute(XMLNode.attribute(withName: "xml:lang", stringValue: "x-default") as! XMLNode)
    item.stringValue = text
    return item
  }
  private static func replace(
    _ parent: XMLElement, target: XMLElement, uri: String, prefix: String, local: String,
    values: [String], container: String?, preserveEmpty: Bool = false
  ) throws {
    try bind(target, uri: uri, prefix: prefix)
    for attribute in parent.attributes ?? []
    where attribute.uri == uri && attribute.localName == local {
      if let name = attribute.name { parent.removeAttribute(forName: name) }
    }
    for item in parent.children?.compactMap({ $0 as? XMLElement }) ?? []
    where item.uri == uri && item.localName == local { item.detach() }
    guard !values.isEmpty || preserveEmpty else { return }
    let property = XMLElement(name: "\(prefix):\(local)", uri: uri)
    if let container {
      let list = XMLElement(name: "rdf:\(container)", uri: rdf)
      for text in values {
        let item = XMLElement(name: "rdf:li", uri: rdf)
        item.stringValue = text
        list.addChild(item)
      }
      property.addChild(list)
    } else {
      property.stringValue = values[0]
    }
    parent.addChild(property)
  }
}
