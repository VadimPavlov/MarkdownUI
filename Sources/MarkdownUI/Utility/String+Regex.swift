import Foundation

extension String {
    func firstMatch(of pattern: String, options: NSRegularExpression.Options = []) -> String? {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(location: 0, length: utf8.count)
        let match = regex?.firstMatch(in: self, range: range)?.range
        let subrange = match.flatMap { Range($0, in: self)}
        return subrange.map { String(self[$0]) }
    }
}
