import SwiftUI
import SkyWayRoom

/// A SwiftUI wrapper for the local camera preview
public struct SkyWayLocalVideoView: UIViewRepresentable {xw
    public init() {}
    
    public func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        // Determine how the video should fit within the view
        view.videoContentMode = .scaleAspectFill
        
        // Attach the preview to this view
        RoomManager.shared.attachLocalPreview(to: view)
        return view
    }
    
    public func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // No updates needed for now
    }
    
    public static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) {
        RoomManager.shared.detachLocalPreview(from: uiView)
    }
}

/// A SwiftUI wrapper for rendering a remote video stream
public struct SkyWayRemoteVideoView: UIViewRepresentable {
    let publicationId: String
    
    public init(publicationId: String) {
        self.publicationId = publicationId
    }
    
    public func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.videoContentMode = .scaleAspectFill
        
        // Find the subscription/stream and attach
        RoomManager.shared.attachRemoteVideo(publicationId: publicationId, to: view)
        
        return view
    }
    
    public func updateUIView(_ uiView: VideoView, context: Context) {
        // If the publication ID somehow changed in a way that requires re-attach, 
        // we might handle it here, but usually SwiftUI recreates the view for id changes
    }
    
    // We can't easily detach using just the view in dismantleUIView because 
    // we need the publication/subscription info which might be lost.
    // However, RoomManager logic should handle cleanup when subscription ends.
    // A more robust implementation would track what is attached.
}

