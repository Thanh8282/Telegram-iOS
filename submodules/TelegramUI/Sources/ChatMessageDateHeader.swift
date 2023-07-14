import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import AvatarNode
import TelegramCore
import TelegramUniversalVideoContent
import UniversalMediaPlayer
import GalleryUI
import HierarchyTrackingLayer
import WallpaperBackgroundNode
import ChatControllerInteraction
import AvatarVideoNode

private let timezoneOffset: Int32 = {
    let nowTimestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
    var now: time_t = time_t(nowTimestamp)
    var timeinfoNow: tm = tm()
    localtime_r(&now, &timeinfoNow)
    return Int32(timeinfoNow.tm_gmtoff)
}()

private let granularity: Int32 = 60 * 60 * 24

final class ChatMessageDateHeader: ListViewItemHeader {
    private let timestamp: Int32
    private let roundedTimestamp: Int32
    private let scheduled: Bool
    
    let id: ListViewItemNode.HeaderId
    let presentationData: ChatPresentationData
    let controllerInteraction: ChatControllerInteraction?
    let context: AccountContext
    let action: ((Int32, Bool) -> Void)?
    
    init(timestamp: Int32, scheduled: Bool, presentationData: ChatPresentationData, controllerInteraction: ChatControllerInteraction?, context: AccountContext, action: ((Int32, Bool) -> Void)? = nil) {
        self.timestamp = timestamp
        self.scheduled = scheduled
        self.presentationData = presentationData
        self.controllerInteraction = controllerInteraction
        self.context = context
        self.action = action
        self.roundedTimestamp = dateHeaderTimestampId(timestamp: timestamp)
        self.id = ListViewItemNode.HeaderId(space: 0, id: Int64(self.roundedTimestamp))
    }
    
    let stickDirection: ListViewItemHeaderStickDirection = .bottom
    let stickOverInsets: Bool = true
    
    let height: CGFloat = 34.0

    public func combinesWith(other: ListViewItemHeader) -> Bool {
        if let other = other as? ChatMessageDateHeader, other.id == self.id {
            return true
        } else {
            return false
        }
    }
    
    func node(synchronousLoad: Bool) -> ListViewItemHeaderNode {
        return ChatMessageDateHeaderNode(localTimestamp: self.roundedTimestamp, scheduled: self.scheduled, presentationData: self.presentationData, controllerInteraction: self.controllerInteraction, context: self.context, action: self.action)
    }
    
    func updateNode(_ node: ListViewItemHeaderNode, previous: ListViewItemHeader?, next: ListViewItemHeader?) {
        guard let node = node as? ChatMessageDateHeaderNode, let next = next as? ChatMessageDateHeader else {
            return
        }
        node.updatePresentationData(next.presentationData, context: next.context)
    }
}

private func monthAtIndex(_ index: Int, strings: PresentationStrings) -> String {
    switch index {
        case 0:
            return strings.Month_GenJanuary
        case 1:
            return strings.Month_GenFebruary
        case 2:
            return strings.Month_GenMarch
        case 3:
            return strings.Month_GenApril
        case 4:
            return strings.Month_GenMay
        case 5:
            return strings.Month_GenJune
        case 6:
            return strings.Month_GenJuly
        case 7:
            return strings.Month_GenAugust
        case 8:
            return strings.Month_GenSeptember
        case 9:
            return strings.Month_GenOctober
        case 10:
            return strings.Month_GenNovember
        case 11:
            return strings.Month_GenDecember
        default:
            return ""
    }
}

private func dateHeaderTimestampId(timestamp: Int32) -> Int32 {
    if timestamp == scheduleWhenOnlineTimestamp {
        return timestamp
    } else if timestamp == Int32.max {
        return timestamp / (granularity) * (granularity)
    } else {
        return ((timestamp + timezoneOffset) / (granularity)) * (granularity)
    }
}

final class ChatMessageDateHeaderNode: ListViewItemHeaderNode {
    let labelNode: TextNode
    let backgroundNode: NavigationBackgroundNode
    let stickBackgroundNode: ASImageNode
    
    private var backgroundContent: WallpaperBubbleBackgroundNode?
    
    private let localTimestamp: Int32
    private var presentationData: ChatPresentationData
    private let controllerInteraction: ChatControllerInteraction?
    private let context: AccountContext
    private let text: String
    
    private var flashingOnScrolling = false
    private var stickDistanceFactor: CGFloat = 0.0
    private var action: ((Int32, Bool) -> Void)? = nil
    
    private var absolutePosition: (CGRect, CGSize)?
    
    init(localTimestamp: Int32, scheduled: Bool, presentationData: ChatPresentationData, controllerInteraction: ChatControllerInteraction?, context: AccountContext, action: ((Int32, Bool) -> Void)? = nil) {
        self.presentationData = presentationData
        self.controllerInteraction = controllerInteraction
        self.context = context
        
        self.localTimestamp = localTimestamp
        self.action = action
        
        self.labelNode = TextNode()
        self.labelNode.isUserInteractionEnabled = false
        self.labelNode.displaysAsynchronously = !presentationData.isPreview
        
        if controllerInteraction?.presentationContext.backgroundNode?.hasExtraBubbleBackground() == true, let backgroundContent = controllerInteraction?.presentationContext.backgroundNode?.makeBubbleBackground(for: .free) {
            backgroundContent.clipsToBounds = true
            self.backgroundContent = backgroundContent
        }
                
        self.backgroundNode = NavigationBackgroundNode(color: .clear)
        self.backgroundNode.isUserInteractionEnabled = false
        
        self.stickBackgroundNode = ASImageNode()
        self.stickBackgroundNode.isLayerBacked = true
        self.stickBackgroundNode.displayWithoutProcessing = true
        self.stickBackgroundNode.displaysAsynchronously = false
        
        let nowTimestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        
        var t: time_t = time_t(localTimestamp)
        var timeinfo: tm = tm()
        gmtime_r(&t, &timeinfo)
        
        var now: time_t = time_t(nowTimestamp)
        var timeinfoNow: tm = tm()
        localtime_r(&now, &timeinfoNow)
        
        var text: String
        if timeinfo.tm_year == timeinfoNow.tm_year {
            if timeinfo.tm_yday == timeinfoNow.tm_yday {
                text = presentationData.strings.Weekday_Today
            } else {
                text = presentationData.strings.Date_ChatDateHeader(monthAtIndex(Int(timeinfo.tm_mon), strings: presentationData.strings), "\(timeinfo.tm_mday)").string
            }
        } else {
            text = presentationData.strings.Date_ChatDateHeaderYear(monthAtIndex(Int(timeinfo.tm_mon), strings: presentationData.strings), "\(timeinfo.tm_mday)", "\(1900 + timeinfo.tm_year)").string
        }
        
        if scheduled {
            if localTimestamp == scheduleWhenOnlineTimestamp {
                text = presentationData.strings.ScheduledMessages_ScheduledOnline
            } else if timeinfo.tm_year == timeinfoNow.tm_year && timeinfo.tm_yday == timeinfoNow.tm_yday {
                text = presentationData.strings.ScheduledMessages_ScheduledToday
            } else {
                text = presentationData.strings.ScheduledMessages_ScheduledDate(text).string
            }
        }
        self.text = text
        
        super.init(layerBacked: false, dynamicBounce: true, isRotated: true, seeThrough: false)
        
        self.transform = CATransform3DMakeRotation(CGFloat.pi, 0.0, 0.0, 1.0)
        
        let graphics = PresentationResourcesChat.principalGraphics(theme: presentationData.theme.theme, wallpaper: presentationData.theme.wallpaper, bubbleCorners: presentationData.chatBubbleCorners)

        let fullTranslucency: Bool = controllerInteraction?.enableFullTranslucency ?? true
        
        self.backgroundNode.updateColor(color: selectDateFillStaticColor(theme: presentationData.theme.theme, wallpaper: presentationData.theme.wallpaper), enableBlur: fullTranslucency && dateFillNeedsBlur(theme: presentationData.theme.theme, wallpaper: presentationData.theme.wallpaper), transition: .immediate)
        self.stickBackgroundNode.image = graphics.dateFloatingBackground
        self.stickBackgroundNode.alpha = 0.0

        if let backgroundContent = self.backgroundContent {
            self.addSubnode(backgroundContent)
        } else {
            self.addSubnode(self.backgroundNode)
        }
        self.addSubnode(self.labelNode)
                
        let titleFont = Font.medium(min(18.0, floor(presentationData.fontSize.baseDisplaySize * 13.0 / 17.0)))
        
        let attributedString = NSAttributedString(string: text, font: titleFont, textColor: bubbleVariableColor(variableColor: presentationData.theme.theme.chat.serviceMessage.dateTextColor, wallpaper: presentationData.theme.wallpaper))
        let labelLayout = TextNode.asyncLayout(self.labelNode)
                
        let (size, apply) = labelLayout(TextNodeLayoutArguments(attributedString: attributedString, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: 320.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
        let _ = apply()
        self.labelNode.frame = CGRect(origin: CGPoint(), size: size.size)
    }

    override func didLoad() {
        super.didLoad()
        
        self.view.addGestureRecognizer(ListViewTapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
    }
    
    func updatePresentationData(_ presentationData: ChatPresentationData, context: AccountContext) {
        let previousPresentationData = self.presentationData
        self.presentationData = presentationData
        
        let graphics = PresentationResourcesChat.principalGraphics(theme: presentationData.theme.theme, wallpaper: presentationData.theme.wallpaper, bubbleCorners: presentationData.chatBubbleCorners)
        
        let fullTranslucency: Bool = self.controllerInteraction?.enableFullTranslucency ?? true

        self.backgroundNode.updateColor(color: selectDateFillStaticColor(theme: presentationData.theme.theme, wallpaper: presentationData.theme.wallpaper), enableBlur: fullTranslucency && dateFillNeedsBlur(theme: presentationData.theme.theme, wallpaper: presentationData.theme.wallpaper), transition: .immediate)
        self.stickBackgroundNode.image = graphics.dateFloatingBackground
        
        let titleFont = Font.medium(min(18.0, floor(presentationData.fontSize.baseDisplaySize * 13.0 / 17.0)))
        
        let attributedString = NSAttributedString(string: self.text, font: titleFont, textColor: bubbleVariableColor(variableColor: presentationData.theme.theme.chat.serviceMessage.dateTextColor, wallpaper: presentationData.theme.wallpaper))
        let labelLayout = TextNode.asyncLayout(self.labelNode)
        
        let (size, apply) = labelLayout(TextNodeLayoutArguments(attributedString: attributedString, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: 320.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
        let _ = apply()
        
        if presentationData.fontSize != previousPresentationData.fontSize {
            self.labelNode.bounds = CGRect(origin: CGPoint(), size: size.size)
        }

        self.setNeedsLayout()
    }
    
    func updateBackgroundColor(color: UIColor, enableBlur: Bool) {
        self.backgroundNode.updateColor(color: color, enableBlur: enableBlur, transition: .immediate)
    }
    
    override func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {
        self.absolutePosition = (rect, containerSize)
        if let backgroundContent = self.backgroundContent {
            var backgroundFrame = backgroundContent.frame
            backgroundFrame.origin.x += rect.minX
            backgroundFrame.origin.y += containerSize.height - rect.minY
            backgroundContent.update(rect: backgroundFrame, within: containerSize, transition: .immediate)
        }
    }
    
    override func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat) {
        let chatDateSize: CGFloat = 20.0
        let chatDateInset: CGFloat = 6.0
        
        let labelSize = self.labelNode.bounds.size
        let backgroundSize = CGSize(width: labelSize.width + chatDateInset * 2.0, height: chatDateSize)
        
        let backgroundFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - backgroundSize.width) / 2.0), y: (34.0 - chatDateSize) / 2.0), size: backgroundSize)
        self.stickBackgroundNode.frame = CGRect(origin: CGPoint(), size: backgroundFrame.size)
        self.backgroundNode.frame = backgroundFrame
        self.backgroundNode.update(size: backgroundFrame.size, cornerRadius: backgroundFrame.size.height / 2.0, transition: .immediate)
        self.labelNode.frame = CGRect(origin: CGPoint(x: backgroundFrame.origin.x + chatDateInset, y: backgroundFrame.origin.y + floorToScreenPixels((backgroundSize.height - labelSize.height) / 2.0)), size: labelSize)
                
        if let backgroundContent = self.backgroundContent {
            backgroundContent.allowsGroupOpacity = true
            self.backgroundNode.isHidden = true
            backgroundContent.frame = self.backgroundNode.frame
            backgroundContent.cornerRadius = backgroundFrame.size.height / 2.0
            
            if let (rect, containerSize) = self.absolutePosition {
                var backgroundFrame = backgroundContent.frame
                backgroundFrame.origin.x += rect.minX
                backgroundFrame.origin.y += containerSize.height - rect.minY
                backgroundContent.update(rect: backgroundFrame, within: containerSize, transition: .immediate)
            }
        }
    }
    
    override func updateStickDistanceFactor(_ factor: CGFloat, transition: ContainedViewLayoutTransition) {
        if !self.stickDistanceFactor.isEqual(to: factor) {
            self.stickBackgroundNode.alpha = factor
            
            let wasZero = self.stickDistanceFactor < 0.5
            let isZero = factor < 0.5
            self.stickDistanceFactor = factor
            
            if wasZero != isZero {
                var animated = true
                if case .immediate = transition {
                    animated = false
                }
                self.updateFlashing(animated: animated)
            }
        }
    }
    
    override func updateFlashingOnScrolling(_ isFlashingOnScrolling: Bool, animated: Bool) {
        self.flashingOnScrolling = isFlashingOnScrolling
        self.updateFlashing(animated: animated)
    }
    
    private func updateFlashing(animated: Bool) {
        let flashing = self.flashingOnScrolling || self.stickDistanceFactor < 0.5
        
        let alpha: CGFloat = flashing ? 1.0 : 0.0
        let previousAlpha = self.backgroundNode.alpha
        
        if !previousAlpha.isEqual(to: alpha) {
            self.backgroundContent?.alpha = alpha
            self.backgroundNode.alpha = alpha
            self.labelNode.alpha = alpha
            if animated {
                let duration: Double = flashing ? 0.3 : 0.4
                self.backgroundContent?.layer.animateAlpha(from: previousAlpha, to: alpha, duration: duration)
                self.backgroundNode.layer.animateAlpha(from: previousAlpha, to: alpha, duration: duration)
                self.labelNode.layer.animateAlpha(from: previousAlpha, to: alpha, duration: duration)
            }
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !self.bounds.contains(point) {
            return nil
        }
        if self.labelNode.alpha.isZero {
            return nil
        }
        if self.backgroundNode.frame.contains(point) {
            return self.view
        }
        return nil
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
    }
    
    @objc func tapGesture(_ recognizer: ListViewTapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.action?(self.localTimestamp, self.stickDistanceFactor < 0.5)
        }
    }
}

final class ChatMessageAvatarHeader: ListViewItemHeader {
    struct Id: Hashable {
        var peerId: PeerId
        var timestampId: Int32
    }

    let id: ListViewItemNode.HeaderId
    let peerId: PeerId
    let peer: Peer?
    let messageReference: MessageReference?
    let adMessageId: EngineMessage.Id?
    let effectiveTimestamp: Int32
    let presentationData: ChatPresentationData
    let context: AccountContext
    let controllerInteraction: ChatControllerInteraction
    let storyStats: PeerStoryStats?

    init(timestamp: Int32, peerId: PeerId, peer: Peer?, messageReference: MessageReference?, message: Message, presentationData: ChatPresentationData, context: AccountContext, controllerInteraction: ChatControllerInteraction, storyStats: PeerStoryStats?) {
        self.peerId = peerId
        self.peer = peer
        self.messageReference = messageReference
        if message.adAttribute != nil {
            self.adMessageId = message.id
        } else {
            self.adMessageId = nil
        }

        var effectiveTimestamp = message.timestamp
        if let forwardInfo = message.forwardInfo, forwardInfo.flags.contains(.isImported) {
            effectiveTimestamp = forwardInfo.date
        }
        self.effectiveTimestamp = effectiveTimestamp

        self.presentationData = presentationData
        self.context = context
        self.controllerInteraction = controllerInteraction
        self.id = ListViewItemNode.HeaderId(space: 1, id: Id(peerId: peerId, timestampId: dateHeaderTimestampId(timestamp: timestamp)))
        self.storyStats = storyStats
    }
    
    let stickDirection: ListViewItemHeaderStickDirection = .top
    let stickOverInsets: Bool = false

    let height: CGFloat = 38.0

    public func combinesWith(other: ListViewItemHeader) -> Bool {
        if let other = other as? ChatMessageAvatarHeader, other.id == self.id {
            if abs(self.effectiveTimestamp - other.effectiveTimestamp) >= 10 * 60 {
                return false
            }
            return true
        } else {
            return false
        }
    }

    func node(synchronousLoad: Bool) -> ListViewItemHeaderNode {
        return ChatMessageAvatarHeaderNode(peerId: self.peerId, peer: self.peer, messageReference: self.messageReference, adMessageId: self.adMessageId, presentationData: self.presentationData, context: self.context, controllerInteraction: self.controllerInteraction, storyStats: self.storyStats, synchronousLoad: synchronousLoad)
    }

    func updateNode(_ node: ListViewItemHeaderNode, previous: ListViewItemHeader?, next: ListViewItemHeader?) {
        guard let node = node as? ChatMessageAvatarHeaderNode else {
            return
        }
        node.updatePresentationData(self.presentationData, context: self.context)
        node.updateStoryStats(storyStats: self.storyStats, theme: self.presentationData.theme.theme, force: false)
    }
}

private let avatarFont = avatarPlaceholderFont(size: 16.0)

private let maxVideoLoopCount = 3

final class ChatMessageAvatarHeaderNode: ListViewItemHeaderNode {
    private let context: AccountContext
    private var presentationData: ChatPresentationData
    private let controllerInteraction: ChatControllerInteraction
    private var storyStats: PeerStoryStats?
    
    private let peerId: PeerId
    private let messageReference: MessageReference?
    private let peer: Peer?
    private let adMessageId: EngineMessage.Id?

    private let containerNode: ContextControllerSourceNode
    let avatarNode: AvatarNode
    private var avatarVideoNode: AvatarVideoNode?
        
    private var cachedDataDisposable = MetaDisposable()
    private var hierarchyTrackingLayer: HierarchyTrackingLayer?
    
    private var trackingIsInHierarchy: Bool = false {
        didSet {
            if self.trackingIsInHierarchy != oldValue {
                Queue.mainQueue().justDispatch {
                    if self.trackingIsInHierarchy {
                        self.avatarVideoNode?.resetPlayback()
                    }
                    self.updateVideoVisibility()
                }
            }
        }
    }
    
    init(peerId: PeerId, peer: Peer?, messageReference: MessageReference?, adMessageId: EngineMessage.Id?, presentationData: ChatPresentationData, context: AccountContext, controllerInteraction: ChatControllerInteraction, storyStats: PeerStoryStats?, synchronousLoad: Bool) {
        self.peerId = peerId
        self.peer = peer
        self.messageReference = messageReference
        self.adMessageId = adMessageId
        self.presentationData = presentationData
        self.context = context
        self.controllerInteraction = controllerInteraction
        self.storyStats = storyStats

        self.containerNode = ContextControllerSourceNode()

        self.avatarNode = AvatarNode(font: avatarFont)

        super.init(layerBacked: false, dynamicBounce: true, isRotated: true, seeThrough: false)

        self.transform = CATransform3DMakeRotation(CGFloat.pi, 0.0, 0.0, 1.0)

        self.addSubnode(self.containerNode)
        self.containerNode.addSubnode(self.avatarNode)

        if let peer = peer {
            self.setPeer(context: context, theme: presentationData.theme.theme, synchronousLoad: synchronousLoad, peer: peer, authorOfMessage: messageReference, emptyColor: .black)
        }
        
        if let storyStats {
            self.updateStoryStats(storyStats: storyStats, theme: presentationData.theme.theme, force: true)
        }

        self.containerNode.activated = { [weak self] gesture, _ in
            guard let strongSelf = self, let peer = strongSelf.peer else {
                return
            }
            var messageId: MessageId?
            if let messageReference = messageReference, case let .message(_, _, id, _, _, _) = messageReference.content {
                messageId = id
            }
            strongSelf.controllerInteraction.openPeerContextMenu(peer, messageId, strongSelf.containerNode, strongSelf.containerNode.bounds, gesture)
        }

        self.updateSelectionState(animated: false)
    }
    
    deinit {
        self.cachedDataDisposable.dispose()
    }

    func setCustomLetters(context: AccountContext, theme: PresentationTheme, synchronousLoad: Bool, letters: [String], emptyColor: UIColor) {
        self.containerNode.isGestureEnabled = false

        self.avatarNode.setCustomLetters(letters, icon: !letters.isEmpty ? nil : .phone)
    }

    func setPeer(context: AccountContext, theme: PresentationTheme, synchronousLoad: Bool, peer: Peer, authorOfMessage: MessageReference?, emptyColor: UIColor) {
        self.containerNode.isGestureEnabled = peer.smallProfileImage != nil

        var overrideImage: AvatarNodeImageOverride?
        if peer.isDeleted {
            overrideImage = .deletedIcon
        }
        self.avatarNode.setPeer(context: context, theme: theme, peer: EnginePeer(peer), authorOfMessage: authorOfMessage, overrideImage: overrideImage, emptyColor: emptyColor, synchronousLoad: synchronousLoad, displayDimensions: CGSize(width: 38.0, height: 38.0))
        
        if peer.isPremium && context.sharedContext.energyUsageSettings.autoplayVideo {
            self.cachedDataDisposable.set((context.account.postbox.peerView(id: peer.id)
            |> deliverOnMainQueue).start(next: { [weak self] peerView in
                guard let strongSelf = self else {
                    return
                }
                
                let cachedPeerData = peerView.cachedData as? CachedUserData
                var personalPhoto: TelegramMediaImage?
                var profilePhoto: TelegramMediaImage?
                var isKnown = false
                
                if let cachedPeerData = cachedPeerData {
                    if case let .known(maybePersonalPhoto) = cachedPeerData.personalPhoto {
                        personalPhoto = maybePersonalPhoto
                        isKnown = true
                    }
                    if case let .known(maybePhoto) = cachedPeerData.photo {
                        profilePhoto = maybePhoto
                        isKnown = true
                    }
                }
                
                if isKnown {
                    let photo = personalPhoto ?? profilePhoto
                    if let photo = photo, !photo.videoRepresentations.isEmpty || photo.emojiMarkup != nil {
                        let videoNode: AvatarVideoNode
                        if let current = strongSelf.avatarVideoNode {
                            videoNode = current
                        } else {
                            videoNode = AvatarVideoNode(context: context)
                            strongSelf.avatarNode.contentNode.addSubnode(videoNode)
                            strongSelf.avatarVideoNode = videoNode
                        }
                        videoNode.update(peer: EnginePeer(peer), photo: photo, size: CGSize(width: 38.0, height: 38.0))
                        
                        if strongSelf.hierarchyTrackingLayer == nil {
                            let hierarchyTrackingLayer = HierarchyTrackingLayer()
                            hierarchyTrackingLayer.didEnterHierarchy = { [weak self] in
                                guard let strongSelf = self else {
                                    return
                                }
                                strongSelf.trackingIsInHierarchy = true
                            }
                            
                            hierarchyTrackingLayer.didExitHierarchy = { [weak self] in
                                guard let strongSelf = self else {
                                    return
                                }
                                strongSelf.trackingIsInHierarchy = false
                            }
                            strongSelf.hierarchyTrackingLayer = hierarchyTrackingLayer
                            strongSelf.layer.addSublayer(hierarchyTrackingLayer)
                        }
                    } else {
                        if let avatarVideoNode = strongSelf.avatarVideoNode {
                            avatarVideoNode.removeFromSupernode()
                            strongSelf.avatarVideoNode = nil
                        }
                        strongSelf.hierarchyTrackingLayer?.removeFromSuperlayer()
                        strongSelf.hierarchyTrackingLayer = nil
                    }
                    strongSelf.updateVideoVisibility()
                } else {
                    if let photo = peer.largeProfileImage, photo.hasVideo {
                        let _ = context.engine.peers.fetchAndUpdateCachedPeerData(peerId: peer.id).start()
                    }
                }
            }))
        } else {            
            self.cachedDataDisposable.set(nil)
            
            self.avatarVideoNode?.removeFromSupernode()
            self.avatarVideoNode = nil
            
            self.hierarchyTrackingLayer?.removeFromSuperlayer()
            self.hierarchyTrackingLayer = nil
        }
    }
    
    func updateStoryStats(storyStats: PeerStoryStats?, theme: PresentationTheme, force: Bool) {
        if self.storyStats != storyStats || self.presentationData.theme.theme !== theme || force {
            self.avatarNode.setStoryStats(storyStats: storyStats.flatMap { storyStats in
                return AvatarNode.StoryStats(
                    totalCount: storyStats.totalCount != 0 ? 1 : 0,
                    unseenCount: storyStats.unseenCount != 0 ? 1 : 0,
                    hasUnseenCloseFriendsItems: storyStats.hasUnseenCloseFriends
                )
            }, presentationParams: AvatarNode.StoryPresentationParams(
                colors: AvatarNode.Colors(theme: theme),
                lineWidth: 2.0,
                inactiveLineWidth: 2.0
            ), transition: .immediate)
        }
    }

    override func didLoad() {
        super.didLoad()

        self.avatarNode.view.addGestureRecognizer(ListViewTapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
    }

    func updatePresentationData(_ presentationData: ChatPresentationData, context: AccountContext) {
        if self.presentationData !== presentationData {
            self.presentationData = presentationData
            self.setNeedsLayout()
        }
    }

    override func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat) {
        self.containerNode.frame = CGRect(origin: CGPoint(x: leftInset + 3.0, y: 0.0), size: CGSize(width: 38.0, height: 38.0))
        self.avatarNode.frame = CGRect(origin: CGPoint(), size: CGSize(width: 38.0, height: 38.0))
    }

    override func animateRemoved(duration: Double) {
        self.alpha = 0.0
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false)
        self.avatarNode.layer.animateScale(from: 1.0, to: 0.2, duration: duration, removeOnCompletion: false)
    }

    override func animateAdded(duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: self.alpha, duration: 0.2)
        self.avatarNode.layer.animateScale(from: 0.2, to: 1.0, duration: 0.2)
    }

    override func updateStickDistanceFactor(_ factor: CGFloat, transition: ContainedViewLayoutTransition) {
    }

    override func updateFlashingOnScrolling(_ isFlashingOnScrolling: Bool, animated: Bool) {
    }

    func updateSelectionState(animated: Bool) {
        let offset: CGFloat = self.controllerInteraction.selectionState != nil ? 42.0 : 0.0

        let previousSubnodeTransform = self.subnodeTransform
        self.subnodeTransform = CATransform3DMakeTranslation(offset, 0.0, 0.0);
        if animated {
            self.layer.animate(from: NSValue(caTransform3D: previousSubnodeTransform), to: NSValue(caTransform3D: self.subnodeTransform), keyPath: "sublayerTransform", timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, duration: 0.2)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !self.bounds.contains(point) {
            return nil
        }
        let result = self.containerNode.view.hitTest(self.view.convert(point, to: self.containerNode.view), with: event)
        return result
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
    }

    @objc func tapGesture(_ recognizer: ListViewTapGestureRecognizer) {
        if case .ended = recognizer.state {
            if self.peerId.namespace == Namespaces.Peer.Empty, case let .message(_, _, id, _, _, _) = self.messageReference?.content {
                self.controllerInteraction.displayMessageTooltip(id, self.presentationData.strings.Conversation_ForwardAuthorHiddenTooltip, self, self.avatarNode.frame)
            } else if let peer = self.peer {
                if let adMessageId = self.adMessageId {
                    self.controllerInteraction.activateAdAction(adMessageId)
                } else {
                    if let channel = peer as? TelegramChannel, case .broadcast = channel.info {
                        self.controllerInteraction.openPeer(EnginePeer(peer), .chat(textInputState: nil, subject: nil, peekData: nil), self.messageReference, .default)
                    } else {
                        self.controllerInteraction.openPeer(EnginePeer(peer), .info, self.messageReference, .groupParticipant(storyStats: self.storyStats, avatarHeaderNode: self))
                    }
                }
            }
        }
    }
    
    private func updateVideoVisibility() {
        let isVisible = self.trackingIsInHierarchy
        self.avatarVideoNode?.updateVisibility(isVisible)
      
        if let videoNode = self.avatarVideoNode {
            videoNode.updateLayout(size: self.avatarNode.frame.size, cornerRadius: self.avatarNode.frame.size.width / 2.0, transition: .immediate)
            videoNode.frame = self.avatarNode.bounds
        }
    }
}
