declare module 'snarkjs' {
  export interface GrothProof {
    pi_a: string[];
    pi_b: string[][];
    pi_c: string[];
    protocol: string;
  }

  export interface PublicSignals {
    [key: string]: string;
  }

  export interface FullProveResult {
    proof: GrothProof;
    publicSignals: string[];
  }

  export const groth16: {
    fullProve(
      input: Record<string, any>,
      wasmPath: string,
      zkeyPath: string
    ): Promise<FullProveResult>;
    verify(
      vkey: Record<string, any>,
      publicSignals: string[],
      proof: GrothProof
    ): Promise<boolean>;
  };

  export const unstringifyBigInts: (obj: any) => any;
  export const stringifyBigInts: (obj: any) => any;
}
