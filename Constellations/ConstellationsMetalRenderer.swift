//
//  ConstellationsMetalRenderer.swift
//  Constellations
//

import MetalKit
import ScreenSaver

// MARK: Shared layout with ConstellationsShaders.metal

private struct Uniforms {
    var viewportSize: SIMD2<Float>
    var scale: Float
    var lineWidth: Float
    var nodeColor: SIMD4<Float>
    var lineColor: SIMD4<Float>
}

private struct LineInstance {
    var p0: SIMD2<Float>
    var p1: SIMD2<Float>
    var intensity: Float
}

private struct NodeInstance {
    var position: SIMD2<Float>
    var radius: Float
}

/// Draws the constellation on the GPU.
///
/// Both passes are instanced: one quad per line and one per node, expanded in the vertex shader,
/// which keeps the whole frame down to two draw calls. The only per-frame CPU work is the pair
/// test that decides which nodes are close enough to be joined.
final class ConstellationsMetalRenderer: NSObject, MTKViewDelegate {
    
    /// Whether this Mac can run the Metal engine at all.
    static var isSupported: Bool { MTLCreateSystemDefaultDevice() != nil }
    
    private static let maximumFramesInFlight = 3
    private static let lineWidth: Float = 1.0
    
    /// The view the renderer draws into, to be added to the saver view's hierarchy.
    var contentView: NSView { view }
    
    private let view: MTKView
    private let defaults: ConstellationsDefaults
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let linePipeline: MTLRenderPipelineState
    private let nodePipeline: MTLRenderPipelineState
    
    private let frameSemaphore = DispatchSemaphore(value: ConstellationsMetalRenderer.maximumFramesInFlight)
    private var frameIndex = 0
    private var lineBuffers: [MTLBuffer?]
    private var nodeBuffers: [MTLBuffer?]
    
    /// The frame that `render(nodes:)` has staged and `draw(in:)` has still to encode.
    private var pendingFrame: (lineCount: Int, nodeCount: Int, uniforms: Uniforms)?
    
    private var positions: [SIMD2<Float>] = []
    
    // MARK: Setup
    
    init?(defaults: ConstellationsDefaults, frame: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else { return nil }
        
        // The shaders are compiled into the bundle's default.metallib at build time.
        let bundle = Bundle(for: ConstellationsMetalRenderer.self)
        guard let library = try? device.makeDefaultLibrary(bundle: bundle),
              let linePipeline = Self.makePipeline(device: device,
                                                   library: library,
                                                   vertexFunction: "constellations_line_vertex",
                                                   fragmentFunction: "constellations_line_fragment"),
              let nodePipeline = Self.makePipeline(device: device,
                                                   library: library,
                                                   vertexFunction: "constellations_node_vertex",
                                                   fragmentFunction: "constellations_node_fragment")
        else { return nil }
        
        self.defaults = defaults
        self.device = device
        self.commandQueue = commandQueue
        self.linePipeline = linePipeline
        self.nodePipeline = nodePipeline
        self.lineBuffers = Array(repeating: nil, count: Self.maximumFramesInFlight)
        self.nodeBuffers = Array(repeating: nil, count: Self.maximumFramesInFlight)
        
        self.view = MTKView(frame: frame, device: device)
        
        super.init()
        
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.framebufferOnly = true
        view.autoResizeDrawable = true
        // The saver's own animation timer drives the frames, so the view never draws on its own.
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.layer?.isOpaque = true
        view.clearColor = Self.clearColor(defaults.backgroundColor)
    }
    
    private static func makePipeline(device: MTLDevice,
                                     library: MTLLibrary,
                                     vertexFunction: String,
                                     fragmentFunction: String) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertexFunction)
        descriptor.fragmentFunction = library.makeFunction(name: fragmentFunction)
        
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = .bgra8Unorm
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.sourceAlphaBlendFactor = .sourceAlpha
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    // MARK: Drawing
    
    /// Stages one frame's worth of geometry and draws it.
    func render(nodes: [Node]) {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, view.drawableSize.width > 0 else { return }
        
        frameSemaphore.wait()
        frameIndex = (frameIndex + 1) % Self.maximumFramesInFlight
        
        pendingFrame = stageFrame(nodes: nodes, size: size)
        view.clearColor = Self.clearColor(defaults.backgroundColor)
        view.draw()
    }
    
    private func stageFrame(nodes: [Node], size: NSSize) -> (lineCount: Int, nodeCount: Int, uniforms: Uniforms) {
        positions.removeAll(keepingCapacity: true)
        positions.reserveCapacity(nodes.count)
        for node in nodes {
            positions.append(SIMD2<Float>(Float(node.position.x), Float(node.position.y)))
        }
        
        let uniforms = Uniforms(viewportSize: SIMD2<Float>(Float(size.width), Float(size.height)),
                                scale: Float(view.drawableSize.width / max(size.width, 1)),
                                lineWidth: Self.lineWidth,
                                nodeColor: Self.components(defaults.nodeColor),
                                lineColor: Self.components(defaults.lineColor))
        
        return (lineCount: stageLines(),
                nodeCount: stageNodes(nodes),
                uniforms: uniforms)
    }
    
    /// Writes one instance per pair of nodes that is close enough to be joined.
    private func stageLines() -> Int {
        let count = positions.count
        guard count > 1 else { return 0 }
        
        let capacity = count * (count - 1) / 2
        guard let buffer = resizedBuffer(lineBuffers[frameIndex],
                                         count: capacity,
                                         stride: MemoryLayout<LineInstance>.stride) else { return 0 }
        lineBuffers[frameIndex] = buffer
        
        let lineDistance = Float(defaults.lineDistance)
        guard lineDistance > 0 else { return 0 }
        
        let instances = buffer.contents().bindMemory(to: LineInstance.self, capacity: capacity)
        var written = 0
        
        positions.withUnsafeBufferPointer { points in
            for idx in 0..<(count - 1) {
                let first = points[idx]
                for jdx in (idx + 1)..<count {
                    let second = points[jdx]
                    let separation = simd_distance(first, second)
                    if separation <= lineDistance {
                        instances[written] = LineInstance(p0: first,
                                                          p1: second,
                                                          intensity: 1.0 - separation / lineDistance)
                        written += 1
                    }
                }
            }
        }
        
        return written
    }
    
    /// Writes every node; the ones off screen cost nothing once the GPU clips them.
    private func stageNodes(_ nodes: [Node]) -> Int {
        let count = nodes.count
        guard count > 0,
              let buffer = resizedBuffer(nodeBuffers[frameIndex],
                                         count: count,
                                         stride: MemoryLayout<NodeInstance>.stride) else { return 0 }
        nodeBuffers[frameIndex] = buffer
        
        let instances = buffer.contents().bindMemory(to: NodeInstance.self, capacity: count)
        for idx in 0..<count {
            instances[idx] = NodeInstance(position: positions[idx], radius: Float(nodes[idx].radius))
        }
        
        return count
    }
    
    /// Reuses the buffer when it is already big enough. The size only changes when the node
    /// count does, so this reallocates on a settings change rather than every frame.
    private func resizedBuffer(_ existing: MTLBuffer?, count: Int, stride: Int) -> MTLBuffer? {
        let length = max(count, 1) * stride
        if let existing, existing.length >= length { return existing }
        return device.makeBuffer(length: length, options: .storageModeShared)
    }
    
    // MARK: MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        // Only draw frames that `render(nodes:)` staged, so an unsolicited redraw does not
        // unbalance the in-flight semaphore.
        guard let frame = pendingFrame else { return }
        pendingFrame = nil
        
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            frameSemaphore.signal()
            return
        }
        
        var uniforms = frame.uniforms
        let uniformsLength = MemoryLayout<Uniforms>.stride
        
        if frame.lineCount > 0, let lineBuffer = lineBuffers[frameIndex] {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setVertexBuffer(lineBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: uniformsLength, index: 1)
            encoder.setFragmentBytes(&uniforms, length: uniformsLength, index: 0)
            encoder.drawPrimitives(type: .triangleStrip,
                                   vertexStart: 0,
                                   vertexCount: 4,
                                   instanceCount: frame.lineCount)
        }
        
        if frame.nodeCount > 0, let nodeBuffer = nodeBuffers[frameIndex] {
            encoder.setRenderPipelineState(nodePipeline)
            encoder.setVertexBuffer(nodeBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: uniformsLength, index: 1)
            encoder.setFragmentBytes(&uniforms, length: uniformsLength, index: 0)
            encoder.drawPrimitives(type: .triangleStrip,
                                   vertexStart: 0,
                                   vertexCount: 4,
                                   instanceCount: frame.nodeCount)
        }
        
        encoder.endEncoding()
        commandBuffer.addCompletedHandler { [frameSemaphore] _ in frameSemaphore.signal() }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // MARK: Colors
    
    private static func components(_ color: NSColor) -> SIMD4<Float> {
        guard let color = color.usingColorSpace(.sRGB) else { return SIMD4<Float>(1, 1, 1, 1) }
        return SIMD4<Float>(Float(color.redComponent),
                            Float(color.greenComponent),
                            Float(color.blueComponent),
                            Float(color.alphaComponent))
    }
    
    private static func clearColor(_ color: NSColor) -> MTLClearColor {
        let components = components(color)
        return MTLClearColor(red: Double(components.x),
                             green: Double(components.y),
                             blue: Double(components.z),
                             alpha: Double(components.w))
    }
}
