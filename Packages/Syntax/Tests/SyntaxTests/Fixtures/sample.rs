use std::collections::HashMap;

#[derive(Debug)]
struct User {
    id: u64,
    name: String,
}

fn build_users() -> HashMap<u64, User> {
    let mut users = HashMap::new();
    users.insert(1, User { id: 1, name: "Ada".to_string() });
    users
}

fn main() {
    let users = build_users();
    let id = 1u64;
    match users.get(&id) {
        Some(user) => println!("{}: {}", user.id, user.name),
        None => eprintln!("missing user"),
    }
}
