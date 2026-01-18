//
//  ContentView.swift
//  SkyWayRoom
//
//  Created by raven on 1/14/26.
//

import SwiftUI


// MARK: - Constants
private let SkyWayAppID = ""
private let SkyWaySecret = ""

struct ContentView: View {
    @StateObject private var roomManager = RoomManager.shared
    
    @State private var roomName: String = "test_room"
    @State private var memberName: String = "user_\(Int.random(in: 100...999))"
    @State private var messageText: String = ""
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            if roomManager.isJoined {
                MainRoomView
            } else {
                JoinView
            }
        }
        .alert(isPresented: $showingError) {
            Alert(title: Text("Error"), message: Text(errorMessage ?? "Unknown error"), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            setupSkyWay()
        }
    }
    
    // MARK: - Views
    
    private var JoinView: some View {
        VStack(spacing: 20) {
            Text("SkyWay Room")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                TextField("Room Name", text: $roomName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                
                TextField("Member Name", text: $memberName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                
                Button(action: joinRoom) {
                    Text("Join Room (P2P)")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding(30)
            .background(Color(.systemGray6))
            .cornerRadius(15)
            .padding(.horizontal)
            
            // Local Preview in Join Screen
            VStack {
                Text("Camera Preview")
                    .foregroundColor(.gray)
                SkyWayLocalVideoView()
                    .frame(height: 200)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray, lineWidth: 1)
                    )
            }
            .padding()
        }
    }
    
    private var MainRoomView: some View {
        VStack {
            // Header
            HStack {
                Text("Room: \(roomName)")
                    .foregroundColor(.white)
                    .font(.headline)
                Spacer()
                Button("Leave", action: leaveRoom)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding()
            
            // Remote Videos Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(roomManager.remotePublications.filter { $0.contentType == .video }, id: \.id) { publication in
                        VStack {
                            SkyWayRemoteVideoView(publicationId: publication.id)
                                .aspectRatio(9/16, contentMode: .fit)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(8)
                            
                            Text(publication.publisher?.name ?? "Unknown")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                    }
                }
                .padding()
            }
            
            Spacer()
            
            // Received Messages Area
            if !roomManager.lastReceivedMessage.isEmpty {
                HStack {
                    Text(roomManager.lastReceivedMessage)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    Spacer()
                }
                .padding(.horizontal)
                .transition(.opacity)
            }
            
            // Controls & Input
            VStack(spacing: 12) {
                // Message Input
                HStack {
                    TextField("Message", text: $messageText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                
                // Media Controls
                HStack(spacing: 30) {
                    Button(action: { /* Toggle Mute */ }) {
                        Image(systemName: "mic.fill") // Placeholder state
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.gray.opacity(0.5)))
                    }
                    
                    Button(action: { /* Toggle Camera */ }) {
                        Image(systemName: "video.fill") // Placeholder state
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.gray.opacity(0.5)))
                    }
                }
            }
            .padding(.bottom)
        }
        .overlay(
            // Local Video Floating PIP
            GeometryReader { geometry in
                SkyWayLocalVideoView()
                    .frame(width: 100, height: 160)
                    .cornerRadius(8)
                    .shadow(radius: 5)
                    .position(x: geometry.size.width - 60, y: geometry.size.height - 150)
            }
        )
    }
    
    // MARK: - Actions
    
    private func setupSkyWay() {
        Task {
            do {
                // Setup Context with AppID/Secret for dev
                try await roomManager.setupForDev(appId: SkyWayAppID, secretKey: SkyWaySecret)
                
                // Setup Camera
                try await roomManager.setupCamera()
                
                // Create local streams
                roomManager.createLocalStreams()
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                }
            }
        }
    }
    
    private func joinRoom() {
        Task {
            do {
                // Join (P2P mode to support DataStream)
                try await roomManager.join(roomName: roomName, memberName: memberName, mode: .p2p)
                
                // Publish Audio/Video/Data
                try await roomManager.publish(useSFU: false)
                
                // Subscribe to all existing remote pubs
                try await roomManager.subscribeToAllRemotePublications()
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                }
            }
        }
    }
    
    private func leaveRoom() {
        Task {
            await roomManager.leave()
            // Re-setup camera/streams for next join if needed, or just stay idle
            // ideally we might want to restart camera preview
            try? await roomManager.setupCamera()
            roomManager.createLocalStreams()
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        Task {
            do {
                try await roomManager.sendData(messageText)
                // Clear text
                await MainActor.run {
                    self.messageText = ""
                }
            } catch {
                print("Failed to send message: \(error)")
            }
        }
    }
}


#Preview {
    ContentView()
}
