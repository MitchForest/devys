data class User(val id: Int, val name: String)

fun greet(user: User): String {
    return "Hello ${user.name}!"
}

fun main() {
    val users = listOf(User(1, "Devys"))
    for (user in users) {
        println(greet(user))
    }
}
