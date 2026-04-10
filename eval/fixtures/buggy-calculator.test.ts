import { describe, it, expect } from "vitest";
import { Calculator } from "./buggy-calculator";

describe("Calculator", () => {
  const calc = new Calculator();

  it("adds two numbers", () => {
    expect(calc.add(2, 3)).toBe(5);
    expect(calc.add(-1, 1)).toBe(0);
  });

  it("subtracts two numbers", () => {
    expect(calc.subtract(5, 3)).toBe(2);
    expect(calc.subtract(1, 5)).toBe(-4);
  });

  it("multiplies two numbers", () => {
    expect(calc.multiply(3, 4)).toBe(12);
    expect(calc.multiply(-2, 3)).toBe(-6);
  });

  it("divides two numbers with rounding to 3 decimals", () => {
    expect(calc.divide(10, 2)).toBe(5);
    expect(calc.divide(10, 3)).toBe(3.333);  // FAILS: Math.floor gives 3.333, but 7/3 = 2.333 not 2.333
    expect(calc.divide(2, 3)).toBe(0.667);   // FAILS: Math.floor gives 0.666 instead of 0.667
    expect(calc.divide(1, 6)).toBe(0.167);   // FAILS: Math.floor gives 0.166 instead of 0.167
  });

  it("throws on division by zero", () => {
    expect(() => calc.divide(5, 0)).toThrow("Cannot divide by zero");
  });
});
