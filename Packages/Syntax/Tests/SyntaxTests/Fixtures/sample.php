<?php
declare(strict_types=1);

class User {
    public function __construct(
        public int $id,
        public string $name
    ) {}
}

function greet(User $user): string {
    return "Hello {$user->name}!";
}

$users = [new User(1, "Devys")];
foreach ($users as $user) {
    echo greet($user) . PHP_EOL;
}
