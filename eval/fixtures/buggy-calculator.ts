/**
 * Simple calculator with basic arithmetic operations.
 * divide() should return results rounded to 3 decimal places.
 */
export class Calculator {
  add(a: number, b: number): number {
    return a + b;
  }

  subtract(a: number, b: number): number {
    return a - b;
  }

  multiply(a: number, b: number): number {
    return a * b;
  }

  divide(a: number, b: number): number {
    if (b === 0) {
      throw new Error("Cannot divide by zero");
    }
    // BUG: Math.floor truncates instead of rounding to 3 decimals
    return Math.floor((a / b) * 1000) / 1000;
  }
}
