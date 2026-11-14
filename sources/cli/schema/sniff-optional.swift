import FolioActions
import FolioDomain
import FolioStorage
import Foundation

protocol SniffOptional { static var wrapped: any Decodable.Type { get } }
