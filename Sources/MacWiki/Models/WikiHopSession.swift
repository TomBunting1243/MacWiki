import Foundation

struct WikiHopSession: Codable, Equatable {
    enum Mode: String, Codable {
        case chill
        case rush
    }

    enum Status: String, Codable {
        case idle
        case active
        case completed
        case failed
    }

    let id: UUID
    let mode: Mode
    var status: Status
    
    let startArticle: Article
    let targetArticle: Article
    
    var currentTitle: String
    var clickCount: Int
    
    let startedAt: Date
    var completedAt: Date?
    
    var failureReason: String?
    
    init(mode: Mode, startArticle: Article, targetArticle: Article) {
        self.id = UUID()
        self.mode = mode
        self.status = .active
        self.startArticle = startArticle
        self.targetArticle = targetArticle
        self.currentTitle = startArticle.title
        self.clickCount = 0
        self.startedAt = Date()
    }
}
