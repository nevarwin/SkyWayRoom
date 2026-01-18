import Foundation
import SkyWayRoom

/// Protocol for receiving room events
public protocol RoomManagerDelegate: AnyObject {
    func roomManager(_ manager: RoomManager, didReceiveRemotePublication publication: RoomPublication)
    func roomManager(_ manager: RoomManager, didRemoveRemotePublication publication: RoomPublication)
    func roomManager(_ manager: RoomManager, memberDidJoin member: RoomMember)
    func roomManager(_ manager: RoomManager, memberDidLeave member: RoomMember)
    func roomManager(_ manager: RoomManager, didReceiveData data: Data, from member: RoomMember)
}

public class RoomManager: ObservableObject {
    public static let shared = RoomManager()
    
    // MARK: - Delegate
    public weak var delegate: RoomManagerDelegate?
    
    // MARK: - Core Properties
    private var context: Context?
    private var room: Room?
    private var localMember: LocalRoomMember?
    
    // MARK: - Audio/Video Sources
    private var audioSource: MicrophoneAudioSource?
    private(set) var localAudioStream: LocalAudioStream?
    private(set) var localVideoStream: LocalVideoStream?
    private(set) var localDataStream: LocalDataStream?
    
    // MARK: - Publications & Subscriptions
    private var audioPublication: RoomPublication?
    private var videoPublication: RoomPublication?
    private var dataPublication: RoomPublication?
    private var subscriptions: [String: RoomSubscription] = [:] // keyed by publication ID
    
    // MARK: - Published State
    @Published public var isJoined: Bool = false
    @Published public var remoteStreams: [Stream] = []
    @Published public var remotePublications: [RoomPublication] = []
    @Published public var lastReceivedMessage: String = ""
    
    public init() {}
    
    // MARK: - Context Setup
    
    public func setup(token: String) async throws {
        let options = ContextOptions()
        options.logLevel = .error
        self.context = try await Context.setup(withToken: token, options: options)
    }
    
    /// Development-only setup with app ID and secret key
    public func setupForDev(appId: String, secretKey: String) async throws {
        let options = ContextOptions()
        options.logLevel = .trace
        try await Context.setupForDev(withAppId: appId, secretKey: secretKey, options: options)
    }
    
    // MARK: - Camera Setup
    
    /// Setup and start camera capture with specified position
    public func setupCamera(position: AVCaptureDevice.Position = .front) async throws {
        guard let camera = CameraVideoSource.supportedCameras().first(where: { $0.position == position }) else {
            throw SkyWayError.cameraNotFound
        }
        try await CameraVideoSource.shared().startCapturing(with: camera, options: nil)
    }
    
    /// Stop camera capture
    public func stopCamera() {
        CameraVideoSource.shared().stopCapturing()
    }
    
    /// Attach local camera preview to a view
    public func attachLocalPreview(to view: CameraPreviewView) {
        CameraVideoSource.shared().attach(view)
    }
    
    /// Detach local camera preview from a view
    public func detachLocalPreview(from view: CameraPreviewView) {
        CameraVideoSource.shared().detach(view)
    }
    
    // MARK: - Room Join/Leave
    
    public func join(roomName: String, memberName: String? = nil, mode: Room.InitOptions.Mode = .p2p) async throws {
        guard context != nil else {
            throw SkyWayError.contextNotSetup
        }
        
        // Create or find room
        let roomInitOptions = Room.InitOptions()
        roomInitOptions.mode = mode
        
        let room: Room
        if mode == .p2p {
            room = try await P2PRoom.findOrCreate(with: roomName, options: roomInitOptions)
        } else {
            room = try await SFURoom.findOrCreate(with: roomName, options: roomInitOptions)
        }
        self.room = room
        
        // Setup room event handlers
        setupRoomEventHandlers(for: room)
        
        // Join the room
        let memberInitOptions = Room.MemberInitOptions()
        if let name = memberName {
            memberInitOptions.name = name
        }
        self.localMember = try await room.join(with: memberInitOptions)
        
        await MainActor.run {
            self.isJoined = true
            // Update remote publications with existing ones
            self.updateRemotePublications()
        }
    }
    
    public func leave() async {
        // Unsubscribe from all subscriptions
        for (_, subscription) in subscriptions {
            try? await subscription.cancel()
        }
        subscriptions.removeAll()
        
        // Unpublish our streams
        if let audioPublication = audioPublication {
            try? await localMember?.unpublish(publication: audioPublication)
        }
        if let videoPublication = videoPublication {
            try? await localMember?.unpublish(publication: videoPublication)
        }
        
        // Leave the room
        try? await localMember?.leave()
        
        // Clean up
        stopCamera()
        audioSource = nil
        localAudioStream = nil
        localVideoStream = nil
        audioPublication = nil
        videoPublication = nil
        dataPublication = nil
        localMember = nil
        room = nil
        
        await MainActor.run {
            self.isJoined = false
            self.remoteStreams.removeAll()
            self.remotePublications.removeAll()
        }
    }
    
    // MARK: - Local Stream Creation
    
    public func createLocalStreams() {
        // Create audio stream using proper MicrophoneAudioSource pattern
        self.audioSource = MicrophoneAudioSource()
        self.localAudioStream = audioSource?.createStream()
        
        // Create video stream from camera
        self.localVideoStream = CameraVideoSource.shared().createStream()
        
        // Create data stream
        self.localDataStream = LocalDataStream(name: "data_stream")
    }
    
    // MARK: - Publishing
    
    /// Publish local audio and video streams to the room
    public func publish(useSFU: Bool = false) async throws {
        guard let member = localMember else {
            throw SkyWayError.memberNotJoined
        }
        
        let publicationType: RoomPublicationOptions.PublicationType = useSFU ? .SFU : .P2P
        
        // Publish audio stream
        if let audioStream = localAudioStream {
            let audioOptions = RoomPublicationOptions()
            audioOptions.type = publicationType
            self.audioPublication = try await member.publish(audioStream, options: audioOptions)
        }
        
        // Publish video stream
        if let videoStream = localVideoStream {
            let videoOptions = RoomPublicationOptions()
            videoOptions.type = publicationType
            self.videoPublication = try await member.publish(videoStream, options: videoOptions)
        }
        
        // Publish data stream (P2P Only as per limitation)
        if !useSFU, let dataStream = localDataStream {
            let dataOptions = RoomPublicationOptions()
            dataOptions.type = .P2P // Explicitly P2P
            self.dataPublication = try await member.publish(dataStream, options: dataOptions)
        }
    }
    
    // MARK: - Data Stream Methods
    
    public func sendData(_ data: String) async throws {
        guard let dataStream = localDataStream else {
             throw SkyWayError.streamNotCreated
        }
        try await dataStream.write(data)
    }
    
    public func sendData(_ data: Data) async throws {
        guard let dataStream = localDataStream else {
             throw SkyWayError.streamNotCreated
        }
        try await dataStream.write(data)
    }
    
    /// Publish only audio stream
    public func publishAudio(useSFU: Bool = false) async throws {
        guard let member = localMember else {
            throw SkyWayError.memberNotJoined
        }
        guard let audioStream = localAudioStream else {
            throw SkyWayError.streamNotCreated
        }
        
        let audioOptions = RoomPublicationOptions()
        audioOptions.type = useSFU ? .SFU : .P2P
        self.audioPublication = try await member.publish(audioStream, options: audioOptions)
    }
    
    /// Publish only video stream
    public func publishVideo(useSFU: Bool = false) async throws {
        guard let member = localMember else {
            throw SkyWayError.memberNotJoined
        }
        guard let videoStream = localVideoStream else {
            throw SkyWayError.streamNotCreated
        }
        
        let videoOptions = RoomPublicationOptions()
        videoOptions.type = useSFU ? .SFU : .P2P
        self.videoPublication = try await member.publish(videoStream, options: videoOptions)
    }
    
    // MARK: - Subscribing
    
    /// Subscribe to a publication by ID
    @discardableResult
    public func subscribe(publicationId: String) async throws -> RoomSubscription {
        guard let member = localMember else {
            throw SkyWayError.memberNotJoined
        }
        
        let subscription = try await member.subscribe(publicationId: publicationId, options: nil)
        subscriptions[publicationId] = subscription
        
        // Setup handlers for data streams
        setupSubscriptionEventHandlers(subscription: subscription)
        
        // Add the stream to remote streams
        if let stream = subscription.stream {
            await MainActor.run {
                self.remoteStreams.append(stream)
            }
        }
        
        return subscription
    }
    
    private func setupSubscriptionEventHandlers(subscription: RoomSubscription) {
        if let dataStream = subscription.stream as? RemoteDataStream {
             dataStream.onStringReceivedHandler = { [weak self] string, time in
                 guard let self = self, let publisher = subscription.publication.publisher else { return }
                 if let data = string.data(using: .utf8) {
                     Task { @MainActor in
                         self.lastReceivedMessage = "\(publisher.name ?? "Unknown"): \(string)"
                         self.delegate?.roomManager(self, didReceiveData: data, from: publisher)
                     }
                 }
             }
             
            dataStream.onDataReceivedHandler = { [weak self] data, time in
                guard let self = self, let publisher = subscription.publication.publisher else { return }
                Task { @MainActor in
                    if let string = String(data: data, encoding: .utf8) {
                        self.lastReceivedMessage = "\(publisher.name ?? "Unknown"): \(string)"
                    }
                    self.delegate?.roomManager(self, didReceiveData: data, from: publisher)
                }
            }
        }
    }
    
    /// Unsubscribe from a publication
    public func unsubscribe(publicationId: String) async throws {
        guard let subscription = subscriptions[publicationId] else {
            return
        }
        
        try await subscription.cancel()
        subscriptions.removeValue(forKey: publicationId)
        
        // Remove the stream from remote streams
        if let stream = subscription.stream {
            await MainActor.run {
                self.remoteStreams.removeAll { $0.id == stream.id }
            }
        }
    }
    
    /// Subscribe to all remote publications
    public func subscribeToAllRemotePublications() async throws {
        let publications = getRemotePublications()
        for publication in publications {
            // Skip if already subscribed
            guard subscriptions[publication.id] == nil else { continue }
            try await subscribe(publicationId: publication.id)
        }
    }
    
    // MARK: - Remote Video Attachment
    
    /// Attach a remote video stream to a view
    public func attachRemoteVideo(subscription: RoomSubscription, to view: VideoView) {
        guard let remoteStream = subscription.stream as? RemoteVideoStream else {
            return
        }
        remoteStream.attach(view)
    }
    
    /// Attach a remote video stream to a view by publication ID
    public func attachRemoteVideo(publicationId: String, to view: VideoView) {
        guard let subscription = subscriptions[publicationId],
              let remoteStream = subscription.stream as? RemoteVideoStream else {
            return
        }
        remoteStream.attach(view)
    }
    
    /// Detach a remote video stream from a view
    public func detachRemoteVideo(subscription: RoomSubscription, from view: VideoView) {
        guard let remoteStream = subscription.stream as? RemoteVideoStream else {
            return
        }
        remoteStream.detach(view)
    }
    
    // MARK: - Utility Methods
    
    /// Get all remote publications (excluding our own)
    public func getRemotePublications() -> [RoomPublication] {
        guard let room = room, let localMember = localMember else {
            return []
        }
        return room.publications.filter { $0.publisher?.id != localMember.id }
    }
    
    /// Get subscription for a publication ID
    public func getSubscription(for publicationId: String) -> RoomSubscription? {
        return subscriptions[publicationId]
    }
    
    // MARK: - Private Methods
    
    private func setupRoomEventHandlers(for room: Room) {
        // Handle new publications
        room.onPublicationListChangedHandler = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateRemotePublications()
            }
        }
        
        // Handle member changes
        room.onMemberListChangedHandler = { [weak self] in
            guard let self = self else { return }
            // Notify delegate about member changes if needed
            Task { @MainActor in
                self.updateRemotePublications()
            }
        }
        
        // Handle subscription list changes
        room.onSubscriptionListChangedHandler = { [weak self] in
            guard let self = self else { return }
            // Handle subscription changes if needed
            _ = self
        }
    }
    
    @MainActor
    private func updateRemotePublications() {
        let newPublications = getRemotePublications()
        
        // Find new publications
        let existingIds = Set(remotePublications.map { $0.id })
        let newIds = Set(newPublications.map { $0.id })
        
        // Publications to subscribe to (new ones)
        let publicationsToSubscribe = newPublications.filter { !existingIds.contains($0.id) }
        
        // Notify about new publications
        for publication in publicationsToSubscribe {
            delegate?.roomManager(self, didReceiveRemotePublication: publication)
            
            // Auto-subscribe
            Task {
                try? await self.subscribe(publicationId: publication.id)
            }
        }
        
        // Notify about removed publications
        for publication in remotePublications where !newIds.contains(publication.id) {
            delegate?.roomManager(self, didRemoveRemotePublication: publication)
        }
        
        self.remotePublications = newPublications
    }
}

// MARK: - Error Types

public enum SkyWayError: Error, LocalizedError {
    case contextNotSetup
    case cameraNotFound
    case memberNotJoined
    case streamNotCreated
    case subscriptionFailed
    case roomNotJoined
    
    public var errorDescription: String? {
        switch self {
        case .contextNotSetup:
            return "SkyWay context has not been set up. Call setup() first."
        case .cameraNotFound:
            return "No supported camera found on this device."
        case .memberNotJoined:
            return "Not joined to a room. Call join() first."
        case .streamNotCreated:
            return "Local stream not created. Call createLocalStreams() first."
        case .subscriptionFailed:
            return "Failed to subscribe to the publication."
        case .roomNotJoined:
            return "Not currently in a room."
        }
    }
}
