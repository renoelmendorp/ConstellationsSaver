//
//  ConstellationsShaders.metal
//  Constellations
//

#include <metal_stdlib>
using namespace metal;

// Kept in step with the matching Swift structs in ConstellationsMetalRenderer.swift.
struct Uniforms {
    float2 viewportSize;    // The drawing area, in points.
    float  scale;           // Drawable pixels per point.
    float  lineWidth;       // In points.
    float4 nodeColor;
    float4 lineColor;
};

struct LineInstance {
    float2 p0;
    float2 p1;
    float  intensity;
};

struct NodeInstance {
    float2 position;
    float  radius;
};

/// Maps a point in the view's coordinate space (bottom-left origin) to clip space.
static inline float4 clipSpacePosition(float2 point, float2 viewportSize) {
    return float4(point / viewportSize * 2.0 - 1.0, 0.0, 1.0);
}

// MARK: Lines

struct LineVertexOut {
    float4 position [[position]];
    float  intensity;
    float  edge;    // -1 and +1 at the two long edges of the segment.
};

/// Expands each line instance into a quad, so the width is expressed in points rather than
/// being stuck at Metal's one-pixel line primitive.
vertex LineVertexOut constellations_line_vertex(uint vertexID [[vertex_id]],
                                                uint instanceID [[instance_id]],
                                                const device LineInstance *lines [[buffer(0)]],
                                                constant Uniforms &uniforms [[buffer(1)]])
{
    LineInstance segment = lines[instanceID];

    float2 delta = segment.p1 - segment.p0;
    float span = length(delta);
    float2 direction = span > 0.0 ? delta / span : float2(1.0, 0.0);
    float2 normal = float2(-direction.y, direction.x) * (uniforms.lineWidth * 0.5);

    float side = (vertexID & 1) == 0 ? 1.0 : -1.0;
    float2 anchor = vertexID < 2 ? segment.p0 : segment.p1;

    LineVertexOut out;
    out.position = clipSpacePosition(anchor + normal * side, uniforms.viewportSize);
    out.intensity = segment.intensity;
    out.edge = side;
    return out;
}

fragment float4 constellations_line_fragment(LineVertexOut in [[stage_in]],
                                             constant Uniforms &uniforms [[buffer(0)]])
{
    // Fade out over the outermost pixel so the segments are antialiased.
    float halfWidthPixels = max(uniforms.lineWidth * uniforms.scale * 0.5, 0.5);
    float pixelsFromEdge = (1.0 - abs(in.edge)) * halfWidthPixels;
    float coverage = saturate(pixelsFromEdge + 0.5);

    float4 color = uniforms.lineColor;
    return float4(color.rgb, color.a * in.intensity * coverage);
}

// MARK: Nodes

struct NodeVertexOut {
    float4 position [[position]];
    float2 offset;          // Distance from the node's centre, in points.
    float  radiusPixels;
};

/// Expands each node instance into a quad that the fragment shader carves a disc out of.
vertex NodeVertexOut constellations_node_vertex(uint vertexID [[vertex_id]],
                                                uint instanceID [[instance_id]],
                                                const device NodeInstance *nodes [[buffer(0)]],
                                                constant Uniforms &uniforms [[buffer(1)]])
{
    NodeInstance node = nodes[instanceID];

    float2 corner = float2((vertexID & 1) == 0 ? -1.0 : 1.0,
                           vertexID < 2 ? -1.0 : 1.0);
    // One pixel of slack, so the antialiased edge is not clipped away by the quad.
    float padding = 1.0 / max(uniforms.scale, 1.0);
    float2 offset = corner * (node.radius + padding);

    NodeVertexOut out;
    out.position = clipSpacePosition(node.position + offset, uniforms.viewportSize);
    out.offset = offset;
    out.radiusPixels = node.radius * uniforms.scale;
    return out;
}

fragment float4 constellations_node_fragment(NodeVertexOut in [[stage_in]],
                                             constant Uniforms &uniforms [[buffer(0)]])
{
    float distancePixels = length(in.offset) * uniforms.scale;
    float coverage = saturate(in.radiusPixels - distancePixels + 0.5);
    if (coverage <= 0.0) {
        discard_fragment();
    }

    float4 color = uniforms.nodeColor;
    return float4(color.rgb, color.a * coverage);
}
