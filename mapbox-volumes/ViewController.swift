//
//  ViewController.swift
//  mapbox-volumes
//
//  Created by Jim Martin on 7/31/18.
//  Copyright © 2018 Jim Martin. All rights reserved.
//

import UIKit
import SceneKit
//import MapboxSceneKit

class ViewController: UIViewController, SCNSceneRendererDelegate {
    
    var sceneView: SCNView = SCNView()
    private var scene: SCNScene = SCNScene()
    
    var cloudNode: CloudVolume!
//    var terrainNode: TerrainNode?
//    var terrainNodeScale = SCNVector3(0.00003, 0.00005, 0.00003) // scale down map (otherwise it's far too big)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupSceneView()
        
        let minLat = 37.72
        let minLon = -122.521
        let maxLat = 37.835
        let maxLon = -122.378
        
        //create a cloud node
        cloudNode = CloudVolume(minLat:minLat, maxLat: maxLat,
                                minLon: minLon, maxLon: maxLon)
        cloudNode.scale = SCNVector3(x: 1, y: 0.1, z: 1) //flatten the volume into a thin layer
        scene.rootNode.addChildNode(cloudNode)
        
//        terrainNode = TerrainNode(minLat: minLat, maxLat: maxLat ,
//                                  minLon: minLon, maxLon: maxLon)
//        if let terrainNode = terrainNode {
//            terrainNode.scale = terrainNodeScale // scale down map (otherwise it's far too big)
//            scene.rootNode.addChildNode(terrainNode)
//
//            terrainNode.fetchTerrainHeights(minWallHeight: 100.0, enableDynamicShadows: true, progress: { progress, total in
//            }, completion: {
//                NSLog("Terrain load complete")
//            })
//
//            terrainNode.fetchTerrainTexture("mapbox/satellite-v9", zoom: 14, progress: { progress, total in
//            }, completion: { image in
//                NSLog("Texture load complete")
//                terrainNode.geometry?.materials[4].diffuse.contents = image
//            })
//        }
    }
    
    //add lights, camera
    func setupSceneView(){
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
}
