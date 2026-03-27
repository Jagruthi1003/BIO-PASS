declare module 'circomlibjs' {
  export interface Poseidon {
    (inputs: bigint[]): bigint;
    hash(inputs: bigint[]): bigint;
  }

  export function buildPoseidon(): Promise<Poseidon>;

  export interface Num2Bits {
    (n: number): (input: bigint) => bigint[];
  }

  export function buildNum2Bits(): Promise<Num2Bits>;

  export interface LessThan {
    (input: { in: bigint; lt: bigint }): bigint;
  }

  export function buildLessThan(): Promise<LessThan>;
}
