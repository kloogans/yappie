// Yappie/DebugLog.swift
import Foundation

private let logFile: FileHandle? = {
    let path = "/tmp/yappie-debug.log"
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}()

func debugLog(_ message: String) {
    let line = "\(message)\n"
    print(line, terminator: "")
    if let data = line.data(using: .utf8) {
        logFile?.seekToEndOfFile()
        logFile?.write(data)
    }
}
