import Foundation

/// An element of a small in-memory XML tree, for the short parts of a package (workbook, relationships,
/// styles, theme) and for small pieces of streamed parts.
///
/// Element and attribute names drop their namespace prefixes ("r:id" → "id"); when an element has both
/// a prefixed and an unprefixed attribute with the same local name, the prefixed one wins.
/// Namespace declarations aren't kept.
final class XNode {
    let name: String
    let attributes: [String: String]
    fileprivate(set) var children: [XNode] = []
    /// The element's own character data, concatenated.
    fileprivate(set) var text = ""

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    subscript(attribute: String) -> String? { attributes[attribute] }

    func child(_ name: String) -> XNode? { children.first { $0.name == name } }

    func children(_ name: String) -> [XNode] { children.filter { $0.name == name } }

    /// The first element named `name` below this one, depth first.
    func firstDescendant(_ name: String) -> XNode? {
        for child in children {
            if child.name == name { return child }
            if let found = child.firstDescendant(name) { return found }
        }
        return nil
    }

    /// Every element named `name` below this one, depth first.
    func descendants(_ name: String) -> [XNode] {
        var result: [XNode] = []
        for child in children {
            if child.name == name { result.append(child) }
            result.append(contentsOf: child.descendants(name))
        }
        return result
    }

    /// Attributes keyed by local name, without namespace declarations.
    static func localAttributes(_ attributes: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in attributes {
            if key == "xmlns" || key.hasPrefix("xmlns:") { continue }
            if let local = XMLParsing.strippingPrefix(key) {
                result[local] = value
            } else if result[key] == nil {
                result[key] = value
            }
        }
        return result
    }
}

/// Builds a tree from parser events: a whole part, or one element of a streamed part with everything
/// inside it.
final class XNodeBuilder {
    /// Real parts nest a few dozen levels. Deeper ones are refused: a tree tens of thousands of levels deep
    /// overflows the stack when it's freed.
    static let maximumDepth = 256

    private(set) var root: XNode?
    private var stack: [XNode] = []
    /// Skipped elements still open, so their ends stay matched with their starts.
    private var skipped = 0
    /// Set once an element went past `maximumDepth`; a whole-part parse stops there.
    private(set) var isTooDeep = false

    init() {}

    /// Starts building at an element whose start was already seen.
    init(rootName: String, attributes: [String: String]) {
        start(rootName, attributes)
    }

    func start(_ name: String, _ attributes: [String: String]) {
        guard skipped == 0, stack.count < Self.maximumDepth else {
            skipped += 1
            isTooDeep = true
            return
        }
        let node = XNode(name: XMLParsing.localName(name), attributes: XNode.localAttributes(attributes))
        if let parent = stack.last {
            parent.children.append(node)
        } else if root == nil {
            root = node
        } else {
            return
        }
        stack.append(node)
    }

    /// Ends the innermost element; true when that was the root.
    @discardableResult
    func end() -> Bool {
        if skipped > 0 {
            skipped -= 1
            return false
        }
        guard !stack.isEmpty else { return false }
        stack.removeLast()
        return stack.isEmpty
    }

    func characters(_ text: String) {
        guard skipped == 0 else { return }
        stack.last?.text += text
    }
}

enum XMLTree {
    static func parse(_ data: Data) throws -> XNode {
        let builder = TreeBuilder()
        guard XMLParsing.parse(data, delegate: builder), !builder.tree.isTooDeep, let root = builder.tree.root else { throw MalformedXMLError() }
        return root
    }

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        let tree = XNodeBuilder()

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            tree.start(elementName, attributeDict)
            if tree.isTooDeep { parser.abortParsing() }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            tree.end()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            tree.characters(string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            tree.characters(String(decoding: CDATABlock, as: UTF8.self))
        }

        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
            parser.abortParsing()
        }

        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
            parser.abortParsing()
        }
    }
}
