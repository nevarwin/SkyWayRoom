import Foundation
import SkyWayRoom

public class RoomManager: ObservableObject {
    public static let shared = RoomManager()
    
    private var context: Context?
    private var room: Room?
    private(set) var localAudioStream: LocalAudioStream?
    private(set) var localVideoStream: LocalVideoStream?
    
    @Published public var isJoined: Bool = false
    @Published public var remoteStreams: [Stream] = []
    
    public init() {}
    
    public func setup(token: String) async throws {
        let options = Context.Options(
            logLevel: .error,
            token: token
        )
        self.context = try await Context.setup(with: options)
    }
    
    public func join(roomName: String, mode: Room.InitOptions.Mode = .p2p) async throws {
        guard let context = context else {
            throw SkyWayError.contextNotSetup
        }
        
        let roomInitOptions = Room.InitOptions(mode: mode)
        let room = try await P2PRoom.findOrCreate(with: roomName, options: roomInitOptions)
        self.room = room
        
        // Join the room
        let memberInitOptions = Room.MemberInitOptions()
        let _ = try await room.join(with: memberInitOptions)
        
        self.isJoined = true
        
        // Subscribe to delegate or events if needed
        // Note: Real implementation would attach delegates here to handle stream events
    }
    
    public func leave() async {
        guard let room = room else { return }
        try? await room.leave()
        self.room = nil
        self.isJoined = false
        self.remoteStreams.removeAll()
    }
    
    public func createLocalStream() {
        // Create audio/video streams
        self.localAudioStream = LocalAudioStream()
        self.localVideoStream = CameraVideoSource.shared().createStream()
    }
    
    public func publish() async throws {
        guard let room = room, let member = room.localMember else { return }
        
        if let audioScope = localAudioStream {
            try await member.publish(audioScope)
        }
        if let videoScope = localVideoStream {
            try await member.publish(videoScope)
        }
    }
}

public enum SkyWayError: Error {
    case contextNotSetup
}
