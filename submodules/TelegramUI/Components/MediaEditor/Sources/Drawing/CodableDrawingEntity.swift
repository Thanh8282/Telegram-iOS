import Foundation
import TelegramCore

public func decodeCodableDrawingEntities(data: Data) -> [CodableDrawingEntity] {
    if let codableEntities = try? JSONDecoder().decode([CodableDrawingEntity].self, from: data) {
        return codableEntities
    }
    return []
}

public func decodeDrawingEntities(data: Data) -> [DrawingEntity] {
    return decodeCodableDrawingEntities(data: data).map { $0.entity }
}

public enum CodableDrawingEntity: Equatable {
    public static func == (lhs: CodableDrawingEntity, rhs: CodableDrawingEntity) -> Bool {
        return lhs.entity.isEqual(to: rhs.entity)
    }
    
    case sticker(DrawingStickerEntity)
    case text(DrawingTextEntity)
    case simpleShape(DrawingSimpleShapeEntity)
    case bubble(DrawingBubbleEntity)
    case vector(DrawingVectorEntity)
    case location(DrawingLocationEntity)
    case link(DrawingLinkEntity)
    
    public init?(entity: DrawingEntity) {
        if let entity = entity as? DrawingStickerEntity {
            self = .sticker(entity)
        } else if let entity = entity as? DrawingTextEntity {
            self = .text(entity)
        } else if let entity = entity as? DrawingSimpleShapeEntity {
            self = .simpleShape(entity)
        } else if let entity = entity as? DrawingBubbleEntity {
            self = .bubble(entity)
        } else if let entity = entity as? DrawingVectorEntity {
            self = .vector(entity)
        } else if let entity = entity as? DrawingLocationEntity {
            self = .location(entity)
        } else if let entity = entity as? DrawingLinkEntity {
            self = .link(entity)
        } else {
            return nil
        }
    }
    
    public var entity: DrawingEntity {
        switch self {
        case let .sticker(entity):
            return entity
        case let .text(entity):
            return entity
        case let .simpleShape(entity):
            return entity
        case let .bubble(entity):
            return entity
        case let .vector(entity):
            return entity
        case let .location(entity):
            return entity
        case let .link(entity):
            return entity
        }
    }
    
    private var coordinates: MediaArea.Coordinates? {
        var position: CGPoint?
        var size: CGSize?
        var rotation: CGFloat?
        var scale: CGFloat?
        
        switch self {
        case let .location(entity):
            position = entity.position
            size = entity.renderImage?.size
            rotation = entity.rotation
            scale = entity.scale
        case let .sticker(entity):
            var entityPosition = entity.position
            var entitySize = entity.baseSize
            let entityRotation = entity.rotation
            let entityScale = entity.scale
            
            if case .message = entity.content {
                let offset: CGFloat = 16.18 * entityScale //54.0 * entityScale / 3.337
                entitySize = CGSize(width: entitySize.width - 38.0, height: entitySize.height - 4.0)
                entityPosition = CGPoint(x: entityPosition.x + offset * cos(entityRotation), y: entityPosition.y + offset * sin(entityRotation))
            }
            
            position = entityPosition
            size = entitySize
            rotation = entityRotation
            scale = entityScale
        case let .link(entity):
            position = entity.position
            size = entity.renderImage?.size
            rotation = entity.rotation
            scale = entity.scale
        default:
            return nil
        }
        
        guard let position, let size, let scale, let rotation else {
            return nil
        }
        
        return MediaArea.Coordinates(
            x: position.x / 1080.0 * 100.0,
            y: position.y / 1920.0 * 100.0,
            width: size.width * scale / 1080.0 * 100.0,
            height: size.height * scale / 1920.0 * 100.0,
            rotation: rotation / .pi * 180.0,
            cornerRadius: nil
        )
    }
    
    public var mediaArea: MediaArea? {
        guard let coordinates = self.coordinates else {
            return nil
        }
        switch self {
        case let .location(entity):
            return .venue(
                coordinates: coordinates,
                venue: MediaArea.Venue(
                    latitude: entity.location.latitude,
                    longitude: entity.location.longitude,
                    venue: entity.location.venue,
                    address: entity.location.address,
                    queryId: entity.queryId,
                    resultId: entity.resultId
                )
            )
        case let .sticker(entity):
            if case let .file(_, type) = entity.content, case let .reaction(reaction, style) = type {
                var flags: MediaArea.ReactionFlags = []
                if case .black = style {
                    flags.insert(.isDark)
                }
                if entity.mirrored {
                    flags.insert(.isFlipped)
                }
                return .reaction(
                    coordinates: coordinates,
                    reaction: reaction,
                    flags: flags
                )
            } else if case let .message(messageIds, _, _, _, _) = entity.content, let messageId = messageIds.first {
                return .channelMessage(
                    coordinates: coordinates,
                    messageId: messageId
                )
            } else {
                return nil
            }
        case let .link(entity):
            var url = entity.url
            if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
                url = "https://\(url)"
            }
            return .link(
                coordinates: coordinates,
                url: url
            )
        default:
            return nil
        }
    }
}

extension CodableDrawingEntity: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case entity
    }

    private enum EntityType: Int, Codable {
        case sticker
        case text
        case simpleShape
        case bubble
        case vector
        case location
        case link
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EntityType.self, forKey: .type)
        switch type {
        case .sticker:
            self = .sticker(try container.decode(DrawingStickerEntity.self, forKey: .entity))
        case .text:
            self = .text(try container.decode(DrawingTextEntity.self, forKey: .entity))
        case .simpleShape:
            self = .simpleShape(try container.decode(DrawingSimpleShapeEntity.self, forKey: .entity))
        case .bubble:
            self = .bubble(try container.decode(DrawingBubbleEntity.self, forKey: .entity))
        case .vector:
            self = .vector(try container.decode(DrawingVectorEntity.self, forKey: .entity))
        case .location:
            self = .location(try container.decode(DrawingLocationEntity.self, forKey: .entity))
        case .link:
            self = .link(try container.decode(DrawingLinkEntity.self, forKey: .entity))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .sticker(payload):
            try container.encode(EntityType.sticker, forKey: .type)
            try container.encode(payload, forKey: .entity)
        case let .text(payload):
            try container.encode(EntityType.text, forKey: .type)
            try container.encode(payload, forKey: .entity)
        case let .simpleShape(payload):
            try container.encode(EntityType.simpleShape, forKey: .type)
            try container.encode(payload, forKey: .entity)
        case let .bubble(payload):
            try container.encode(EntityType.bubble, forKey: .type)
            try container.encode(payload, forKey: .entity)
        case let .vector(payload):
            try container.encode(EntityType.vector, forKey: .type)
            try container.encode(payload, forKey: .entity)
        case let .location(payload):
            try container.encode(EntityType.location, forKey: .type)
            try container.encode(payload, forKey: .entity)
        case let .link(payload):
            try container.encode(EntityType.link, forKey: .type)
            try container.encode(payload, forKey: .entity)
        }
    }
}
