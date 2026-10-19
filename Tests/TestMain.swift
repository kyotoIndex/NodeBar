import Foundation

@main
enum NodeBarTestRunner {
    static func main() throws {
        try LocalizationTests.run()
        print("Language selection tests passed")
        try LocalCoreTests.run()
        print("Local core and Unix socket tests passed")
        try ActiveMonitoringTests.run()
        print("Active monitoring and pinned-node tests passed")
        try SocketDiscoveryTests.run()
        print("Socket discovery tests passed")
        try AppPreferencesTests.run()
        print("Existing preferences migration tests passed")
        try AlertPolicyTests.run()
        print("Alert policy transition tests passed")
    }
}
