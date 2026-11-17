import Foundation

/// An element of an OpenDocument part, or a run of its character data.
///
/// Names keep a namespace prefix, but the prefix is the one `ODFNamespace` gives the namespace the file declared,
/// so "draw:frame" means the same element whatever prefix the file used. Character data stays in place among the
/// elements (text paragraphs mix the two).
final class ODFNode {
    static let textName = "#text"

    let name: String
    let attributes: [String: String]
    fileprivate(set) var children: [ODFNode] = []
    /// The characters of a text node.
    let text: String

    init(name: String, attributes: [String: String] = [:], text: String = "") {
        self.name = name
        self.attributes = attributes
        self.text = text
    }

    var isText: Bool { name == Self.textName }

    subscript(attribute: String) -> String? { attributes[attribute] }

    func child(_ name: String) -> ODFNode? { children.first { $0.name == name } }

    func children(_ name: String) -> [ODFNode] { children.filter { $0.name == name } }

    var elements: [ODFNode] { children.filter { !$0.isText } }

    /// Every character below this node, in document order.
    var textContent: String {
        if isText { return text }
        var result = ""
        appendText(to: &result)
        return result
    }

    private func appendText(to result: inout String) {
        for child in children {
            if child.isText { result += child.text } else { child.appendText(to: &result) }
        }
    }

    /// The first element named `name` below this one, depth first.
    func firstDescendant(_ name: String, depth: Int = 0) -> ODFNode? {
        guard depth < ODFXML.maxDepth else { return nil }
        for child in children where !child.isText {
            if child.name == name { return child }
            if let found = child.firstDescendant(name, depth: depth + 1) { return found }
        }
        return nil
    }
}

/// Parses package parts into `ODFNode` trees, refusing nesting deeper than real documents go: a tree thousands
/// of levels deep would exhaust the stack when it's freed.
enum ODFXML {
    static let maxDepth = 256

    static func parse(_ data: Data) throws -> ODFNode {
        let builder = Builder()
        guard XMLParsing.parse(data, delegate: builder), !builder.isTooDeep, let root = builder.root else { throw MalformedXMLError() }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        private(set) var root: ODFNode?
        private(set) var isTooDeep = false
        private var stack: [ODFNode] = []
        /// Namespace scopes: the depth that declared them, and the prefix map in force from there.
        private var scopes: [(depth: Int, prefixes: [String: String])] = [(0, ["xml": ODFNamespace.xml])]
        /// Canonical names by name as written, for the scope in force.
        private var nameCache: [String: String] = [:]
        private var pendingText = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            flushText()
            guard stack.count < ODFXML.maxDepth else {
                isTooDeep = true
                parser.abortParsing()
                return
            }
            var declarations: [String: String]?
            for (key, value) in attributeDict where key == "xmlns" || key.hasPrefix("xmlns:") {
                if declarations == nil { declarations = scopes[scopes.count - 1].prefixes }
                declarations?[key == "xmlns" ? "" : String(key.dropFirst(6))] = value
            }
            if let declarations {
                scopes.append((stack.count + 1, declarations))
                nameCache.removeAll(keepingCapacity: true)
            }
            var attributes: [String: String] = [:]
            attributes.reserveCapacity(attributeDict.count)
            for (key, value) in attributeDict where !(key == "xmlns" || key.hasPrefix("xmlns:")) {
                // Unprefixed attributes belong to no namespace.
                attributes[key.contains(":") ? canonical(key, isElement: false) : key] = value
            }
            let node = ODFNode(name: canonical(elementName, isElement: true), attributes: attributes)
            if let parent = stack.last {
                parent.children.append(node)
            } else if root == nil {
                root = node
            }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            flushText()
            if scopes.count > 1, scopes[scopes.count - 1].depth == stack.count {
                scopes.removeLast()
                nameCache.removeAll(keepingCapacity: true)
            }
            if !stack.isEmpty { stack.removeLast() }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            pendingText += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            pendingText += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
            parser.abortParsing()
        }

        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
            parser.abortParsing()
        }

        /// Character data is kept where text can matter: inside text elements, or when it isn't just white space.
        private func flushText() {
            guard !pendingText.isEmpty else { return }
            defer { pendingText = "" }
            guard let parent = stack.last else { return }
            if parent.name.hasPrefix("text:") || pendingText.contains(where: { !$0.isWhitespace }) {
                parent.children.append(ODFNode(name: ODFNode.textName, text: pendingText))
            }
        }

        /// "d:frame" with d bound to the drawing namespace is "draw:frame". Names in unknown namespaces keep their URI.
        private func canonical(_ name: String, isElement: Bool) -> String {
            let key = isElement ? name : "@" + name
            if let known = nameCache[key] { return known }
            let prefixes = scopes[scopes.count - 1].prefixes
            let result: String
            if let colon = name.firstIndex(of: ":") {
                let prefix = String(name[..<colon]), local = name[name.index(after: colon)...]
                if let uri = prefixes[prefix] {
                    result = (ODFNamespace.prefixes[uri] ?? "{\(uri)}") + ":" + local
                } else {
                    result = name
                }
            } else if isElement, let uri = prefixes[""] {
                result = (ODFNamespace.prefixes[uri] ?? "{\(uri)}") + ":" + name
            } else {
                result = name
            }
            nameCache[key] = result
            return result
        }
    }
}
