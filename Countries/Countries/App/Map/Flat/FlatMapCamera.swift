//
//  FlatMapCamera.swift
//  Countries
//
//  Created by Max Breuning on 07.01.26.
//

import CoreGraphics

/// Camera math isolated from the view (center/zoom clamping, transforms).
struct FlatMapCamera: Sendable {
    
    var normalizedCenter: CGPoint = CGPoint(x: 0.5, y: 0.5) // 0...1
    var userZoom: CGFloat = 1
    
    let maxUserZoom: CGFloat = 60
    var wrapsHorizontally: Bool = false
    
    func minimumUserZoom(viewport: CGRect,
                         worldRect: CGRect,
                         fitScale: CGFloat) -> CGFloat {
        
        guard viewport.width > 0,
              viewport.height > 0,
              worldRect.width > 0,
              worldRect.height > 0,
              fitScale > 0
        else {
            return 1
        }
        
        let minTotalScale = max(viewport.width / worldRect.width,
                                viewport.height / worldRect.height)
        let minUserZoom = minTotalScale / fitScale
        
        return max(0.0001, minUserZoom)
    }
    
    mutating func clamp(viewport: CGRect,
                        worldRect: CGRect,
                        fitScale: CGFloat) {
        
        let minUser = minimumUserZoom(viewport: viewport,
                                      worldRect: worldRect,
                                      fitScale: fitScale)
        userZoom = userZoom.clamped(minUser, maxUserZoom)
        
        let totalScale = fitScale * userZoom
        normalizedCenter = clampCenter(normalizedCenter,
                                       viewport: viewport,
                                       worldRect: worldRect,
                                       totalScale: totalScale)
    }
    
    func clampCenter(_ center: CGPoint,
                     viewport: CGRect,
                     worldRect: CGRect,
                     totalScale: CGFloat) -> CGPoint {
        
        guard viewport.width > 0,
              viewport.height > 0,
              worldRect.width > 0,
              worldRect.height > 0,
              totalScale > 0 else {
            return center
        }
        
        let visibleWidth = (viewport.width / totalScale) / worldRect.width
        let visibleHeight = (viewport.height / totalScale) / worldRect.height
        
        let minX = visibleWidth * 0.5
        let maxX = 1 - visibleWidth * 0.5
        let minY = visibleHeight * 0.5
        let maxY = 1 - visibleHeight * 0.5
        
        var x = center.x
        var y = center.y
        
        if wrapsHorizontally {
            x = x.truncatingRemainder(dividingBy: 1)
            if x < 0 { x += 1 }
        } else {
            x = x.clamped(minX, maxX)
        }
        
        y = y.clamped(minY, maxY)
        
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Transform helpers
    
    func offsetFromCenter(_ center: CGPoint,
                          viewport: CGRect,
                          worldRect: CGRect,
                          totalScale: CGFloat) -> CGSize {
        
        let cameraCenter = CGPoint(x: viewport.midX, y: viewport.midY)
        let worldPointX = worldRect.minX + center.x * worldRect.width
        let worldPointY = worldRect.minY + center.y * worldRect.height
        
        return CGSize(
            width: (cameraCenter.x - worldPointX) * totalScale,
            height: (cameraCenter.y - worldPointY) * totalScale
        )
    }
    
    func centerFromOffset(_ offset: CGSize,
                                 viewport: CGRect,
                                 worldRect: CGRect,
                                 totalScale: CGFloat) -> CGPoint {
        
        guard worldRect.width > 0,
              worldRect.height > 0,
              totalScale > 0
        else { return normalizedCenter }
        
        let cameraCenter = CGPoint(x: viewport.midX, y: viewport.midY)
        let worldPointX = cameraCenter.x - (offset.width / totalScale)
        let worldPointY = cameraCenter.y - (offset.height / totalScale)
        
        let x = (worldPointX - worldRect.minX) / worldRect.width
        let y = (worldPointY - worldRect.minY) / worldRect.height
        
        return CGPoint(x: x, y: y)
    }
    
    func zoomOffsetAroundPoint(
        currentOffset: CGSize,
        oldScale: CGFloat,
        newScale: CGFloat,
        viewport: CGRect,
        pinchCenter: CGPoint
    ) -> CGSize {
        
        guard oldScale > 0 else { return currentOffset }
        
        let cameraCenter = CGPoint(x: viewport.midX, y: viewport.midY)
        let px = pinchCenter.x - cameraCenter.x
        let py = pinchCenter.y - cameraCenter.y
        let k = 1 - (newScale / oldScale)
        
        return CGSize(
            width: currentOffset.width + (px - currentOffset.width) * k,
            height: currentOffset.height + (py - currentOffset.height) * k
        )
    }
    
    func untransform(screenPoint: CGPoint,
                     viewport: CGRect,
                     totalScale: CGFloat,
                     offset: CGSize) -> CGPoint {
        
        let cameraCenter = CGPoint(x: viewport.midX, y: viewport.midY)
        
        var x = screenPoint.x - cameraCenter.x - offset.width
        var y = screenPoint.y - cameraCenter.y - offset.height
        
        x /= totalScale
        y /= totalScale
        
        x += cameraCenter.x
        y += cameraCenter.y
        
        return CGPoint(x: x, y: y)
    }
}
