export type WalletFundingCurrency = "USDC";

export type WalletCreditFundingQuote = {
  provider: "base-usdc" | "veil-cash-placeholder";
  address: string;
  currency: WalletFundingCurrency;
  chainId: 8453;
  credits: number;
  expiresAt: string;
};

export interface WalletCreditFundingProvider {
  quote(input: { address: string; credits: number }): Promise<WalletCreditFundingQuote>;
  reconcile(input: { address: string; transactionHash: string }): Promise<{ creditsGranted: number; reference: string }>;
}

export class VeilCashFundingProviderPlaceholder implements WalletCreditFundingProvider {
  async quote(): Promise<WalletCreditFundingQuote> {
    throw new Error("VEIL_CASH_INTEGRATION_NOT_CONFIGURED");
  }

  async reconcile(): Promise<{ creditsGranted: number; reference: string }> {
    throw new Error("VEIL_CASH_INTEGRATION_NOT_CONFIGURED");
  }
}
