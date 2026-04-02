using System;
using System.Collections.Generic;

public record User(int Id, string Name);

public static class Program {
    public static void Main() {
        var users = new List<User> { new User(1, "Devys") };
        foreach (var user in users) {
            Console.WriteLine($"Hello {user.Name}");
        }
    }
}
