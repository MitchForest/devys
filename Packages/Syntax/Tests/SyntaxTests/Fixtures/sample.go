package main

import (
	"fmt"
)

type User struct {
	ID   int
	Name string
}

func greet(user User) string {
	return fmt.Sprintf("Hello, %s", user.Name)
}

func main() {
	users := []User{{ID: 1, Name: "Devys"}}
	for _, user := range users {
		fmt.Println(greet(user))
	}
}
