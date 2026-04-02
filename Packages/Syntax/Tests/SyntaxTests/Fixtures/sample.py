from dataclasses import dataclass

@dataclass
class User:
    id: int
    name: str


def greet(user: User) -> str:
    return f"Hello, {user.name}!"


user = User(id=1, name="Ada")
print(greet(user))
