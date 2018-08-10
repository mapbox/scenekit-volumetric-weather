//
//  CloudVolume.swift
//  mapbox-volumes
//
//  Created by Jim Martin on 6/20/18.
//  Copyright © 2018 Mapbox.
//
//  Create volumetric clouds.
//

import Foundation
import SceneKit
import Mapbox

class CloudVolume: SCNNode, MGLMapViewDelegate {

    var mapView: MGLMapView? = nil
    var rasterLayer: MGLRasterStyleLayer? = nil
    var debugPlane: SCNNode!
    
    private var minLat: Double!
    private var maxLat: Double!
    private var minLon: Double!
    private var maxLon: Double!
    
    override init(){
        super.init()
    }
    
    convenience init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        self.init()
        
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
        
        setGeometry()
        setCloudShader()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    // We assume a 1x1x1 cube, but other shapes would work as well.
    private func setGeometry() {
        self.geometry = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.0)
    }
    
    private func setCloudShader() {
        // Create cloud material
        let cloudMaterial = SCNMaterial()
        self.geometry?.firstMaterial = cloudMaterial
        
        // Set shader program
        let program = SCNProgram()
        program.fragmentFunctionName = "cloudFragment" // In Shaders/Programs/clouds.metal
        program.vertexFunctionName = "cloudVertex"     // In Shaders/Programs/clouds.metal
        program.isOpaque = false
        cloudMaterial.program = program
        
        // Set noise texture
        let noiseImage  = UIImage(named: "art.scnassets/softNoise.png")!
        let noiseImageProperty = SCNMaterialProperty(contents: noiseImage)
        cloudMaterial.setValue(noiseImageProperty, forKey: "noiseTexture")

        let intImage  = UIImage(named: "art.scnassets/sharpNoise.png")!
        let intImageProperty = SCNMaterialProperty(contents: intImage)
        cloudMaterial.setValue(intImageProperty, forKey: "interferenceTexture")
        
        // Set up cloud map
        debugPlane = SCNNode(geometry: SCNPlane(width: 1, height: 1))
            // Offset the plane so that it's visible below the volume node
            debugPlane.position = SCNVector3Make(0, -1, 0)
            // Rotate it to match the orientation of the volume node's samples
            debugPlane.eulerAngles = SCNVector3Make(-Float.pi / 2, 0, 0)
            // Cull the front, so that it's only visible from below
            debugPlane.geometry?.firstMaterial?.cullMode = .front
        self.addChildNode(debugPlane)
        
        let url = URL(string: "mapbox://styles/mapbox/streets-v10")
        mapView = MGLMapView(frame: CGRect(x: 0, y: 0, width: 512, height: 512), styleURL: url)
        if let mapView = self.mapView {
            let sw = CLLocationCoordinate2D(latitude: minLat, longitude: maxLon)
            let ne = CLLocationCoordinate2D(latitude: maxLat, longitude: minLon)
            mapView.setVisibleCoordinateBounds(MGLCoordinateBounds(sw: sw, ne: ne), animated: false)
            mapView.delegate = self
            mapView.isUserInteractionEnabled = false
        }
    }
    
    func mapView(_ mapView: MGLMapView, didFinishLoading style: MGLStyle) {
        self.addCloudRasterTileLayer(style: style)
        
        // Applying views as material properties may cause a memory leak. see thread: (https://forums.developer.apple.com/message/71497#71497)
        debugPlane.geometry?.firstMaterial?.diffuse.contents = mapView
        let densityProperty = SCNMaterialProperty(contents: mapView)
        self.geometry?.firstMaterial?.setValue(densityProperty, forKey: "densityMap")
    }
    
    private func addCloudRasterTileLayer(style: MGLStyle) -> Void {
        // Add the raster source layer from real earth (http://realearth.ssec.wisc.edu/)
        // Documentation (http://realearth.ssec.wisc.edu/doc/)
        // Not maintained by Mapbox
        
        // This requests the *most recent* ir imagery, and may appear incorrect after sunset locally.
        let cloudTileURLTemplate = "https://re.ssec.wisc.edu/api/image?products=G16-ABI-FD-BAND02&x={x}&y={y}&z={z}&client=RealEarth&device=Browser"
        let source = MGLRasterTileSource(identifier: "cloudcover", tileURLTemplates: [cloudTileURLTemplate], options: [ .tileSize: 256 ])
        let rasterLayer = MGLRasterStyleLayer(identifier: "cloudcover", source: source)
        
        style.addSource(source)
        style.addLayer(rasterLayer)
        self.rasterLayer = rasterLayer
    }
}
