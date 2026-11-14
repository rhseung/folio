import FolioDomain
import Foundation

public enum MaterialFileError: Error, Equatable {
    case outsideCourseFolder(String)
}
