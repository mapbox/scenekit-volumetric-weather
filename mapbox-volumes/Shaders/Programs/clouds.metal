//
//  clouds.metal
//  mapbox-volumes
//
//  Created by Jim Martin on 7/31/18.
//  Copyright © 2018 Mapbox.


#include <metal_stdlib>
using namespace metal;
#include <SceneKit/scn_metal>

//Information about the node, passed to the vertex function
struct NodeBuffer {
    float4x4 modelTransform;
    float4x4 inverseModelTransform;
    float4x4 modelViewTransform;
    float4x4 inverseModelViewTransform;
    float4x4 normalTransform;
    float4x4 modelViewProjectionTransform;
    float4x4 inverseModelViewProjectionTransform;
    float2x3 boundingBox;
};

//Information about the vertex, passed to the vertex function
typedef struct {
    float3 position [[ attribute(SCNVertexSemanticPosition) ]];
    float2 texCoords [[ attribute(SCNVertexSemanticTexcoord0) ]];
} VertexInput;

//Vertex function output, passed to the fragment function
struct VertexOut
{
    float4 position [[position]];
    float4 fragmentModelCoordinates;
    float4 nodePosition;
    float4 cameraCoordinates;
    float4 cameraPosition;
    float2 texCoords;
    float time;
};

//MARK: - Vertex Function
//used to pass positions in node-space to the fragment function, in order to do per-pixel ray marching.
vertex VertexOut cloudVertex(VertexInput in [[ stage_in ]],
                             constant SCNSceneBuffer& scn_frame [[buffer(0)]],
                             constant NodeBuffer& scn_node [[buffer(1)]])
{
    VertexOut vert;
    vert.position = scn_node.modelViewProjectionTransform * float4(in.position, 1.0);
    vert.texCoords = in.texCoords;
    
    //define raymarching transforms in node(model) space, so that the output
    //can be repostioned/rotated/scaled using the node's transform
    vert.fragmentModelCoordinates = float4(in.position, 1.0);
    vert.cameraCoordinates = scn_node.modelViewTransform * float4(in.position, 1.0);
    vert.nodePosition = float4(0,0,0, 1.0);
    vert.cameraPosition = scn_node.inverseModelViewTransform * float4(0,0,0, 1.0);
    
    //define animation parameters
    vert.time = scn_frame.time;
    return vert;
}

//MARK: - Ray Marching

//MARK: Ray Marching utilities
struct Ray {
    float3 origin;
    float3 direction;
    Ray(float3 o, float3 d) {
        origin = o;
        direction = d;
    }
};

float3 IntersectionOnPlane( float3 offsetOrthogonalToPlane, float3 rayDirection)
{
    float dotToSurface = dot(normalize(offsetOrthogonalToPlane), rayDirection);
    if( dotToSurface <= 0.0)
    {
        return float3(0);
    }
    return rayDirection * length(offsetOrthogonalToPlane) / dotToSurface;
};

//MARK: Ray Marching Function
/// For a given ray(ray) and volume position(nodePosition) step through the input textures(noiseTexture, interferenceTexture, densityMap) to output a final pixel color.
///
/// - Parameters:
///   - ray: origin and direction of view for a single fragment
///   - nodePosition: the center of the final rendered volume
///   - time: scn_frame.time passed from the vertex function, used to animate the noise textures
///   - noiseTexture: texture that provides soft noise distortion to the final cloud volume, tiled and animated
///   - interferenceTexture: texture that creates harsher distortions, tiled and animated
///   - densityMap: real cloud data, white is denser cloud cover, black is thinner.

float4 RayMarch(Ray ray, float4 nodePosition, float time, texture2d<float, access::sample> noiseTexture, texture2d<float, access::sample> interferenceTexture, texture2d<float, access::sample> densityMap)
{
    float3 initialDirection = ray.direction;
    float3 initialPosition = ray.origin;
    float3 samplePosition = initialPosition;
    
    // Raymarching parameters
    //initial direction, *0.01 to make the skipstep values easier to modify/experiment with
    float3 offset = initialDirection * 0.01;
    //skipstep: the distance travelled at each step. Larger numbers are more performant, but lower quality.
    float skipStep = 8.0;
    //scale for the noise samples, larger numbers scale up the noise texture.
    float tileScale = 1;
    
    //animation parameters, these could be made into shader inputs, or even become data-driven by textures
    float2 windDirection = normalize(float2(.5,.5));
    float3 baseColor = float3(.85, .8, .7); //the color to add per-step.
    float opacityModifier = .2; //scale for the opacity contribution per-step, higher numbers make thicker clouds.
    float cloudDensityModifier = 4.0; //scale factor for cloud density, higher numbers makes the density map more pronounced in the output.

    //cloud bounds
    float cloudSizeVertical = .5;
    float cloudCenterBounds = nodePosition.y;
    float cloudUpperBounds = cloudCenterBounds + cloudSizeVertical;
    float cloudLowerBounds = cloudCenterBounds - cloudSizeVertical;
    
    //place the initial sample on cloud bounds (defined above)
    if(samplePosition.y > cloudUpperBounds)
    {
        float3 orthoOffset = float3(samplePosition.x, cloudUpperBounds, samplePosition.z) - samplePosition;
        float3 offsetToBounds = IntersectionOnPlane(orthoOffset, initialDirection);
        samplePosition += offsetToBounds;
    }
    if(samplePosition.y < cloudLowerBounds)
    {
        float3 orthoOffset = float3(samplePosition.x, cloudLowerBounds, samplePosition.z) - samplePosition;
        float3 offsetToBounds = IntersectionOnPlane(orthoOffset, initialDirection);
        samplePosition += offsetToBounds;
    }
    
    //final pixel color from raymarching
    float4 outputColor = float4(0.0);
    
    //measure initial position from the sampleposition snapped to cloud boundaries
    initialPosition = samplePosition;
    
    //initialize offset before loop, in case we want to apply a default
    float3 newOffset = offset;
    
    //define multiple samplers, one for each texture
    //density: the opacity of the volume. samples the satellite cloud texture
    constexpr sampler densitySampler(coord::normalized, filter::nearest, address::clamp_to_zero);
    //noise: adds some interference to the volume, creating more realistic, animated final visuals
    constexpr sampler softNoiseSampler(coord::normalized, filter::linear, address::repeat);
    constexpr sampler sharpNoiseSampler(coord::normalized, filter::linear, address::repeat);
    
    
    //MARK: Ray Marching Loop
    //takes up to 30 texture samples per-pixel, moving by the offset*stepsize in node-space every loop.
    for(int i = int(0); i < 30; i++)
    {
        
        //stop marching if the ray has left the cloud volume
        if(samplePosition.y > cloudUpperBounds + 0.01)
        {
            break;
        }
        if(samplePosition.y < cloudLowerBounds - 0.01)
        {
            break;
        }
        
        //get distance from the cloud's center plane
        float dist = (samplePosition.y - cloudCenterBounds) / cloudSizeVertical;
        float absDist = abs(dist);
        
        //use node-space coordinates to define UVs, so that the volume responds to positions/scale/rotation changes
        float2 nodeUV = (samplePosition.xz - nodePosition.xz) / tileScale;

        //cheap modulo here is faster than feeding large uv positions to the sampler
        float2 moduloNodeUV = nodeUV;
        moduloNodeUV = moduloNodeUV - floor(moduloNodeUV);
        
        //offset the UVs from node center to match normalized texture coordinate space (0-1).
        nodeUV += 0.5;
        
        //check density using the red component - standard when sampling greyscale images
        float4 densitySample = densityMap.sample(densitySampler, nodeUV );
        float density = densitySample.r * cloudDensityModifier;
        
        //animate the noise textures over time
        float2 softNoiseAnimation = time * 0.01 * windDirection;
        float2 noiseUV = moduloNodeUV - softNoiseAnimation;
        float4 softNoiseSample = noiseTexture.sample(softNoiseSampler, noiseUV );
        softNoiseSample.a = softNoiseSample.r;
        
        //create a copy to interfere with the original noise sample, causing clouds to distort over time
        float2 interferenceAnimation = softNoiseAnimation;
        interferenceAnimation.x *= -2;
        float2 interferenceUV = moduloNodeUV + float2(.5,.5) - (interferenceAnimation);
        float4 interferenceSample = interferenceTexture.sample(sharpNoiseSampler, interferenceUV);
        interferenceSample.a = interferenceSample.r;
        
        //create final texture sample by mixing base, interference samples and density
        float4 textureSample = saturate((density) - (softNoiseSample * 0.6 - interferenceSample * 0.6 ));
        
        //blend with previous samples if the sample alpha is high enough
        if( textureSample.a >= absDist )
        {
            //use the texture sample to add some opacity to the output color
            float opacityGain = textureSample.a * opacityModifier;
            outputColor.a += opacityGain;
            
            //color the output based on the height of sample - higher samples are lighter.
            float3 baseSampleColor = mix(1.0, dist * 0.5 + 0.5, baseColor) * opacityGain;
            outputColor.rgb += baseSampleColor;
        }
        
        //move the sample position to the new offset based on the skipstep and the opacity of the current sample
        //more opaque samples step less, to create better definition around the edges.
        newOffset = offset * (skipStep) * ( 1.1-textureSample.a );
        samplePosition += newOffset;
        
        //set a max opacity for the output color, and stop marching if it's reached.
        if(outputColor.a >= .8)
            break;
       
    };
    
    return outputColor;
};

//MARK: - Fragment Function
fragment half4 cloudFragment(VertexOut in [[stage_in]],
                            constant NodeBuffer& scn_node [[buffer(1)]],
                            texture2d<float, access::sample> noiseTexture [[texture(0)]],
                            texture2d<float, access::sample> interferenceTexture [[texture(1)]],
                            texture2d<float, access:: sample> densityMap [[texture(2)]])
{
    
    //construct ray pointing into the cloud volume
    float3 rayDirection = normalize(float3( in.fragmentModelCoordinates.xyz - in.cameraPosition.xyz));
    float3 rayOrigin = in.fragmentModelCoordinates.xyz;
    Ray ray = Ray(rayOrigin, rayDirection);
    
    //output the ray marching result
    float4 output = RayMarch(ray, in.nodePosition, in.time, noiseTexture, interferenceTexture, densityMap);
    return half4(output);
    
};
