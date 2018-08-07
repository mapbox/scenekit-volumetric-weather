//
//  ViewController.swift
//  mapbox-volumes
//
//  Created by Jim Martin on 7/31/18.
//  Copyright © 2018 Mapbox.
//
//  Create a SceneKit view with a 3D map of San Francisco
//  and volumetric clouds above it.
//

import UIKit
import SceneKit
import MapboxSceneKit

class ViewController: UIViewController, SCNSceneRendererDelegate {
    
    var sceneView: SCNView = SCNView()
    private var scene: SCNScene = SCNScene()
    
    var cloudNode: CloudVolume!
    var terrainNode: TerrainNode?
    var terrainNodeScale = SCNVector3(0.0003, 0.0003, 0.0003) // Scale down map (otherwise it's far too big)
    
    // San Francisco
    var minLat = 37.72
    var minLon = -122.521
    var maxLat = 37.835
    var maxLon = -122.378
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupSceneView()
        createClouds()
        createTerrain()
    }
    
    // Set up sceneview with camera and lights
    func setupSceneView() {
        self.view.addSubview(sceneView)
        sceneView.frame = self.view.bounds
        
        sceneView.scene = scene
        sceneView.delegate = self
        sceneView.allowsCameraControl = true
        sceneView.showsStatistics = true
        sceneView.isPlaying = true
        
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 5)
        scene.rootNode.addChildNode(cameraNode)
        
        let lightNode = SCNNode()
        let light = SCNLight()
        light.type = .ambient
        light.intensity = 1000
        lightNode.light = light
        scene.rootNode.addChildNode(lightNode)
    }
    
    // Create clouds with same coordinates as terrain
    func createClouds() {
        cloudNode = CloudVolume(minLat:minLat, maxLat: maxLat,
                                minLon: minLon, maxLon: maxLon)
        cloudNode.scale = SCNVector3(x: 3.8, y: 0.1, z: 3.8) // Flatten the volume into a thin layer
        scene.rootNode.addChildNode(cloudNode)
    }
    
    // Create map with terrain and satellite imagery below clouds
    func createTerrain() {
        terrainNode = TerrainNode(minLat: minLat, maxLat: maxLat,
                                  minLon: minLon, maxLon: maxLon)
        
        if let terrainNode = terrainNode {
            terrainNode.scale = terrainNodeScale // Scale down map
            terrainNode.position = SCNVector3Make(0, -0.3, 0) // Place map slightly below clouds
            terrainNode.geometry?.materials = defaultMaterials() // Add default materials
            scene.rootNode.addChildNode(terrainNode)
            
            terrainNode.fetchTerrainHeights(minWallHeight: 100.0, enableDynamicShadows: true, progress: { progress, total in
            }, completion: {
                NSLog("Terrain load complete")
            })
            
            terrainNode.fetchTerrainTexture("mapbox/satellite-v9", zoom: 14, progress: { progress, total in
            }, completion: { image in
                NSLog("Texture load complete")
                terrainNode.geometry?.materials[4].diffuse.contents = image
            })
        }
    }
    
    // Create default materials for each side of the terrain node
    func defaultMaterials() -> [SCNMaterial] {
        let groundImage = SCNMaterial()
        groundImage.diffuse.contents = UIColor.darkGray
        groundImage.name = "Ground texture"
        
        let sideMaterial = SCNMaterial()
        sideMaterial.diffuse.contents = UIColor.darkGray
        sideMaterial.isDoubleSided = true
        sideMaterial.name = "Side"
        
        let bottomMaterial = SCNMaterial()
        bottomMaterial.diffuse.contents = UIColor.black
        bottomMaterial.name = "Bottom"
        
        return [sideMaterial, sideMaterial, sideMaterial, sideMaterial, groundImage, bottomMaterial]
    }
}
