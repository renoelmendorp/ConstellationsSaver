//
//  ConstellationsDefaults.swift
//  Constellations
//

import ScreenSaver

class ConstellationsDefaults {
    
    /// The keys used to persist every setting in the module's defaults domain.
    enum Key: String {
        case numberOfNodes = "NumberOfNodes"
        case minSpeed = "MinSpeed"
        case maxSpeed = "MaxSpeed"
        case minRadius = "MinRadius"
        case maxRadius = "MaxRadius"
        case lineDistance = "LineDistance"
        case backgroundColor = "BackgroundColor"
        case nodeColor = "NodeColor"
        case lineColor = "LineColor"
        case renderingEngine = "RenderingEngine"
        case framesPerSecond = "FramesPerSecond"
    }
    
    /// The drawing back end used by the saver view.
    enum RenderingEngine: String, CaseIterable {
        case coreGraphics = "CoreGraphics"
        case metal = "Metal"
        
        var displayName: String {
            switch self {
            case .coreGraphics: return "Core Graphics"
            case .metal: return "Metal"
            }
        }
    }
    
    /// The factory settings, used both as the registration domain and by `reset()`.
    enum Factory {
        static let numberOfNodes: Int = 150
        static let minSpeed: CGFloat = 1.0
        static let maxSpeed: CGFloat = 5.0
        static let minRadius: CGFloat = 2.0
        static let maxRadius: CGFloat = 5.0
        static let lineDistance: CGFloat = 200.0
        static let backgroundColor: NSColor = .black
        static let nodeColor: NSColor = .white
        static let lineColor: NSColor = .white
        static let renderingEngine: RenderingEngine = .metal
        static let framesPerSecond: Int = 30
    }
    
    private var defaults = ScreenSaverDefaults(forModuleWithName: "nl.relmendorp.Constellations")
    
    /// Suppresses write-back while `load()` populates the properties.
    private var isLoading = false
    
    var numberOfNodes: Int = Factory.numberOfNodes {
        didSet { write(numberOfNodes, for: .numberOfNodes) }
    }
    var minSpeed = Factory.minSpeed {
        didSet { write(Double(minSpeed), for: .minSpeed) }
    }
    var maxSpeed = Factory.maxSpeed {
        didSet { write(Double(maxSpeed), for: .maxSpeed) }
    }
    var minRadius = Factory.minRadius {
        didSet { write(Double(minRadius), for: .minRadius) }
    }
    var maxRadius = Factory.maxRadius {
        didSet { write(Double(maxRadius), for: .maxRadius) }
    }
    var lineDistance = Factory.lineDistance {
        didSet { write(Double(lineDistance), for: .lineDistance) }
    }
    
    var backgroundColor: NSColor = Factory.backgroundColor {
        didSet { writeColor(backgroundColor, for: .backgroundColor) }
    }
    var nodeColor: NSColor = Factory.nodeColor {
        didSet { writeColor(nodeColor, for: .nodeColor) }
    }
    var lineColor: NSColor = Factory.lineColor {
        didSet { writeColor(lineColor, for: .lineColor) }
    }
    
    var renderingEngine: RenderingEngine = Factory.renderingEngine {
        didSet { write(renderingEngine.rawValue, for: .renderingEngine) }
    }
    var framesPerSecond: Int = Factory.framesPerSecond {
        didSet { write(framesPerSecond, for: .framesPerSecond) }
    }
    
    init() {
        defaults?.register(defaults: [
            Key.numberOfNodes.rawValue: Factory.numberOfNodes,
            Key.minSpeed.rawValue: Double(Factory.minSpeed),
            Key.maxSpeed.rawValue: Double(Factory.maxSpeed),
            Key.minRadius.rawValue: Double(Factory.minRadius),
            Key.maxRadius.rawValue: Double(Factory.maxRadius),
            Key.lineDistance.rawValue: Double(Factory.lineDistance),
            Key.renderingEngine.rawValue: Factory.renderingEngine.rawValue,
            Key.framesPerSecond.rawValue: Factory.framesPerSecond
        ])
        load()
    }
    
    // MARK: Reading
    
    /// Pulls the persisted values into the properties, without writing them straight back out again.
    func load() {
        guard let defaults = self.defaults else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        numberOfNodes = defaults.integer(forKey: Key.numberOfNodes.rawValue)
        minSpeed = CGFloat(defaults.double(forKey: Key.minSpeed.rawValue))
        maxSpeed = CGFloat(defaults.double(forKey: Key.maxSpeed.rawValue))
        minRadius = CGFloat(defaults.double(forKey: Key.minRadius.rawValue))
        maxRadius = CGFloat(defaults.double(forKey: Key.maxRadius.rawValue))
        lineDistance = CGFloat(defaults.double(forKey: Key.lineDistance.rawValue))
        
        backgroundColor = readColor(for: .backgroundColor) ?? Factory.backgroundColor
        nodeColor = readColor(for: .nodeColor) ?? Factory.nodeColor
        lineColor = readColor(for: .lineColor) ?? Factory.lineColor
        
        let engine = defaults.string(forKey: Key.renderingEngine.rawValue) ?? ""
        renderingEngine = RenderingEngine(rawValue: engine) ?? Factory.renderingEngine
        framesPerSecond = defaults.integer(forKey: Key.framesPerSecond.rawValue)
    }
    
    /// Restores every setting to its factory value.
    func reset() {
        numberOfNodes = Factory.numberOfNodes
        minSpeed = Factory.minSpeed
        maxSpeed = Factory.maxSpeed
        minRadius = Factory.minRadius
        maxRadius = Factory.maxRadius
        lineDistance = Factory.lineDistance
        backgroundColor = Factory.backgroundColor
        nodeColor = Factory.nodeColor
        lineColor = Factory.lineColor
        renderingEngine = Factory.renderingEngine
        framesPerSecond = Factory.framesPerSecond
    }
    
    private func readColor(for key: Key) -> NSColor? {
        guard let data = defaults?.data(forKey: key.rawValue) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }
    
    // MARK: Writing
    
    private func write(_ value: Any, for key: Key) {
        guard !isLoading, let defaults = self.defaults else { return }
        defaults.set(value, forKey: key.rawValue)
        defaults.synchronize()
    }
    
    private func writeColor(_ color: NSColor, for key: Key) {
        // NSColor is not a property list type, so it has to be archived first.
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: color,
                                                           requiringSecureCoding: true) else { return }
        write(data, for: key)
    }
}
