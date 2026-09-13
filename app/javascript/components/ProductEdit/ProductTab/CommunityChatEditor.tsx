import * as React from "react";

import { Product } from "$app/components/ProductEdit/state";
import { ToggleSettingRow } from "$app/components/SettingRow";
import { Fieldset } from "$app/components/ui/Fieldset";
import { Label } from "$app/components/ui/Label";
import { Select } from "$app/components/ui/Select";

type CommunitySettings = Pick<Product, "community_chat_enabled" | "shared_community_id" | "available_communities">;

export const CommunityChatEditor = ({
  product,
  onChange,
}: {
  product: CommunitySettings;
  onChange: (update: Partial<CommunitySettings>) => void;
}) => {
  const uid = React.useId();

  return (
    <>
      <ToggleSettingRow
        label="Invite your customers to your community chat"
        value={product.community_chat_enabled}
        onChange={(community_chat_enabled) => onChange({ community_chat_enabled })}
        help={{ label: "Learn more", url: "/help/article/347-gumroad-community" }}
      />
      {product.community_chat_enabled && product.available_communities.length > 0 ? (
        <Fieldset>
          <Label htmlFor={uid}>Community</Label>
          <Select
            id={uid}
            value={product.shared_community_id ?? ""}
            onChange={(event) => onChange({ shared_community_id: event.target.value || null })}
          >
            <option value="">This product's community</option>
            {product.available_communities.map((community) => (
              <option key={community.id} value={community.id}>
                {community.name} (from {community.product_name})
              </option>
            ))}
          </Select>
        </Fieldset>
      ) : null}
    </>
  );
};
