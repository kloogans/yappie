// Yappie/DebugLog.swift
import Foundation

private let logFile: FileHandle? = {
    #if DEBUG
    let path = "/tmp/yappie-debug.log"
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
    #else
    return nil
    #endif
}()

func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    let line = "\(message())\n"
    print(line, terminator: "")
    if let data = line.data(using: .utf8) {
        logFile?.seekToEndOfFile()
        logFile?.write(data)
    }
    #endif
}
