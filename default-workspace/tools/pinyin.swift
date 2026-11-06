// 把每行中文转成拼音：输出 "原文\t全拼(无空格)\t首字母"
import Foundation

func convert(_ s: String) -> (String, String) {
    let m = NSMutableString(string: s) as CFMutableString
    CFStringTransform(m, nil, kCFStringTransformMandarinLatin, false)
    CFStringTransform(m, nil, kCFStringTransformStripDiacritics, false)
    let full = (m as String).lowercased()
    let joined = full.replacingOccurrences(of: " ", with: "")
    let initials = full.split(separator: " ").compactMap { $0.first }.map(String.init).joined()
    return (joined, initials)
}

var out = ""
while let line = readLine(strippingNewline: true) {
    let (py, ini) = convert(line)
    out += "\(line)\t\(py)\t\(ini)\n"
}
print(out, terminator: "")
