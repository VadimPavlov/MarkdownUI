import Foundation

public extension Double {
    static func from(html: String) -> Self? {
        let sizes = ["xx-small": 0.5625,
                     "x-small": 0.625,
                     "small": 0.8125,
                     "medium": 1,
                     "large": 1.125,
                     "x-large": 1.5,
                     "xx-large": 2,
                     "xxx-large": 3]
        return sizes[html]
    }
}
