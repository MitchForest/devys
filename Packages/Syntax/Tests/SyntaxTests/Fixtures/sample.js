// sample.js
const nums = [1, 2, 3, 4];

function sum(values) {
  return values.reduce((acc, n) => acc + n, 0);
}

const result = sum(nums);
console.log(`sum: ${result}`);

class Greeter {
  #name;
  constructor(name) {
    this.#name = name;
  }
  greet() {
    return `Hello, ${this.#name}!`;
  }
}

export { sum, Greeter };
