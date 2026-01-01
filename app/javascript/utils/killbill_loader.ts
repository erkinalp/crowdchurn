export type KillBillConfig = {
  publicKey: string | null;
  accountId: string | null;
};

export type KillBillClient = {
  config: KillBillConfig;
  createPaymentMethod: (options: {
    walletAddress?: string;
    isCryptocurrency?: boolean;
  }) => Promise<{ paymentMethodId: string }>;
};

let killbillInstance: KillBillClient | null = null;

export function getKillBillConfig(): KillBillConfig {
  const publicKeyTag = document.querySelector<HTMLElement>('meta[name="killbill-public-key"]');
  const accountIdTag = document.querySelector<HTMLElement>('meta[name="killbill-account-id"]');

  return {
    publicKey: publicKeyTag?.getAttribute("content") ?? null,
    accountId: accountIdTag?.getAttribute("content") ?? null,
  };
}

export async function getKillBillInstance(): Promise<KillBillClient> {
  if (killbillInstance) return killbillInstance;

  const config = getKillBillConfig();

  if (!config.publicKey) {
    throw new Error("Kill Bill public key not found. Ensure meta[name='killbill-public-key'] is set.");
  }

  killbillInstance = {
    config,
    createPaymentMethod: async (options) => {
      const response = await fetch("/api/killbill/payment_methods", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-KillBill-ApiKey": config.publicKey ?? "",
        },
        body: JSON.stringify({
          account_id: config.accountId,
          wallet_address: options.walletAddress,
          is_cryptocurrency: options.isCryptocurrency,
        }),
      });

      if (!response.ok) {
        throw new Error("Failed to create Kill Bill payment method");
      }

      const data: { payment_method_id: string } = await response.json();
      return { paymentMethodId: data.payment_method_id };
    },
  };

  return killbillInstance;
}

export function resetKillBillInstance(): void {
  killbillInstance = null;
}
