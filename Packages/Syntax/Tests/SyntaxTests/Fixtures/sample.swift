import Foundation

struct User: Codable {
    let id: Int
    let name: String
}

func greet(_ user: User) -> String {
    return "Hello, \(user.name)!"
}

let user = User(id: 1, name: "Ada")
print(greet(user))
