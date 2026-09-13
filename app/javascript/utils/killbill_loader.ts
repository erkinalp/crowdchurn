export type KillBillConfig = {
  publicKey: string | null;
  accountId: string | null;
};

export type KillBillSetupIntentResponse = {
  success: boolean;
  payment_method_id?: string;
  account_id?: string;
  error_message?: string;
};

export type KillBillClient = {
  config: KillBillConfig;
  createSetupIntent: (options: {
    walletAddress?: string;
    isCryptocurrency?: boolean;
  }) => Promise<{ paymentMethodId: string; accountId: string }>;
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
    createSetupIntent: async (options) => {
      const response = await fetch("/killbill/setup_intents", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          wallet_address: options.walletAddress,
          is_cryptocurrency: options.isCryptocurrency ?? false,
        }),
      });

      const data: KillBillSetupIntentResponse = await response.json();

      if (!response.ok || !data.success || !data.payment_method_id || !data.account_id) {
        throw new Error(data.error_message ?? "Failed to create Kill Bill setup intent");
      }
      return { paymentMethodId: data.payment_method_id, accountId: data.account_id };
    },
  };

  return killbillInstance;
}

export function resetKillBillInstance(): void {
  killbillInstance = null;
}
