// sample.ts
export type ID = string | number;

export interface User {
  id: ID;
  name: string;
  isActive?: boolean;
}

export function toLabel(user: User): string {
  return `${user.id}:${user.name}`;
}

const user: User = { id: 42, name: "Ada" };
console.log(toLabel(user));
